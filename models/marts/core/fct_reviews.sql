-- ============================================================
-- 模型：fct_reviews（评价事实表）
-- 层级：DWD 明细层 marts/core
-- 物化：table
-- 粒度：一行 = 一条评价
-- ------------------------------------------------------------
-- ★ 【本模型处理一个真实的数据质量问题：一单多评】
--
--   业务设计上，一笔订单应该只有一条评价。
--   但真实的 Olist 数据里，部分 order_id 对应多条 review_id。
--
--   如果不处理直接 JOIN：
--     订单表 99,441 行 × 评价表 → 部分订单被复制成多行
--     → 所有金额 SUM 都会虚高！
--
--   这是维度建模里最危险的事故之一，术语叫：
--     【chasm trap（陷阱）】或【fan-out（扇出）】
--
-- 【处理方式：保留明细 + 标记重复 + 下游显式去重】
--   三步走：
--     ① 本层保留全部评价记录（不删除任何数据）
--     ② 计算"该订单是否重复评价"的标记位 is_duplicate_review
--     ③ 下游做订单级分析时，先按规则取一条（见 dws_seller_performance）
--
--   为什么不直接在这里删掉重复的？
--     因为"哪条是最新的"取决于业务规则，
--     不同分析场景可能选不同的规则。
--     在 DWD 层保留全部 + 打标记，把选择权交给下游，
--     才是正确的分层设计。
--
-- 【新手知识点：窗口函数 ROW_NUMBER()】
--   ROW_NUMBER() OVER (PARTITION BY 订单 ORDER BY 时间 DESC)
--
--   大白话：
--     先把数据按订单"分组"（PARTITION BY），
--     组内按评价时间倒序排队（ORDER BY ... DESC），
--     然后给每行编号 1、2、3...
--
--   所以 rn = 1 就是"该订单最新的一条评价"。
-- ============================================================

WITH reviews AS (
    SELECT
        r.review_key,
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_comment_title,
        r.review_comment_message,
        r.review_created_at,
        r.review_answered_at,

        -- 窗口函数：同一订单内，按评价时间倒序编号
        -- rn = 1 → 该订单最新的一条评价
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_created_at DESC NULLS LAST, r.review_id
        ) AS rn,

        -- 窗口函数：统计同一订单共有多少条评价
        COUNT(*) OVER (
            PARTITION BY r.order_id
        ) AS order_review_count,

        -- 窗口函数：统计同一 review_id 被多少个订单共用
        -- ★ 这是"一评多单"问题的监控标记
        --   实测：789 个 review_id 被多个订单共用，共影响 1,603 行
        --   计算验证：764×2 + 25×3 = 1,603 ✓
        COUNT(*) OVER (
            PARTITION BY r.review_id
        ) AS shared_id_count

    FROM {{ ref('stg_order_reviews') }} r
),

-- 关联订单，带出客户与时间属性
joined AS (
    SELECT
        rv.review_key,
        rv.review_id,
        rv.order_id,
        o.customer_id,
        rv.review_score,
        rv.review_created_at,
        rv.review_answered_at,
        rv.rn,
        rv.order_review_count,
        CAST(o.order_purchased_at AS DATE)          AS order_date,
        DATE_TRUNC('month', o.order_purchased_at)   AS order_month,

        -- 是否写了文字评论（只打分不写评论的很多）
        -- ⚠️ CAST 成 VARCHAR 再 TRIM：
        --    某些情况下该字段可能被推断为非字符串类型，
        --    直接 TRIM 会报 "No function matches trim(INTEGER)"
        CASE WHEN rv.review_comment_message IS NOT NULL
                  AND TRIM(CAST(rv.review_comment_message AS VARCHAR)) <> ''
             THEN TRUE ELSE FALSE END               AS has_comment,

        -- 平台是否回复
        CASE WHEN rv.review_answered_at IS NOT NULL
             THEN TRUE ELSE FALSE END               AS has_answer,

        -- ★ 质量问题标记 A：同一订单存在多条评价（一单多评）
        CASE WHEN rv.order_review_count > 1
             THEN TRUE ELSE FALSE END               AS is_duplicate_review,

        -- ★ 质量问题标记 B：同一评价ID被多个订单共用（一评多单）
        --   实测 789 个 review_id 存在共用，影响 1,603 行
        CASE WHEN rv.shared_id_count > 1
             THEN TRUE ELSE FALSE END               AS is_shared_review_id,

        -- ★ 是否为该订单的"有效评价"（最新一条）
        --   下游做订单级分析时用这个字段过滤，避免 fan-out
        CASE WHEN rv.rn = 1 THEN TRUE ELSE FALSE END AS is_latest_review

    FROM reviews rv
    LEFT JOIN {{ ref('stg_orders') }} o
        ON rv.order_id = o.order_id
)

SELECT * FROM joined
