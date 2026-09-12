-- ============================================================
-- 模型：ads_region_overview（区域销售概览）
-- 层级：ADS 应用集市层
-- ------------------------------------------------------------
-- 演示：事实表 JOIN 客户维度表，按地理维度看业务
-- 这张表可以直接给 Metabase 做地图/柱状图
-- ============================================================

SELECT
    c.region,                                        -- 大区（维度表里统一算好的）
    c.customer_state,                                -- 州
    c.is_core_market,                                -- 是否核心市场

    COUNT(DISTINCT f.order_id)                       AS orders,
    COUNT(DISTINCT f.customer_id)                    AS buyers,
    SUM(f.order_amount)                              AS gmv,
    ROUND(AVG(f.order_amount), 2)                    AS avg_order_value

FROM {{ ref('fct_orders') }} f
LEFT JOIN {{ ref('dim_customers') }} c
    ON f.customer_id = c.customer_id
WHERE f.is_delivered = TRUE
GROUP BY c.region, c.customer_state, c.is_core_market
ORDER BY gmv DESC
