-- ============================================================
-- 模型：stg_order_reviews（订单评价贴源模型）
-- 层级：ODS 贴源层 staging
-- 物化：view
-- 粒度：一行 = 一条评价
-- ------------------------------------------------------------
-- 【本层要点】
--   1. 只做类型转换，不过滤
--   2. review_score 保留 1-5 原值
--   3. 评论文本可能为空（用户只打分不写评论），这是正常现象
--
-- 【新手知识点：为什么评价表也要单独建模？】
--   评价是"客户体验"主题的核心数据。
--   没有它，你只能分析"卖了多少"，无法分析"客户满不满意"。
--
--   业务价值链条：
--     交易域（卖了多少钱）
--       + 评价域（客户满不满意）
--       = 完整经营视图
--
--   典型分析：
--     - 评分低的品类是哪些？（商品质量问题）
--     - 配送时长与评分的关系？（物流问题）
--     - 评分低的客户还会复购吗？（留存问题）
--
-- 【⚠️ 真实数据的一个坑：reviews 与 orders 是多对多关系】
--
--   实测发现两个方向都不正常：
--     问题A：一个 order_id  → 多条 review_id  （一单多评）
--     问题B：一个 review_id → 多个 order_id   （一评多单）
--
--   两个方向合起来 = 多对多关系，
--   而业务设计上本应是一对一。
--
-- 【⚠️★ 更严重的问题：review_id 单独不是主键】
--   实测数据（真实 Olist）：
--     评价表总行数        99,224
--     唯一 review_id      98,410
--     重复 review_id          789 个
--     ├─ 对应 2 个 order_id   764 个
--     └─ 对应 3 个 order_id    25 个
--     验证：764×1 + 25×2 = 814 = 99,224 - 98,410 ✓
--
--   但同时：
--     完全重复行（review_id + order_id 都相同）= 0 条
--
--   ★ 这说明：【组合键 (review_id, order_id) 是唯一的主键】
--     而 review_id 单独不是。
--
-- 【处理方式：自造代理键】
--   源系统没有可靠主键时，数仓必须自己造一个：
--     review_key = review_id || '-' || order_id
--
--   为什么不在 ODS 层去重？
--     分层规范规定 ODS 只做"忠实记录"，
--     去重/加工属于 DWD 层职责。
--     而且这 789 条不是"脏重复"（完全重复行=0），
--     是业务上真实存在的多对多关系，不能删。
-- ============================================================

SELECT
    -- ★ 组合代理键：review_id 单独不唯一，必须拼上 order_id
    CAST(review_id AS VARCHAR) || '-' || CAST(order_id AS VARCHAR)
                                                        AS review_key,           -- 主键（组合代理键）
    CAST(review_id AS VARCHAR)                          AS review_id,            -- 评价ID（⚠️ 非唯一）
    CAST(order_id AS VARCHAR)                           AS order_id,             -- 订单ID，外键→stg_orders
    CAST(review_score AS INTEGER)                       AS review_score,         -- 评分 1-5（5最好）
    CAST(review_comment_title AS VARCHAR)               AS review_comment_title, -- 评论标题（常为空）
    CAST(review_comment_message AS VARCHAR)             AS review_comment_message, -- 评论正文（常为空）
    CAST(review_creation_date AS TIMESTAMP)             AS review_created_at,    -- 评价提交时间
    CAST(review_answer_timestamp AS TIMESTAMP)          AS review_answered_at    -- 平台回复时间
FROM read_csv_auto(
    '{{ var("raw_path", "data/raw") }}/olist_order_reviews_dataset.csv',
    header = true
)
