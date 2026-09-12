-- ============================================================
-- 模型：stg_geolocation（地理位置贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view
-- 粒度：一行 = 一条邮编地理记录
-- ------------------------------------------------------------
-- 【⚠️ 这是本项目最大的一张表：100 万行】
--   它把你的数据规模从 34 万行直接拉到 155 万行。
--
-- 【本层要点：ODS 只搬运，不去重】
--   这张表有个著名的问题：
--     同一个邮编（zip_code_prefix）重复出现几百次，
--     每次的经纬度略有差异（同一区域不同测量点）。
--
--     1,000,163 行 → 实际只有约 19,000 个唯一邮编
--
--   ⚠️ 但是！ODS 层的职责是"忠实记录"，
--      所以这里【绝对不能去重】。
--      去重属于"加工"，必须放到 DWD 层（dim_geography）去做。
--
--   这是分层架构最容易违反的一条：
--   很多人图省事在 ODS 就 DISTINCT 了，
--   结果下游永远无法追溯"原始测量点有多少个"。
--
-- 【新手知识点：latitude / longitude 是什么？】
--   纬度（lat）：南北方向，赤道为 0，南半球为负
--   经度（lng）：东西方向，本初子午线为 0
--   巴西在南半球，所以纬度是负的（约 -5 ~ -33）
--
--   有了经纬度就能做地图可视化和距离计算，
--   比如"卖家到客户的平均配送距离"。
-- ============================================================

SELECT
    CAST(geolocation_zip_code_prefix AS VARCHAR)    AS zip_code_prefix,  -- 邮编前缀
    CAST(geolocation_lat AS DOUBLE)                 AS latitude,         -- 纬度
    CAST(geolocation_lng AS DOUBLE)                 AS longitude,        -- 经度
    LOWER(TRIM(geolocation_city))                   AS geo_city,         -- 城市
    UPPER(TRIM(geolocation_state))                  AS geo_state         -- 州
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_geolocation_dataset.csv',
    header = true
)
