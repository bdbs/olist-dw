-- ============================================================
-- 模型：stg_sellers（卖家贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view
-- 粒度：一行 = 一个卖家
-- ------------------------------------------------------------
-- 【本层要点】
--   1. 结构与 stg_customers 完全对称（同属"参与方"）
--   2. 城市名做去空格 + 小写标准化
--   3. 州名转大写，与 dim_customers 的口径保持一致
--
-- 【新手知识点：为什么要建卖家维度？】
--   之前的 fct_orders 里有 seller_id，但那只是个"退化维度"——
--   一串ID，没有城市、没有州，没法分析。
--
--   现在建了 dim_sellers 之后，就能回答：
--     - 哪个州的卖家贡献了最多 GMV？
--     - 卖家的地域分布和客户的地域分布匹配吗？
--     - 跨州配送的订单占比多少？（影响物流时效）
--
--   这就是"维度建模"的价值：
--   把一串无意义的ID，变成可以分组、可以下钻的分析维度。
-- ============================================================

SELECT
    CAST(seller_id AS VARCHAR)                      AS seller_id,               -- 卖家ID，主键
    CAST(seller_zip_code_prefix AS VARCHAR)         AS seller_zip_code_prefix,  -- 邮编前缀
    LOWER(TRIM(seller_city))                        AS seller_city,             -- 所在城市（标准化）
    UPPER(TRIM(seller_state))                       AS seller_state             -- 所在州（大写，如 SP/RJ）
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_sellers_dataset.csv',
    header = true
)
