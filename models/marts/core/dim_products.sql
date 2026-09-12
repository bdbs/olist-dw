-- ============================================================
-- 模型：dim_products（商品维度表）
-- 层级：DWD 明细层 marts/core
-- ============================================================

SELECT
    product_id,
    product_category,

    -- 品类中文名：BI 看板直接显示中文，不用分析师每次自己翻译
    CASE product_category
        WHEN 'electronics'            THEN '电子产品'
        WHEN 'home_appliance'         THEN '家用电器'
        WHEN 'furniture_decor'        THEN '家具装饰'
        WHEN 'books'                  THEN '图书'
        WHEN 'sports_leisure'         THEN '运动休闲'
        WHEN 'toys'                   THEN '玩具'
        WHEN 'health_beauty'          THEN '健康美容'
        WHEN 'computers_accessories'  THEN '电脑配件'
        WHEN 'watches_gifts'          THEN '钟表礼品'
        WHEN 'auto'                   THEN '汽车用品'
        ELSE '其他'
    END AS product_category_cn,

    product_weight_g,

    -- 重量分层：把连续数字变成几个档位，便于分组分析
    CASE
        WHEN product_weight_g >= 2000 THEN 'heavy'   -- 重货（影响物流成本）
        WHEN product_weight_g >= 500  THEN 'medium'
        WHEN product_weight_g > 0     THEN 'light'
        ELSE 'unknown'
    END AS weight_tier

FROM {{ ref('stg_products') }}
