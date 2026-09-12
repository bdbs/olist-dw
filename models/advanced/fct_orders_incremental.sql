-- ============================================================
-- 模型：fct_orders_incremental（订单事实表·增量版）
-- 层级：DWD 明细层
-- 物化：incremental（增量）
-- ------------------------------------------------------------
-- 【什么是增量模型？为什么要用它？】
--
--   全量模型（之前的 fct_orders）：
--     每次运行都把 12 万行全部删掉重算一遍。
--     数据少时无所谓，数据到千万行时，一次要跑几十分钟、烧很多钱。
--
--   增量模型：
--     第一次全量构建，之后【只处理新增的数据】。
--     好比写日记：不用每天把整本日记重抄一遍，只需在后面追加今天的。
--
-- 【实测效果】
--   源表新增 5,000 单 / 15,000 行明细
--   全量模型：重算 135,000 行
--   增量模型：只处理 15,000 行  → 效率提升约 9 倍
--
-- 【小白必读：is_incremental() 是什么意思？】
--   dbt 提供的一个特殊判断，作用是"问自己：我是第几次运行？"
--     · 第 1 次运行 → 返回 False → 走全量分支（建表）
--     · 第 2 次及以后 → 返回 True → 走增量分支（只追加新数据）
--
--   写法固定，记住就行：
--     {% if is_incremental() %}
--        -- 增量逻辑：只取新数据
--     {% else %}
--        -- 全量逻辑：取所有数据
--     {% endif %}
-- ============================================================

{{
    config(
        materialized = 'incremental',
        unique_key   = 'order_item_key',
        incremental_strategy = 'append'
    )
}}

WITH items AS (
    SELECT * FROM {{ ref('stg_order_items') }}
),
orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

joined AS (
    SELECT
        items.order_id || '-' || CAST(items.order_item_id AS VARCHAR)
                                                AS order_item_key,
        items.order_id,
        orders.customer_id,
        items.product_id,
        items.seller_id,
        orders.order_status,
        CAST(orders.order_purchased_at AS DATE)  AS order_date,
        DATE_TRUNC('month', orders.order_purchased_at) AS order_month,

        items.price,
        items.freight_value,
        COALESCE(items.price, 0) + COALESCE(items.freight_value, 0)
                                                AS order_amount,

        -- 口径标记位保持不变（口径下沉的设计不受增量影响）
        CASE WHEN orders.order_status = 'delivered' THEN TRUE ELSE FALSE END
                                                AS is_delivered,
        CASE WHEN orders.order_status = 'canceled' THEN TRUE ELSE FALSE END
                                                AS is_cancelled

    FROM items
    INNER JOIN orders ON items.order_id = orders.order_id
)

SELECT * FROM joined

-- ↓↓↓ 以下是增量模型的核心：只取"比现有数据更新的部分" ↓↓↓
{% if is_incremental() %}

WHERE order_date > (SELECT MAX(order_date) FROM {{ this }})

{% endif %}

-- 【逐字解释这行 WHERE】
--   {{ this }}          = 指代"当前这个模型自己"（即已建好的 fct_orders_incremental 表）
--   SELECT MAX(order_date) FROM {{ this }}
--                       = 查一下表里现在最大（最新）的日期是什么
--   WHERE order_date > ...
--                       = 只要比那个日期更新的数据
--
--   举例：表里最新是 2018-10-31，那么只有 11 月及以后的新订单会被追加进来。
--   历史数据一行都不碰 —— 这就是"增量"的本质。
--
--   坑1：迟到的历史数据（late-arriving data）
--        如果 10 月的订单在 11 月才进入源系统，上面的逻辑会漏掉它。
--        解法：加一个"回溯窗口"，比如
--          WHERE order_date > (SELECT MAX(order_date) - INTERVAL 7 DAY FROM {{ this }})
--        这样会重复处理最近 7 天，但保证不丢数据（配合 unique_key 去重）。
--
--   坑2：历史数据被修改
--        append 策略不会更新已存在的行。若源系统修改了历史订单金额，
--        增量模型感知不到。
--        解法：改用 merge 策略（按 unique_key 匹配更新），
--        或定期（如每月）做一次 --full-refresh 全量重建兜底。
-- ============================================================
