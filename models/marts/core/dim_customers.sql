-- ============================================================
-- 模型：dim_customers（客户维度表）
-- 层级：DWD 明细层 marts/core
-- ------------------------------------------------------------
-- 【什么是维度表？】
--   维度 = 你看数据的"角度"。
--   比如"按城市看 GMV"，城市就是维度，它来自客户表。
--   维度表通常行数少、列数多，是给事实表做"标签"用的。
--
-- 【星型模型长什么样？】
--                 dim_customers
--                       |
--   dim_products -- fct_orders -- dim_sellers
--
--   中间是事实表，周围一圈维度表，连线像星星，所以叫星型模型。
--
-- 【本表的治理价值：派生标准化字段】
--   原始数据只有州（SP/RJ/MG...），我们额外算出"大区 region"。
--   这样所有分析师用同一个 region 定义，不会出现口径打架。
-- ============================================================

SELECT
    -- ---- 主键 ----
    customer_id,

    -- ---- 原始属性 ----
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code,

    -- ---- 派生属性：在维度表里统一加工好，别让下游各写各的 ----
    CASE
        WHEN customer_state IN ('SP','RJ','MG','ES') THEN 'southeast'   -- 东南部
        WHEN customer_state IN ('PR','SC','RS')      THEN 'south'       -- 南部
        WHEN customer_state IN ('BA','PE','CE','RN') THEN 'northeast'   -- 东北部
        WHEN customer_state IN ('DF','GO','MT','MS') THEN 'center_west' -- 中西部
        ELSE 'other'
    END AS region,

    -- 是否核心城市（业务口径示例：圣保罗和里约为核心市场）
    CASE WHEN customer_state IN ('SP','RJ') THEN TRUE ELSE FALSE END
        AS is_core_market

FROM {{ ref('stg_customers') }}
