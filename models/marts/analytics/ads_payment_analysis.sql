-- ============================================================
-- 模型：ads_payment_analysis（支付方式分析看板表）
-- 层级：ADS 应用集市层 marts/analytics
-- 物化：table
-- 粒度：一行 = 一种支付方式
-- ------------------------------------------------------------
-- 【业务用途】
--   给财务/运营看：客户都怎么付钱？分期多不多？
--
--   这张表直接对应 Metabase 的一张看板：
--     支付方式占比饼图 + 分期数分布柱状图
--
-- 【为什么支付方式分析重要】
--   1. 资金成本：分期付款商家要垫资，12 期和 1 期成本差很多
--   2. 风险控制：boleto（巴西的线下付款单）有赖账风险
--   3. 产品设计：，voucher（优惠券）占比高说明促销力度大
--
--   credit_card  信用卡，主流
--   boleto       银行付款单，线下打印去银行/便利店付款
--                占巴西电商很大比例，但履约周期长、有违约风险
--   voucher      优惠券/代金券
--   debit_card   借记卡
--
-- 【新手知识点：百分比怎么算才安全】
--   SUM(x) / SUM(SUM(x)) OVER ()  ← 窗口函数算占比
--
--   或者用 NULLIF(分母, 0) 防除零：
--     a / NULLIF(b, 0)   -- b 为 0 时返回 NULL 而不是报错
--
--   这里用的是第一种：SUM(...) OVER () 表示"全表总计"，
--   不需要 GROUP BY 就能拿到总数，这是窗口函数的便利之处。
-- ============================================================

WITH payment_summary AS (
    SELECT
        payment_type,
        COUNT(*)                                    AS payment_count,     -- 支付笔数
        COUNT(DISTINCT order_id)                    AS order_count,       -- 覆盖订单数
        ROUND(SUM(payment_value), 2)                AS total_amount,      -- 总金额
        ROUND(AVG(payment_value), 2)                AS avg_amount,        -- 平均单笔金额
        ROUND(AVG(payment_installments), 2)         AS avg_installments,  -- 平均分期数
        -- 分期付款占比
        ROUND(100.0 * SUM(CASE WHEN is_installment THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2)             AS installment_rate_pct
    FROM {{ ref('fct_payments') }}
    WHERE is_orphan_payment = FALSE     -- 排除找不到订单的脏数据
    GROUP BY payment_type
)

SELECT
    payment_type,
    payment_count,
    order_count,
    total_amount,
    avg_amount,
    avg_installments,
    installment_rate_pct,

    -- 金额占比：用窗口函数 SUM() OVER () 拿全表总计
    ROUND(100.0 * total_amount / NULLIF(SUM(total_amount) OVER (), 0), 2)
                                                    AS amount_share_pct,

    -- 笔数占比
    ROUND(100.0 * payment_count / NULLIF(SUM(payment_count) OVER (), 0), 2)
                                                    AS count_share_pct

FROM payment_summary
ORDER BY total_amount DESC
