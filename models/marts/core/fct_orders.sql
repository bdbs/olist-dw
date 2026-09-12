-- ============================================================
-- 模型：fct_orders（订单明细事实表）
-- 层级：DWD 明细层 marts/core
-- 物化：table（真实建表）
-- ------------------------------------------------------------
-- 【这一层是数仓的心脏】
--   把订单表和明细表 JOIN 起来，形成"每一行 = 一个订单里的一个商品"，
--   并把后续分析需要的字段一次算好、口径统一。
--
-- 【新手知识点：JOIN 是什么？】
--   两张表按某个共同字段"拼"在一起。
--   好比你手上有一张"订单清单"和一张"客户名单"，
--   两张表都有"客户ID"，用这个 ID 就能把客户的城市拼到订单上。
--   INNER JOIN = 只保留两边都能对上的行。
--
-- 【⚠️ 本项目最重要的设计：口径统一（治理价值所在）】
--   订单有 5 种状态（delivered/shipped/canceled/processing/invoiced），
--   但业务上"GMV（成交总额）"只应该算【已送达 delivered】的订单。
--   如果这里不标记清楚，下游每个分析师各写各的过滤条件，
--   就会出现"三个人报三个 GMV 数字"的经典事故。
--   所以我们在这一层就把 is_delivered 标记好，下游直接引用，
--   不准再自己写 status 过滤——这就是【指标口径下沉】。
-- ============================================================

WITH items AS (
    -- 第一步：取出订单明细
    SELECT * FROM {{ ref('stg_order_items') }}
),
orders AS (
    -- 第二步：取出订单主表
    SELECT * FROM {{ ref('stg_orders') }}
),

joined AS (
    SELECT
        -- ---- 主键 ----
        -- 订单ID + 订单内序号 拼接，保证全表唯一
        items.order_id || '-' || CAST(items.order_item_id AS VARCHAR)
                                                AS order_item_key,

        -- ---- 外键（连接到各个维度表）----
        items.order_id,                          -- → 可连回订单
        orders.customer_id,                      -- → dim_customers
        items.product_id,                        -- → dim_products
        items.seller_id,                         -- → 卖家维度（本项目简化，未单独建维表）

        -- ---- 退化维度：事实表里直接存放的、有业务含义的字段 ----
        orders.order_status,
        CAST(orders.order_purchased_at AS DATE)  AS order_date,      -- 下单日期（去掉时分秒）
        DATE_TRUNC('month', orders.order_purchased_at) AS order_month, -- 下单月份，便于按月聚合

        -- ---- 度量值（可以 SUM/AVG 的数字）----
        items.price,                             -- 商品价格
        items.freight_value,                     -- 运费
        -- COALESCE(a,b)：如果 a 是空值就取 b。
        -- 这里防的是"价格为空导致整行金额变空"的连锁问题
        COALESCE(items.price, 0) + COALESCE(items.freight_value, 0)
                                                AS order_amount,     -- 订单行总金额

        -- ---- 口径标记位：这是治理的核心 ----
        CASE WHEN orders.order_status = 'delivered' THEN TRUE ELSE FALSE END
                                                AS is_delivered,     -- 是否成交（GMV 口径）
        CASE WHEN orders.order_status = 'canceled' THEN TRUE ELSE FALSE END
                                                AS is_cancelled      -- 是否取消（质量分析用）

    FROM items
    INNER JOIN orders
        ON items.order_id = orders.order_id
    -- INNER JOIN 的效果：明细里有、但订单主表里查不到的记录会被丢掉。
    -- 这叫"孤儿数据处理"。真实项目里要监控被丢了多少条（见 tests 目录）。
)

SELECT * FROM joined
