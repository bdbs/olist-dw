-- ============================================================
-- 模型：stg_order_payments（支付明细贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view
-- 粒度：一行 = 一笔订单的一次支付
-- ------------------------------------------------------------
-- 【本层要点】
--   1. 只做类型转换，不过滤任何数据
--   2. payment_type 保留原值（credit_card/boleto/voucher 等）
--   3. 判断逻辑一律留给下游
--
-- 【新手知识点：为什么一笔订单会有多笔支付？】
--   真实电商里很常见：
--     - 用礼品卡付一部分，剩下的刷信用卡
--     - 优惠券 + 现金组合支付
--   所以支付表的粒度比订单表更细：
--     订单表 orders      : 一行 = 一笔订单
--     支付表 payments    : 一行 = 一笔订单的一次支付
--   用 payment_sequential（1、2、3...）标识同一订单的第几笔。
--
--   这带来一个重要后果：
--     payment_value 直接 SUM 才是"实收金额"，
--     而订单金额 order_amount 是"应收金额"，
--     两者理论上应该相等，实际会有差异——这就是对账的起点。
-- ============================================================

SELECT
    CAST(order_id AS VARCHAR)                        AS order_id,              -- 订单ID，外键→stg_orders
    CAST(payment_sequential AS INTEGER)              AS payment_sequential,    -- 同一订单内第几笔支付
    LOWER(TRIM(payment_type))                        AS payment_type,          -- 支付方式
    CAST(payment_installments AS INTEGER)            AS payment_installments,  -- 分期数（1=一次性付清）
    CAST(payment_value AS DECIMAL(12,2))             AS payment_value          -- 该笔支付金额
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_order_payments_dataset.csv',
    header = true
)
