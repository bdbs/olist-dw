-- ============================================================
-- 宏：统一计算 GMV
-- ------------------------------------------------------------
-- 【宏是什么？】
--   宏 = 可复用的 SQL 片段，类似编程语言里的"函数"。
--   把重复出现的计算逻辑抽出来，一处定义、多处调用。
--
-- 【为什么要用宏？】
--   如果 10 个模型都要写 SUM(CASE WHEN is_delivered THEN ... END)，
--   改口径时要改 10 处。用宏只需要改 1 处。
--   这就是"口径统一"在工程上的实现。
--
-- 【怎么用？】
--   {{ calc_gmv('order_amount') }}
-- ============================================================

{% macro calc_gmv(amount_column) %}
    SUM(CASE WHEN is_delivered THEN {{ amount_column }} ELSE 0 END)
{% endmacro %}


{% macro calc_gmv_all(amount_column) %}
    -- ⚠️ 全口径，含取消订单，仅用于对比分析，禁止用于对外报表
    SUM({{ amount_column }})
{% endmacro %}
