-- ============================================================
-- 模型：ads_review_analysis（评价分析看板表 · 月度趋势）
-- 层级：ADS 应用集市层 marts/analytics
-- 物化：table
-- 粒度：一行 = 一个月份
-- ------------------------------------------------------------
-- 【业务用途】
--   给运营/客服看：客户满意度是在变好还是变差？
--
--   看板形态：
--     折线图：月度平均分趋势
--     堆叠图：各评分档位占比变化
--
-- 【★ 为什么评价趋势比交易趋势更早预警】
--   GMV 是【滞后指标】——客户不满意了，当月 GMV 可能还在涨（存量客户贡献）
--   评分是【先行指标】——客户开始不满，评分立刻下降
--
--   真实案例逻辑：
--     评分连续下滑 3 个月 → 6 个月后复购率崩塌 → GMV 才开始跌
--     等 GMV 跌了再救，客户已经流失完了。
--
--   所以成熟的经营分析会【同时看领先和滞后指标】。
--
-- 【评分区间设计】
--   1-2 分：差评（bad）
--   3  分：中评（neutral）
--   4-5 分：好评（good）
--
--   为什么 3 分算中评不算好评？
--     5 分制里，3 分意思是"一般、还行"，
--     在 NPS（净推荐值）体系里，只有 4-5 分才算推荐者（Promoter）。
--     这个划分标准要写进数据字典，全公司统一。
--
-- 【新手知识点：NULLIF 防除零】
--   SUM(CASE...) / NULLIF(COUNT(*), 0)
--   如果某个月一条评价都没有，COUNT(*) = 0，
--   直接除会报 "division by zero" 错误。
--   NULLIF(0, 0) 返回 NULL，于是整个算式返回 NULL 而不是崩溃。
-- ============================================================

WITH monthly_reviews AS (
    SELECT
        order_month,
        COUNT(*)                                        AS review_count,
        COUNT(DISTINCT order_id)                        AS reviewed_order_count,

        -- 平均分
        ROUND(AVG(review_score), 3)                     AS avg_review_score,

        -- 各评分区间数量
        SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS bad_count,
        SUM(CASE WHEN review_score = 3 THEN 1 ELSE 0 END)  AS neutral_count,
        SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END) AS good_count,

        -- 评论填写率：写了文字的评价占比
        SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)    AS with_comment_count

    FROM {{ ref('fct_reviews') }}
    WHERE is_latest_review = TRUE       -- ★ 每单只取最新评价，避免重复计数
      AND order_month IS NOT NULL
    GROUP BY order_month
)

SELECT
    order_month,
    review_count,
    reviewed_order_count,
    avg_review_score,

    -- ---- 各档位占比 ----
    ROUND(100.0 * bad_count     / NULLIF(review_count, 0), 2)  AS bad_rate_pct,
    ROUND(100.0 * neutral_count / NULLIF(review_count, 0), 2)  AS neutral_rate_pct,
    ROUND(100.0 * good_count    / NULLIF(review_count, 0), 2)  AS good_rate_pct,

    -- ---- 评论填写率 ----
    ROUND(100.0 * with_comment_count / NULLIF(review_count, 0), 2)
                                                               AS comment_rate_pct,

    -- ---- 净推荐值 NPS（简化版）----
    --   标准 NPS = 推荐者% - 贬损者%
    --   这里用：好评率 - 差评率
    ROUND(100.0 * (good_count - bad_count) / NULLIF(review_count, 0), 2)
                                                               AS nps_simplified,

    -- ---- 健康度评级（派生字段下沉）----
    CASE
        WHEN AVG(avg_review_score) OVER () IS NULL THEN 'unknown'
        WHEN avg_review_score >= 4.2 THEN 'excellent'   -- 优秀
        WHEN avg_review_score >= 3.8 THEN 'good'        -- 良好
        WHEN avg_review_score >= 3.5 THEN 'warning'     -- 预警
        ELSE 'critical'                                  -- 危险
    END                                                        AS health_level

FROM monthly_reviews
ORDER BY order_month
