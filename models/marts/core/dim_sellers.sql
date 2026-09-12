-- ============================================================
-- 模型：dim_sellers（卖家维度表）
-- 层级：DWD 明细层 marts/core
-- 物化：table
-- 粒度：一行 = 一个卖家
-- ------------------------------------------------------------
-- 【为什么现在才建卖家维度？】
--   之前 fct_orders 里 seller_id 只是一串ID（退化维度），
--   没法按地域分析。现在补齐了：
--
--     之前：只能问"哪个商品卖得好"
--     现在：能问"哪个州的卖家贡献最多 GMV"
--           "卖家和买家的地域分布匹配吗"
--           "跨州订单占比多少（影响物流时效）"
--
-- 【设计原则：与 dim_customers 保持对称】
--   两个维度都是"参与方"（Party），
--   字段结构、命名规则、派生逻辑都保持一致：
--     - 城市小写去空格
--     - 州名大写
--     - 同样的 region 大区划分
--     - 同样的 is_core_market 核心市场标记
--
--   这叫【一致性维度（Conformed Dimension）】——
--   Kimball 维度建模的核心概念之一：
--   同一含义的维度在不同事实表中必须口径一致，
--   否则跨主题分析时结果会对不上。
--
-- 【派生字段下沉】
--   region / is_core_market 在这里算好，
--   下游直接引用，禁止在 BI 里重复写 CASE WHEN。
-- ============================================================

SELECT
    -- ---- 主键 ----
    seller_id,

    -- ---- 地理属性 ----
    seller_zip_code_prefix,
    seller_city,
    seller_state,

    -- ---- 派生字段：大区划分（与 dim_customers 完全一致的口径）----
    CASE
        WHEN seller_state IN ('SP', 'RJ', 'MG')  THEN 'sudeste'      -- 东南部：经济最发达
        WHEN seller_state IN ('PR', 'SC', 'RS')  THEN 'sul'          -- 南部
        WHEN seller_state IN ('BA', 'PE', 'CE')  THEN 'nordeste'     -- 东北部
        WHEN seller_state IN ('DF', 'GO', 'MT')  THEN 'centro_oeste' -- 中西部
        ELSE 'outros'                                                 -- 其他
    END                                             AS region,

    -- ---- 派生字段：是否核心市场 ----
    -- SP（圣保罗）和 RJ（里约）是巴西经济最发达的两个州
    CASE WHEN seller_state IN ('SP', 'RJ')
         THEN TRUE ELSE FALSE END                   AS is_core_market

FROM {{ ref('stg_sellers') }}
