-- ============================================================
-- 通用测试（Generic Test）：数值区间校验
-- ------------------------------------------------------------
-- 【这是什么？】
--   通用测试 = 可以复用的质量规则。
--   写一次，在任何模型的任何字段上都能用。
--
-- 【为什么自己写而不用 dbt-expectations？】
--   1. 少一个第三方依赖，安装不踩坑
--   2. 规则逻辑完全可控、可解释
--
-- 【dbt 的测试约定】
--   返回行数 = 0 → 通过
--   返回行数 > 0 → 失败（返回的行就是违规数据）
--
-- 【怎么用？】
--   在 schema.yml 里写：
--     tests:
--       - assert_value_range:
--           min_value: 0
--           max_value: 200000
-- ============================================================

{% test assert_value_range(model, column_name, min_value=none, max_value=none) %}

SELECT *
FROM {{ model }}
WHERE {{ column_name }} IS NOT NULL
  AND (
    {% if min_value is not none %}
        {{ column_name }} < {{ min_value }}
    {% else %}
        FALSE
    {% endif %}
    OR
    {% if max_value is not none %}
        {{ column_name }} > {{ max_value }}
    {% else %}
        FALSE
    {% endif %}
  )

{% endtest %}
