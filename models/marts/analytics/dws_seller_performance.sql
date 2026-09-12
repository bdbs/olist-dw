-- ============================================================
-- 模型：dws_seller_performance（卖家绩效宽表）
-- 层级：DWS 轻度汇总层 marts/analytics
-- 物化：table
-- 粒度：一行 = 一个卖家
-- ------------------------------------------------------------
-- ★ 【本模型演示了一个必须避开的陷阱：fan-out（扇出）】
--
--   需求：算每个卖家的 GMV，同时算他的平均评分。
--
--   ❌ 错误写法（90% 的新手会这么写）：
--     SELECT seller_id, SUM(order_amount), AVG(review_score)
--     FROM fct_orders f
--     JOIN dim_sellers s ON ...
--     JOIN fct_reviews r ON f.order_id = r.order_id   -- ← 灾难开始
--     GROUP BY seller_id
--
--   为什么错？
--     一笔订单有 3 个商品 → fct_orders 有 3 行
--     这笔订单有 2 条评价 → JOIN 后变成 3 × 2 = 6 行
--     SUM(order_amount) 直接翻倍！
--
--   这叫 fan-out（扇出），是维度建模最隐蔽的事故：
--     不报错、不警告，只是数字悄悄变大了。
--
--   ✅ 正确做法：【先各自聚合到同一粒度，再 JOIN】
--     ① 订单侧：先按卖家聚合出 GMV（子查询 A）
--     ② 评价侧：先按卖家聚合出平均分（子查询 B）
--     ③ A LEFT JOIN B —— 两边粒度都是"一个卖家一行"，安全
--
--   这条规则叫【粒度对齐后再关联】，
--
-- 【为什么用 LEFT JOIN 而非 INNER JOIN】
--   有些卖家可能还没收到任何评价。
--   用 INNER JOIN 这些卖家会消失——
--   但"零评价的新卖家"恰恰是需要关注的群体。
--   所以保留，评分显示为 NULL。
-- ============================================================

WITH seller_sales AS (
    -- ① 订单侧：按卖家聚合销售指标
    SELECT
        f.seller_id,
        COUNT(DISTINCT f.order_id)                  AS order_count,      -- 订单数
        COUNT(*)                                    AS item_count,       -- 商品件数
        SUM(f.order_amount)                         AS gmv_all,          -- 含全部状态
        -- 标准口径：只算已送达
        SUM(CASE WHEN f.is_delivered THEN f.order_amount ELSE 0 END)
                                                    AS gmv_delivered,
        ROUND(AVG(CASE WHEN f.is_delivered THEN f.order_amount END), 2)
                                                    AS avg_order_value,  -- 平均订单金额
        COUNT(DISTINCT f.product_id)                AS product_count,    -- 在售商品数
        MIN(f.order_date)                           AS first_sale_date,  -- 首单日期
        MAX(f.order_date)                           AS last_sale_date    -- 末单日期
    FROM {{ ref('fct_orders') }} f
    GROUP BY f.seller_id
),

seller_reviews AS (
    -- ② 评价侧：按卖家聚合评分
    --    ⚠️ 必须先用 is_latest_review 过滤，避免一单多评导致重复计数
    SELECT
        f.seller_id,
        COUNT(DISTINCT rv.order_id)                 AS reviewed_order_count,
        COUNT(rv.review_id)                         AS review_count,
        ROUND(AVG(rv.review_score), 3)              AS avg_review_score,
        -- 好评率：4分及以上算好评
        ROUND(100.0 * SUM(CASE WHEN rv.review_score >= 4 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(rv.review_id), 0), 2)  AS good_review_rate_pct,
        -- 差评率：2分及以下
        ROUND(100.0 * SUM(CASE WHEN rv.review_score <= 2 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(rv.review_id), 0), 2)  AS bad_review_rate_pct
    FROM {{ ref('fct_reviews') }} rv
    INNER JOIN {{ ref('fct_orders') }} f
        ON rv.order_id = f.order_id
    WHERE rv.is_latest_review = TRUE     -- ★ 关键过滤：每个订单只取最新一条评价
    GROUP BY f.seller_id
)

-- ③ 两侧都聚合到"一个卖家一行"后，再安全关联
SELECT
    -- ---- 卖家属性（来自维度表）----
    s.seller_id,
    s.seller_city,
    s.seller_state,
    s.region,
    s.is_core_market,

    -- ---- 销售指标 ----
    COALESCE(sa.order_count, 0)                     AS order_count,
    COALESCE(sa.item_count, 0)                      AS item_count,
    COALESCE(sa.product_count, 0)                   AS product_count,
    ROUND(COALESCE(sa.gmv_delivered, 0), 2)         AS gmv_delivered,
    ROUND(COALESCE(sa.gmv_all, 0), 2)               AS gmv_all,
    COALESCE(sa.avg_order_value, 0)                 AS avg_order_value,
    sa.first_sale_date,
    sa.last_sale_date,

    -- ---- 评价指标 ----
    COALESCE(sr.review_count, 0)                    AS review_count,
    sr.avg_review_score,
    sr.good_review_rate_pct,
    sr.bad_review_rate_pct,

    -- ---- 派生分级：卖家价值分层 ----
    --    按 GMV 分档，逻辑下沉到数仓，避免 BI 层各写各的
    CASE
        WHEN COALESCE(sa.gmv_delivered, 0) >= 100000 THEN 'A_核心卖家'
        WHEN COALESCE(sa.gmv_delivered, 0) >= 20000  THEN 'B_重点卖家'
        WHEN COALESCE(sa.gmv_delivered, 0) > 0       THEN 'C_普通卖家'
        ELSE 'D_无成交'
    END                                             AS seller_tier,

    -- ---- 风险标记：有成交但评分低 ----
    CASE WHEN COALESCE(sa.gmv_delivered, 0) > 0
              AND sr.avg_review_score IS NOT NULL
              AND sr.avg_review_score < 3
         THEN TRUE ELSE FALSE END                   AS is_risk_seller

FROM {{ ref('dim_sellers') }} s
LEFT JOIN seller_sales sa    ON s.seller_id = sa.seller_id
LEFT JOIN seller_reviews sr  ON s.seller_id = sr.seller_id
