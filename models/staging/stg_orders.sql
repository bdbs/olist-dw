-- ============================================================
-- 模型：stg_orders（订单贴源模型）
-- 层级：ODS 贴源层 staging
-- ------------------------------------------------------------
-- 【本层要点】
--   1. 只做类型转换和改名，不做业务过滤
--   2. 时间字段统一转成标准 timestamp 类型
--   3. order_status 保留原值，判断逻辑留给下游
--
-- 【新手知识点：CAST 是什么？】
--   CAST(x AS 类型) = 强制类型转换。
--   好比 Excel 里把"文本格式的数字"改成"数值格式"。
--   数据库里如果类型不对，做比较和计算会出错，
--   所以贴源层第一件事就是把类型理顺。
-- ============================================================

SELECT
    CAST(order_id AS VARCHAR)                    AS order_id,        -- 订单ID，主键
    CAST(customer_id AS VARCHAR)                 AS customer_id,     -- 客户ID，外键→stg_customers
    LOWER(TRIM(order_status))                    AS order_status,    -- 订单状态
    CAST(order_purchase_timestamp AS TIMESTAMP)  AS order_purchased_at -- 下单时间
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_orders_dataset.csv',
    header = true
)
