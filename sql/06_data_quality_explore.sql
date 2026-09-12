-- ============================================================
-- 真实 Olist 数据质量探查（换成 Kaggle 数据后必跑）
-- ------------------------------------------------------------
-- 目的：摸清真实数据有多脏，为质量规则提供依据
-- 产出：把结果填进 docs/02_数据质量基线.md
-- ============================================================

-- ① 总规模
SELECT
    (SELECT COUNT(*) FROM raw_orders)      AS 订单数,
    (SELECT COUNT(*) FROM raw_order_items) AS 明细数,
    (SELECT COUNT(*) FROM raw_customers)   AS 客户数,
    (SELECT COUNT(*) FROM raw_products)    AS 商品数;


-- ② 商品品类缺失（真实数据已知存在，约 600+ 条）
SELECT COUNT(*) AS 品类缺失商品数
FROM raw_products
WHERE product_category_name IS NULL;


-- ③ 订单状态分布（确认 GMV 口径基础）
SELECT order_status, COUNT(*) AS cnt
FROM raw_orders GROUP BY order_status ORDER BY cnt DESC;


-- ④ 有没有"下了单却没商品"的订单
SELECT COUNT(*) AS 无明细订单数
FROM raw_orders o
LEFT JOIN raw_order_items i ON o.order_id = i.order_id
WHERE i.order_id IS NULL;


-- ⑤ 外键失效检查：明细里的商品在商品表找不到
SELECT COUNT(*) AS 孤儿商品数
FROM raw_order_items i
LEFT JOIN raw_products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL;


-- ⑥ 外键失效检查：订单里的客户在客户表找不到
SELECT COUNT(*) AS 孤儿客户数
FROM raw_orders o
LEFT JOIN raw_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


-- ⑦ 时间逻辑倒挂：送达时间早于下单时间
SELECT COUNT(*) AS 时间倒挂数
FROM raw_orders
WHERE TRY_CAST(order_delivered_customer_date AS TIMESTAMP)
      < TRY_CAST(order_purchase_timestamp AS TIMESTAMP);


-- ⑧ 价格异常
SELECT
    COUNT(*)                                          AS 总行数,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END)     AS 空价格,
    SUM(CASE WHEN price <= 0   THEN 1 ELSE 0 END)      AS 非正价格
FROM raw_order_items;


-- ⑨ 客户城市/州是否为空
SELECT
    SUM(CASE WHEN customer_city  IS NULL OR customer_city  = '' THEN 1 ELSE 0 END) AS 空城市,
    SUM(CASE WHEN customer_state IS NULL OR customer_state = '' THEN 1 ELSE 0 END) AS 空州
FROM raw_customers;


-- ⑩ 时间跨度（确认数据覆盖的业务周期）
SELECT
    MIN(TRY_CAST(order_purchase_timestamp AS DATE)) AS 最早订单日,
    MAX(TRY_CAST(order_purchase_timestamp AS DATE)) AS 最晚订单日
FROM raw_orders;


-- ============================================================
-- 📋 把以上每条的实测数字记进 docs/02_数据质量基线.md
--
-- 然后用「探查 → 定位 → 修复 → 补断言防复发」五步法处理，
-- 处理过程就是你的《数据质量问题台账》，
-- ============================================================
