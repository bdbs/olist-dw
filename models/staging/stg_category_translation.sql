-- ============================================================
-- 模型：stg_category_translation（品类名称翻译贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view
-- 粒度：一行 = 一个品类名称的翻译对照
-- ------------------------------------------------------------
-- 【这张表很小（71 行），但价值很高】
--   Olist 是巴西电商，商品品类名是葡萄牙文：
--     'beleza_saude'      → 'health_beauty'
--     'informatica_acessorios' → 'computers_accessories'
--
--   虽然葡文名本身也能用（而且带下划线其实可读性还行），
--   但有了官方映射表，可以：
--     1. 统一成英文，降低理解成本
--     2. 建立"标准代码"与"业务名称"的对照关系
--
-- 【治理视角：这是一张"参照数据"表】
--   在数据治理里，这类表叫 Reference Data（参照数据/码表）：
--     - 数据量小、变更少
--     - 被其他表大量引用
--     - 是数据标准的重要组成部分
--
--   典型的企业码表：
--     性别代码（M/F/U）、币种代码、行政区划代码、
--     行业分类代码（GB/T 4754）、组织部门编码
--
--   管理要点：
--     - 必须有唯一 owner（谁负责维护）
--     - 变更要走审批流程
--     - 下游引用时要用外键约束，防止出现"孤儿编码"
--
-- ============================================================

SELECT
    LOWER(TRIM(product_category_name))          AS category_name_pt,   -- 葡萄牙文原名（主键）
    LOWER(TRIM(product_category_name_english))  AS category_name_en    -- 英文标准名
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/product_category_name_translation.csv',
    header = true
)
