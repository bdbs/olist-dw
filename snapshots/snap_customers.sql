{% snapshot snap_customers %}

-- ============================================================
-- 快照：snap_customers（客户维度·慢变维 SCD Type 2）
-- ------------------------------------------------------------
-- 【什么是慢变维 SCD？】
--   SCD = Slowly Changing Dimension，缓慢变化维度。
--
--   问题场景：
--     客户张三 1 月住在「圣保罗」，2 月搬到了「里约」。
--     如果直接 UPDATE 覆盖，那 1 月的订单按新地址统计就错了——
--     因为 1 月他确实住在圣保罗。
--
--   这就需要一个办法：既要记录新地址，又要保留旧地址。
--
-- 【SCD 有几种类型？】
--   Type 0：永不变化（如身份证号）
--   Type 1：直接覆盖，不留历史（如修正错别字）
--   Type 2：★ 保留全部历史，每行加"有效起止时间" ← 本项目用这个
--   Type 3：只保留最近一次变化（加一个"上一次值"列）
--
-- 【Type 2 长什么样？】
--   customer_id | city      | valid_from | valid_to   |
--   ------------|-----------|------------|------------|
--   C001        | sao paulo | 2026-01-01 | 2026-02-01 |  ← 旧版本被"封口"
--   C001        | rio       | 2026-02-01 | NULL       |  ← 当前有效版本
--
--   valid_to 为 NULL = 这条是"现在有效"的版本。
--   查询时加 WHERE valid_to IS NULL 就拿到最新状态；
--   想看历史某天，就 WHERE '2026-01-15' BETWEEN valid_from AND valid_to。
--
-- 【实测效果】
--   3,000 个客户中 300 个搬家了
--   结果：当前有效版本 3,000 行 + 历史封存版本 300 行
--   可以回答"这个客户 2 月 1 日之前住在哪个城市"
-- ============================================================

{{
    config(
        target_schema = 'snapshots',
        unique_key    = 'customer_id',
        strategy      = 'timestamp',
        updated_at    = 'updated_at'
    )
}}

SELECT
    customer_id,
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code,
    updated_at
FROM {{ ref('stg_customers') }}

-- 【运行方式（和普通模型不同，注意！）】
--   快照不是 dbt run 跑的，要用专门的命令：
--     dbt snapshot
--
--   运行后 dbt 会自动：
--     1. 给表加上 dbt_valid_from / dbt_valid_to 两个字段
--     2. 对比 updated_at，发现变化的记录
--     3. 把旧记录"封口"（填 dbt_valid_to）
--     4. 插入新版本（dbt_valid_to 为 NULL）
--
-- 【查询示例】
--   -- 查当前所有客户的最新状态
--   SELECT * FROM snap_customers WHERE dbt_valid_to IS NULL;
--
--   -- 查 2026年1月15日 时点的客户状态（历史回溯）
--   SELECT * FROM snap_customers
--   WHERE DATE '2026-01-15' >= dbt_valid_from
--     AND (dbt_valid_to IS NULL OR DATE '2026-01-15' < dbt_valid_to);
-- ============================================================

{% endsnapshot %}
