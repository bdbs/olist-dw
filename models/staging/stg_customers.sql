-- ============================================================
-- 模型：stg_customers（客户贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view（视图，不存数据）
-- ------------------------------------------------------------
-- 【这一层是干什么的？】
--   贴源层 = 原样搬运 + 简单改名。
--   你可以理解为"把 Excel 表原封不动搬进数据库，顺便把列名整理干净"。
--   这一层【不做任何业务逻辑】，不加筛选、不做计算。
--
-- 【为什么要这一层？新手常问】
--   因为原始数据的列名可能是拼音、缩写、甚至乱码。
--   统一在这里改成规范的英文小写下划线命名（snake_case），
--   后面所有层都基于这层开发。以后原始表列名变了，
--   只需要改这一层，下游全都不用动——这就是"解耦"。
--
-- 【关于 updated_at 字段】
--   本层额外生成一个 updated_at（最后更新时间），
--   它是给 SCD 慢变维快照（snapshots/snap_customers.sql）用的：
--   快照靠对比这个字段来判断"客户信息有没有变化"。
--   真实项目里这个字段通常来自源系统的数据库时间戳；
--   本项目 CSV 里没有，所以用数据装载时间代替。
-- ============================================================

SELECT
    CAST(customer_id AS VARCHAR)          AS customer_id,          -- 客户ID，主键
    CAST(customer_unique_id AS VARCHAR)   AS customer_unique_id,   -- 客户唯一标识（同一人可能有多条）
    CAST(customer_zip_code_prefix AS VARCHAR) AS customer_zip_code,  -- 邮编前缀（源字段名为 _prefix）
    LOWER(TRIM(customer_city))            AS customer_city,        -- 城市：去空格+转小写，避免"Sao Paulo"和"sao paulo"被当成两个城市
    UPPER(TRIM(customer_state))           AS customer_state,       -- 州：去空格+转大写，统一格式
    -- 供 SCD 慢变维快照使用的更新时间戳
    CURRENT_TIMESTAMP                     AS updated_at
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_customers_dataset.csv',
    header = true
)
