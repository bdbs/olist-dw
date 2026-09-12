-- ============================================================
-- 模型：ads_kpi_summary（核心指标汇总表 / 指标目录）
-- 层级：ADS 应用集市层 marts/analytics
-- 物化：table
-- 粒度：一行 = 一个指标
-- ------------------------------------------------------------
-- ★ 【为什么要有这张表：它是治理岗的核心交付物】
--
--   之前的做法：指标散落在各个 ADS 表里
--     ads_gmv_monthly      里有 GMV、客单价、取消率
--     ads_review_analysis  里有好评率、平均评分
--     dws_customer_rfm     里有客户分层
--
--   带来的问题（这正是企业里最常见的治理痛点）：
--     ① 同一个指标在不同报表里算法不同，数字对不上
--     ② 新人不知道"总营收"该查哪张表
--     ③ 指标改了口径，没人知道影响了哪些报表
--
--   本表的作用：【把指标集中管理起来】
--     每个指标的【口径】和【数值】写在一起，
--     查数值的同时就看到了定义——从源头消除歧义。
--
--   这在治理体系里叫【指标目录 / 指标字典】，
--   是 DCMM「数据应用」与「数据标准」两个能力域的交汇点。
--
-- 【为什么用长表（一行一指标）而不是宽表（一列一指标）】
--   宽表：指标1 | 指标2 | 指标3 ...
--     ❌ 新增指标要加列，表结构要改
--   长表：指标名 | 指标值 | 口径 | 责任人
--     ✅ 新增指标只需 INSERT 一行，表结构不变
--
--   长表更适合做【目录】——因为目录的本质是"清单"，
--   而清单天然是纵向增长的。
--
-- 【新手知识点：UNION ALL 是什么】
--   把多个查询结果【上下拼接】（不是左右拼接）。
--   要求：各段的列数相同、类型兼容。
--
--   JOIN   = 左右拼（加列）
--   UNION  = 上下拼（加行），且会去重
--   UNION ALL = 上下拼，【不去重】（更快，本表用这个）
-- ============================================================

WITH gmv AS (
    -- 交易域：从月度 GMV 表汇总全周期指标
    SELECT
        ROUND(SUM(gmv_delivered), 2) AS gmv_delivered,
        ROUND(SUM(gmv_all), 2)       AS gmv_all,
        SUM(delivered_orders)        AS delivered_orders,
        SUM(total_orders)            AS total_orders,
        SUM(cancelled_orders)        AS cancelled_orders,
        ROUND(AVG(avg_order_value), 2) AS avg_order_value,
        ROUND(AVG(cancel_rate_pct), 2) AS avg_cancel_rate,
        COUNT(*)                     AS month_count
    FROM {{ ref('ads_gmv_monthly') }}
),

cust AS (
    -- 客户域：客户总数、复购客户数
    SELECT
        COUNT(*)                                        AS customer_total,
        SUM(CASE WHEN frequency > 1 THEN 1 ELSE 0 END)  AS repeat_customer
    FROM {{ ref('dws_customer_rfm') }}
),

review AS (
    -- 评价域：满意度相关
    SELECT
        COUNT(*)                                                  AS review_total,
        ROUND(AVG(review_score), 3)                               AS avg_score_alltime,
        ROUND(AVG(good_rate_pct), 2)                              AS good_rate,
        ROUND(AVG(bad_rate_pct), 2)                               AS bad_rate
    FROM {{ ref('fct_reviews') }} r
    LEFT JOIN {{ ref('ads_review_analysis') }} a
        ON r.order_month = a.order_month
    WHERE r.is_latest_review = TRUE
),

seller AS (
    -- 卖家域
    SELECT
        COUNT(*)                                        AS seller_total,
        SUM(CASE WHEN gmv_delivered > 0 THEN 1 ELSE 0 END) AS active_seller
    FROM {{ ref('dws_seller_performance') }}
),

pay AS (
    -- 支付域：实收金额（与应收对账）
    SELECT ROUND(SUM(payment_value), 2) AS paid_amount
    FROM {{ ref('fct_payments') }}
    WHERE is_orphan_payment = FALSE
)

-- ============================================================
-- 指标 1-6：交易域
-- ============================================================
SELECT
    'KPI001'                                    AS metric_id,
    'GMV（标准口径）'                             AS metric_name_cn,
    'gmv_delivered'                             AS metric_name_en,
    '交易域'                                     AS metric_domain,
    CAST(gmv_delivered AS DECIMAL(18,2))        AS metric_value,
    'BRL'                                       AS metric_unit,
    '全周期'                                     AS calc_period,
    '仅统计 order_status = delivered 的订单金额，为对外统一口径' AS metric_definition,
    'ads_gmv_monthly.gmv_delivered'             AS data_source,
    '数据团队'                                   AS metric_owner,
    '每日'                                       AS update_freq
FROM gmv

UNION ALL
SELECT 'KPI002', 'GMV（含全部订单）', 'gmv_all', '交易域',
    CAST(gmv_all AS DECIMAL(18,2)), 'BRL', '全周期',
    '含全部状态订单，仅用于对账对比，【不对外发布】',
    'ads_gmv_monthly.gmv_all', '数据团队', '每日'
FROM gmv

UNION ALL
SELECT 'KPI003', 'GMV口径差异', 'gmv_gap', '交易域',
    CAST(gmv_all - gmv_delivered AS DECIMAL(18,2)), 'BRL', '全周期',
    '含全部订单口径 减 标准口径，衡量取消订单对营收的影响',
    'ads_gmv_monthly 计算得出', '数据团队', '每日'
FROM gmv

UNION ALL
SELECT 'KPI004', '订单总量', 'total_orders', '交易域',
    CAST(total_orders AS DECIMAL(18,2)), '单', '全周期',
    '源系统订单表总行数。⚠️ 注意：事实表 fct_orders 因 INNER JOIN 会少 775 单，本指标取自源表口径',
    'ads_gmv_monthly.total_orders', '数据团队', '每日'
FROM gmv

UNION ALL
SELECT 'KPI005', '平均客单价', 'avg_order_value', '交易域',
    CAST(avg_order_value AS DECIMAL(18,2)), 'BRL', '全周期',
    '标准口径GMV / 已送达订单数',
    'ads_gmv_monthly.avg_order_value 均值', '数据团队', '每日'
FROM gmv

UNION ALL
SELECT 'KPI006', '平均取消率', 'cancel_rate', '交易域',
    CAST(avg_cancel_rate AS DECIMAL(18,2)), '%', '全周期',
    '取消订单数 / 订单总量 × 100%',
    'ads_gmv_monthly.cancel_rate_pct 均值', '数据团队', '每日'
FROM gmv

-- ============================================================
-- 指标 7-9：客户域
-- ============================================================
UNION ALL
SELECT 'KPI007', '客户总数', 'customer_total', '客户域',
    CAST((SELECT customer_total FROM cust) AS DECIMAL(18,2)), '人', '全周期',
    '有下单行为的唯一客户数（按 customer_unique_id 口径）',
    'dws_customer_rfm', '数据团队', '每日'

UNION ALL
SELECT 'KPI008', '复购客户数', 'repeat_customer', '客户域',
    CAST((SELECT repeat_customer FROM cust) AS DECIMAL(18,2)), '人', '全周期',
    '下单次数 > 1 的客户数',
    'dws_customer_rfm.frequency', '数据团队', '每日'

UNION ALL
SELECT 'KPI009', '复购率', 'repeat_rate', '客户域',
    CAST(ROUND(100.0 * (SELECT repeat_customer FROM cust)
        / NULLIF((SELECT customer_total FROM cust), 0), 2) AS DECIMAL(18,2)),
    '%', '全周期',
    '复购客户数 / 客户总数 × 100%',
    'dws_customer_rfm 计算得出', '数据团队', '每日'

-- ============================================================
-- 指标 10-12：评价域
-- ============================================================
UNION ALL
SELECT 'KPI010', '平均评分', 'avg_review_score', '评价域',
    CAST((SELECT avg_score_alltime FROM review) AS DECIMAL(18,2)), '分', '全周期',
    '1-5 分制，5 分最高。取每笔订单最新一条评价（is_latest_review = TRUE）',
    'fct_reviews.review_score', '数据团队', '每日'

UNION ALL
SELECT 'KPI011', '好评率', 'good_rate', '评价域',
    CAST((SELECT good_rate FROM review) AS DECIMAL(18,2)), '%', '全周期',
    '评分 >= 4 的评价占比。口径约定：4-5 好评、3 中评、1-2 差评',
    'ads_review_analysis.good_rate_pct', '数据团队', '每日'

UNION ALL
SELECT 'KPI012', '差评率', 'bad_rate', '评价域',
    CAST((SELECT bad_rate FROM review) AS DECIMAL(18,2)), '%', '全周期',
    '评分 <= 2 的评价占比，为先行预警指标',
    'ads_review_analysis.bad_rate_pct', '数据团队', '每日'

-- ============================================================
-- 指标 13-15：卖家域 / 支付域 / 参照
-- ============================================================
UNION ALL
SELECT 'KPI013', '卖家总数', 'seller_total', '卖家域',
    CAST((SELECT seller_total FROM seller) AS DECIMAL(18,2)), '家', '全周期',
    '平台注册卖家总数',
    'dws_seller_performance', '数据团队', '每日'

UNION ALL
SELECT 'KPI014', '活跃卖家数', 'active_seller', '卖家域',
    CAST((SELECT active_seller FROM seller) AS DECIMAL(18,2)), '家', '全周期',
    '统计周期内 GMV > 0 的卖家数',
    'dws_seller_performance.gmv_delivered', '数据团队', '每日'

UNION ALL
SELECT 'KPI015', '实收金额', 'paid_amount', '支付域',
    CAST((SELECT paid_amount FROM pay) AS DECIMAL(18,2)), 'BRL', '全周期',
    '支付表 payment_value 合计，用于与应收（GMV）对账。已排除孤儿支付',
    'fct_payments.payment_value', '财务/数据团队', '每日'

UNION ALL
SELECT 'KPI016', '覆盖月份数', 'month_count', '参照',
    CAST((SELECT month_count FROM gmv) AS DECIMAL(18,2)), '月', '全周期',
    '数据覆盖的自然月数量，反映数据集时间跨度',
    'ads_gmv_monthly', '数据团队', '每日'

ORDER BY metric_id
