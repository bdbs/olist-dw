-- ============================================================
-- 模型：ads_gmv_monthly（月度 GMV 趋势）—— 业务看板核心表
-- 层级：ADS 应用集市层 marts/analytics
-- ------------------------------------------------------------
-- 【本表是"口径教学"的重点，请仔细看注释】
--
-- 我们同时算出【三个 GMV 数字】，它们不一样：
--   1. gmv_all         所有订单金额（含取消的）  ← ❌ 错误口径
--   2. gmv_delivered   只算已送达               ← ✅ 正确口径
--   3. gmv_cancelled   被取消的金额             ← 用于分析损失
--
-- 【为什么这是本项目的点睛之笔？】
--   真实项目里，90% 的"数据对不上"事故都源于口径不一致：
--   财务按已送达算，运营按全部算，两个人报两个数字，吵半天。
--
--   治理岗的正确做法不是"谁对谁错"，而是：
--     ① 在 DWD 层定义清楚标记位（fct_orders.is_delivered）
--     ② 在 ADS 层显式列出各种口径，让人一眼看到差异
--     ③ 在数据字典里写明"对外统一使用 gmv_delivered"
--
--   "我发现 GMV 对不上，定位到是口径问题，做了口径下沉和字典固化。"
-- ============================================================

SELECT
    -- 时间维度：按月
    DATE_TRUNC('month', order_date)                        AS order_month,

    -- 订单维度
    COUNT(DISTINCT order_id)                               AS total_orders,
    COUNT(DISTINCT CASE WHEN is_delivered THEN order_id END) AS delivered_orders,
    COUNT(DISTINCT CASE WHEN is_cancelled THEN order_id END) AS cancelled_orders,

    -- 客户维度
    COUNT(DISTINCT customer_id)                            AS total_buyers,

    -- ---- 金额口径三兄弟 ----
    SUM(order_amount)                                      AS gmv_all,        -- ❌ 含取消
    SUM(CASE WHEN is_delivered THEN order_amount ELSE 0 END) AS gmv_delivered, -- ✅ 标准口径
    SUM(CASE WHEN is_cancelled THEN order_amount ELSE 0 END) AS gmv_cancelled, -- 取消金额

    -- 客单价：注意分母也要跟着口径走！
    -- 这是新手常犯的错：分子排除了取消单，分母却用总订单数
    SUM(CASE WHEN is_delivered THEN order_amount ELSE 0 END)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_delivered THEN order_id END), 0)
                                                           AS avg_order_value,

    -- 取消率：一个重要的业务健康度指标
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN is_cancelled THEN order_id END)
             / NULLIF(COUNT(DISTINCT order_id), 0)
    , 2)                                                   AS cancel_rate_pct

FROM {{ ref('fct_orders') }}
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY order_month
