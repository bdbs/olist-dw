-- ============================================================
-- 模型：stg_products（商品贴源模型）
-- 层级：ODS 贴源层 staging
-- ============================================================

SELECT
    CAST(product_id AS VARCHAR)              AS product_id,          -- 商品ID，主键
    LOWER(TRIM(product_category_name))        AS product_category,    -- 品类（源字段名为 _name）
    CAST(product_weight_g AS INTEGER)        AS product_weight_g,    -- 重量（克）
    CAST(product_length_cm AS INTEGER)       AS product_length_cm,
    CAST(product_height_cm AS INTEGER)       AS product_height_cm
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_products_dataset.csv',
    header = true
)
