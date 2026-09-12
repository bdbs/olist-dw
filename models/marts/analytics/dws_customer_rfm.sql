-- ============================================================
-- 模型：dws_customer_rfm（客户价值分层）
-- 层级：DWS 轻度汇总层 marts/analytics
-- ------------------------------------------------------------
-- 【RFM 是什么？营销领域的经典客户分群模型】
--   R (Recency)  最近一次购买距今多久 → 越近越好
--   F (Frequency)购买频次            → 越多越好
--   M (Monetary) 累计消费金额        → 越多越好
--   三个维度各打分，组合出"重要价值客户""流失客户"等群体。
--
-- 【新手重点：窗口函数 OVER()】
--   普通 GROUP BY 会把多行压成一行，原始数据没了。
--   窗口函数不一样：它【保留每一行】，同时在每行上"附加"一个计算结果。
--
--   NTILE(4) OVER (ORDER BY 金额)
--   大白话：把所有行按金额从小到大排队，
--           平均切成 4 段（ quartile 四分位），
--           最穷的那 25% 标 1 分，最富的 25% 标 4 分。
--           每行都能拿到自己的分数，行数不变。
--
--   对比理解：
--     GROUP BY  = 把班级 50 人算成 1 个"平均分"
--     窗口函数  = 给 50 个人每人后面加一列"你在班里排第几档"
-- ============================================================

WITH customer_agg AS (
    -- 第一步：先把每个客户汇总成一行（这是普通的 GROUP BY）
    SELECT
        f.customer_id,
        MAX(f.order_date)                  AS last_order_date,  -- 最近下单日
        COUNT(DISTINCT f.order_id)         AS frequency,        -- 买了多少单
        SUM(f.order_amount)                AS monetary          -- 一共花了多少
    FROM {{ ref('fct_orders') }} f
    -- ⚠️ 口径：只统计已送达订单。这里引用的是 DWD 层统一好的标记位，
    --    而不是自己写 order_status='delivered'——这就是口径下沉的好处
    WHERE f.is_delivered = TRUE
    GROUP BY f.customer_id
)

-- 第二步：在汇总结果上打分（这里用窗口函数）
SELECT
    customer_id,
    last_order_date,
    frequency,
    monetary,

    -- R 分：最近购买时间越新，分越高
    NTILE(4) OVER (ORDER BY last_order_date) AS r_score,

    -- F 分：买得越勤，分越高
    NTILE(4) OVER (ORDER BY frequency)       AS f_score,

    -- M 分：花得越多，分越高
    NTILE(4) OVER (ORDER BY monetary)        AS m_score,

    -- 总分 3~12，用于粗分层
    (NTILE(4) OVER (ORDER BY last_order_date)
     + NTILE(4) OVER (ORDER BY frequency)
     + NTILE(4) OVER (ORDER BY monetary))    AS rfm_total,

    -- 业务分层：把分数翻译成人话
    CASE
        WHEN NTILE(4) OVER (ORDER BY last_order_date) >= 3
         AND NTILE(4) OVER (ORDER BY frequency) >= 3
         AND NTILE(4) OVER (ORDER BY monetary) >= 3
            THEN '高价值客户'          -- 三个都高，重点维护
        WHEN NTILE(4) OVER (ORDER BY last_order_date) <= 1
         AND NTILE(4) OVER (ORDER BY monetary) >= 3
            THEN '重要挽留客户'        -- 花得多但很久没来了，赶紧召回
        WHEN NTILE(4) OVER (ORDER BY last_order_date) >= 3
         AND NTILE(4) OVER (ORDER BY monetary) <= 1
            THEN '新客/低价值'         -- 最近来了但没怎么花钱
        WHEN NTILE(4) OVER (ORDER BY last_order_date) <= 1
         AND NTILE(4) OVER (ORDER BY frequency) <= 1
            THEN '流失客户'            -- 又久没来、买得又少
        ELSE '一般客户'
    END AS rfm_segment

FROM customer_agg
