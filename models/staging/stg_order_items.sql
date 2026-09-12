-- ============================================================
-- 模型：stg_order_items（订单明细贴源模型）
-- 层级：ODS 贴源层 staging
-- ------------------------------------------------------------
-- 【这是整个数仓最重要的一张原始表】
--   它记录了"每笔订单里具体买了什么、多少钱"。
--   数仓里的"事实表"就是由它加工而来的。
--
-- 【新手知识点：什么是事实表？】
--   数据分两类：
--     事实（Fact）  = 发生过的事情，可量化 → 卖了多少钱、多少件
--     维度（Dimension）= 观察事情的角度 → 哪个客户、哪个商品、哪天
--   订单明细就是典型的事实，金额和数量是它的"度量值"。
-- ============================================================

SELECT
    CAST(order_id AS VARCHAR)                AS order_id,       -- 订单ID，外键→stg_orders
    CAST(order_item_id AS INTEGER)           AS order_item_id,  -- 订单内序号（同一订单从1递增）
    CAST(product_id AS VARCHAR)               AS product_id,     -- 商品ID，外键→stg_products
    CAST(seller_id AS VARCHAR)               AS seller_id,      -- 卖家ID
    CAST(price AS DECIMAL(10,2))             AS price,          -- 商品价格（不含运费）
    CAST(freight_value AS DECIMAL(10,2))     AS freight_value   -- 运费
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_order_items_dataset.csv',
    header = true
)
