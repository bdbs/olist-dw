-- ============================================================
-- 模型：ads_category_sales（品类销售分析）
-- 层级：ADS 应用集市层
-- ------------------------------------------------------------
-- 【本表演示：事实表 JOIN 维度表的标准用法】
--   fct_orders 里只有 product_id（一串数字，人看不懂）
--   dim_products 里有品类名和中文名
--   把两张表用 product_id 连起来，就能"按品类看销售额"
--
-- 这也是星型模型存在的意义：
--   事实表存"发生了什么"，维度表存"这是什么"，
--   分析时按需连接，既省空间又灵活。
-- ============================================================

SELECT
    p.product_category,                              -- 品类英文
    p.product_category_cn,                           -- 品类中文（BI 直接展示）
    p.weight_tier,                                   -- 重量档位

    COUNT(DISTINCT f.order_id)                       AS orders,
    COUNT(DISTINCT f.customer_id)                    AS buyers,
    SUM(f.order_amount)                              AS gmv,
    ROUND(AVG(f.order_amount), 2)                    AS avg_order_value,

    -- 占比：窗口函数的一个妙用——算每行占总和的百分比
    -- SUM(...) OVER () 括号里为空 = 对全表求和
    ROUND(100.0 * SUM(f.order_amount)
          / NULLIF(SUM(SUM(f.order_amount)) OVER (), 0), 2)
                                                     AS gmv_share_pct

FROM {{ ref('fct_orders') }} f
LEFT JOIN {{ ref('dim_products') }} p
    ON f.product_id = p.product_id
WHERE f.is_delivered = TRUE          -- 统一口径：只算已送达
GROUP BY p.product_category, p.product_category_cn, p.weight_tier
ORDER BY gmv DESC
