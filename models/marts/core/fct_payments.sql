-- ============================================================
-- 模型：fct_payments（支付事实表）
-- 层级：DWD 明细层 marts/core
-- 物化：table
-- 粒度：一行 = 一笔订单的一次支付
-- ------------------------------------------------------------
-- 【支付域的核心价值：从"卖了多少"到"收了多少"】
--   订单金额 order_amount  = 应收（客户该付多少）
--   支付金额 payment_value = 实收（实际收到多少）
--
--   这两个数字理论上应该相等，实际上经常不等：
--     - 优惠券抵扣
--     - 分期手续费
--     - 部分退款
--     - 系统对账差异
--
--   做支付事实表，就是用数据把"应收 vs 实收"的缺口量化出来。
--   【这是财务域和交易域对账的基础，是治理岗的典型工作场景。】
--
-- 【粒度决策：为什么保留"一次支付"而不是汇总到订单？】
--   保留最细粒度（一次支付）：
--     ✅ 能分析"组合支付"占比（多少订单用了两种以上支付方式）
--     ✅ 能分析分期行为（多少人选了 12 期）
--     ✅ 可以上卷到订单（SUM 即可）
--
--   如果一开始就汇总到订单粒度：
--     ❌ 支付方式结构信息永久丢失
--
--   再次印证那条原则：【尽可能保留最细粒度】
--
-- 【新手知识点：LEFT JOIN 在这里的必要性】
--   支付表里有极少数 order_id 在订单表找不到（脏数据）。
--   用 INNER JOIN 会静默丢掉这些支付记录——
--   而"钱收到了但订单找不到"恰恰是最需要告警的情况！
--
--   所以这里用 LEFT JOIN 保留全部支付记录，
--   再用 is_orphan 标记位显式暴露问题。
--   （对比 fct_orders 用 INNER JOIN，那是另一种权衡，
--     因为事实表粒度纯洁性优先。这里的权衡点不同：
--     支付记录涉及钱，宁可脏也不能丢。）
-- ============================================================

SELECT
    -- ---- 主键：订单ID + 支付序号 拼接 ----
    p.order_id || '-' || CAST(p.payment_sequential AS VARCHAR)
                                            AS payment_key,

    -- ---- 外键 ----
    p.order_id,                             -- → stg_orders
    o.customer_id,                          -- → dim_customers

    -- ---- 退化维度：支付方式相关属性 ----
    p.payment_type,                         -- credit_card / boleto / voucher / debit_card
    p.payment_installments,                 -- 分期数

    -- ---- 订单时间属性（从订单表带过来，便于按时间聚合）----
    CAST(o.order_purchased_at AS DATE)      AS order_date,
    DATE_TRUNC('month', o.order_purchased_at) AS order_month,

    -- ---- 度量值 ----
    p.payment_value,                        -- 本次支付金额

    -- ---- 口径标记位（治理核心）----
    -- 是否分期：分期数 > 1 即为分期付款
    CASE WHEN p.payment_installments > 1
         THEN TRUE ELSE FALSE END           AS is_installment,

    -- 是否一次性付清
    CASE WHEN p.payment_installments = 1
         THEN TRUE ELSE FALSE END           AS is_full_payment,

    -- 是否信用卡（巴西主流支付方式）
    CASE WHEN p.payment_type = 'credit_card'
         THEN TRUE ELSE FALSE END           AS is_credit_card,

    -- ★ 质量问题标记：支付记录找不到对应订单
    --   这是【钱收了但订单不存在】的严重异常，必须可见
    CASE WHEN o.order_id IS NULL
         THEN TRUE ELSE FALSE END           AS is_orphan_payment

FROM {{ ref('stg_order_payments') }} p
LEFT JOIN {{ ref('stg_orders') }} o
    ON p.order_id = o.order_id
