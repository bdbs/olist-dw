# SQL 热身：5 小时从"只懂概念"到"能改会写"

> 学习方法：**抄 → 改 → 懂**
> 第一天抄一遍跑通，第二天改参数看变化，第三天才能自己写。
> **不要一上来就想原创**——这是小白放弃的头号原因。

---

## 第 1 小时：SELECT / WHERE / ORDER BY（查询基础）

### 原理：数据库就是一张Excel表

| SQL 概念 | Excel 类比 |
|---|---|
| 数据库 Database | 一个 Excel 文件 |
| 表 Table | 文件里的一个 Sheet |
| 列 Column | 表格里的列（字段） |
| 行 Row | 表格里的一行（记录） |
| SELECT | 选择要显示哪些列 |
| WHERE | 筛选（Excel 的"筛选"按钮） |
| ORDER BY | 排序 |

### 动手：打开 DuckDB 命令行

```powershell
# 在项目目录下
python -c "import duckdb; duckdb.connect('data/warehouse/olist.duckdb').sql('SELECT 1').show()"
```

更推荐：直接用 dbt 的方式练（后面每天都会用）。

### 练习 1：看一眼数据长什么样

```sql
-- 看订单表前 10 行
-- LIMIT 10 = 只看前10行，防止数据太多刷屏
SELECT *
FROM stg_orders
LIMIT 10;
```

### 练习 2：只看某几列

```sql
-- 只关心订单号和状态，不要把所有列都查出来
SELECT order_id, order_status
FROM stg_orders
LIMIT 10;
```

> 💡 **新手必记**：永远不要在生产环境写 `SELECT *`，
> 要什么列写什么列。这是职业素养，也是性能习惯。

### 练习 3：加条件（WHERE）

```sql
-- 只要已送达的订单
SELECT order_id, order_status
FROM stg_orders
WHERE order_status = 'delivered'
LIMIT 10;
```

### 练习 4：排序（ORDER BY）

```sql
-- 按下单时间倒序（最新的在前面）
SELECT order_id, order_purchased_at
FROM stg_orders
ORDER BY order_purchased_at DESC   -- DESC=倒序, ASC=正序(默认)
LIMIT 10;
```

### ✅ 第 1 小时自测

不看书，写出：**"查出 10 笔已取消的订单，按订单号排序"**

<details>
<summary>答案（先自己写再看）</summary>

```sql
SELECT order_id
FROM stg_orders
WHERE order_status = 'canceled'
ORDER BY order_id
LIMIT 10;
```
</details>

---

## 第 2 小时：聚合 GROUP BY（统计的核心）

### 原理：把很多行"压"成几行

Excel 的**数据透视表**就是这个东西。

```sql
-- 数一数每种状态各有多少订单
SELECT
    order_status,        -- 按什么分组
    COUNT(*) AS cnt      -- 每组有多少行
FROM stg_orders
GROUP BY order_status    -- 关键：按状态分组
ORDER BY cnt DESC;
```

**执行过程脑补**：
1. 数据库把所有订单按 `order_status` 分成 5 堆
2. 数每堆有多少行
3. 输出 5 行结果

### 常用聚合函数

| 函数 | 作用 | 例子 |
|---|---|---|
| `COUNT(*)` | 数行数 | 有多少笔订单 |
| `COUNT(DISTINCT x)` | 数不重复值 | 有多少个不同客户 |
| `SUM(x)` | 求和 | 总金额 |
| `AVG(x)` | 平均 | 客单价 |
| `MAX(x)` / `MIN(x)` | 最大/最小 | 最贵订单 |

### 练习：算总金额

```sql
SELECT
    COUNT(*)           AS 订单明细数,
    SUM(price)         AS 商品总额,
    AVG(price)         AS 平均单价,
    MAX(price)         AS 最贵商品
FROM stg_order_items;
```

### ⚠️ 新手第一大坑：NULLIF 防除零

```sql
-- ❌ 危险：如果订单数为 0，会报"除零错误"
SELECT SUM(price) / COUNT(*) FROM stg_order_items;

-- ✅ 安全：NULLIF(a, b) 的意思是"如果 a 等于 b，就返回 NULL"
SELECT SUM(price) / NULLIF(COUNT(*), 0) FROM stg_order_items;
```

### ✅ 第 2 小时自测

写出：**"统计每个客户下了多少单，只显示下单超过 2 单的客户"**

<details>
<summary>答案</summary>

```sql
SELECT customer_id, COUNT(*) AS order_cnt
FROM stg_orders
GROUP BY customer_id
HAVING COUNT(*) > 2        -- HAVING 是对分组后的结果再筛选
ORDER BY order_cnt DESC;
```

**注意**：`WHERE` 在分组前筛选，`HAVING` 在分组后筛选。
</details>

---

## 第 3 小时：JOIN（把表连起来）——最重要

### 原理：两张表按共同字段"拼"

```
订单表 stg_orders          客户表 stg_customers
┌────────┬──────────┐     ┌──────────┬────────┐
│order_id│customer_id│     │customer_id│ state  │
├────────┼──────────┤     ├──────────┼────────┤
│  001   │    C1    │     │    C1    │  SP    │
│  002   │    C2    │     │    C2    │  RJ    │
└────────┴──────────┘     └──────────┴────────┘
         │                        │
         └──── 用 customer_id 连接 ────┘
                    ▼
         ┌────────┬──────────┬──────┐
         │order_id│customer_id│ state│
         ├────────┼──────────┼──────┤
         │  001   │    C1    │  SP  │
         │  002   │    C2    │  RJ  │
         └────────┴──────────┴──────┘
```

### 四种 JOIN（先记两种）

| 类型 | 效果 | 什么时候用 |
|---|---|---|
| `INNER JOIN` | **只保留两边都能对上的** | 要严格匹配，丢掉脏数据 |
| `LEFT JOIN` | **保留左边全部**，右边对不上就填空 | 要保全左边，允许有缺失 |

**LEFT JOIN 记忆法**：LEFT = 左边的表是"老大"，一行都不能少。

### 练习：订单 + 客户

```sql
SELECT
    o.order_id,
    o.order_status,
    c.customer_state      -- 来自客户表
FROM stg_orders o              -- o 是别名，简写
LEFT JOIN stg_customers c      -- c 是别名
    ON o.customer_id = c.customer_id   -- 连接条件：ID 相等
LIMIT 10;
```

> 💡 **别名很重要**：表名太长时，`stg_orders o` 之后就能写 `o.order_id`。
> 这是所有 SQL 高手的习惯。

### ✅ 第 3 小时自测

写出：**"统计每个州的订单数，按订单数倒序"**

<details>
<summary>答案</summary>

```sql
SELECT c.customer_state, COUNT(*) AS order_cnt
FROM stg_orders o
LEFT JOIN stg_customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY order_cnt DESC;
```
</details>

---

## 第 4 小时：CTE 与窗口函数

### CTE（WITH 语句）：把复杂查询拆成几步

**为什么需要**：SQL 嵌套三层就没人看得懂了。CTE 让你"分步写"。

```sql
-- 用 WITH 定义一个临时结果，后面直接当表用
WITH delivered_orders AS (
    SELECT * FROM stg_orders WHERE order_status = 'delivered'
)
SELECT COUNT(*) FROM delivered_orders;
```

**类比**：CTE 就像 Excel 里的"中间计算表"，
先算好放一边，最后再引用。

### 窗口函数 OVER()：保留每一行，同时附加排名

**这是 SQL 从"会写"到"会分析"的分水岭。**

对比理解：
- `GROUP BY` = 把 50 个学生算成 1 个"平均分"（行数变少）
- `窗口函数` = 给 50 个学生每人加一列"你在班里排第几"（行数不变）

```sql
-- NTILE(4)：按某列排序后平均切成 4 档，标 1/2/3/4
SELECT
    customer_id,
    total_amount,
    NTILE(4) OVER (ORDER BY total_amount) AS amt_score  -- 1=最低档, 4=最高档
FROM (
    SELECT customer_id, SUM(price) AS total_amount
    FROM stg_order_items oi
    JOIN stg_orders o ON oi.order_id = o.order_id
    GROUP BY customer_id
);
```

### 常用窗口函数

| 函数 | 作用 |
|---|---|
| `ROW_NUMBER() OVER(...)` | 连续排名 1,2,3,4 |
| `RANK() OVER(...)` | 并列排名 1,2,2,4 |
| `NTILE(n) OVER(...)` | 平均分成 n 档 |
| `SUM(x) OVER(...)` | 累计求和 |

### ✅ 第 4 小时自测

说出 `NTILE(4) OVER (ORDER BY amount)` 的意思。

<details>
<summary>答案</summary>

把所有行按 amount 从小到大排队，平均切成 4 段，
最少的 25% 标 1 分，最多的 25% 标 4 分。
每行都拿到自己的分，**行数不变**。
</details>

---

## 第 5 小时：把知识串起来（跑通 RFM）

现在打开 `models/marts/analytics/dws_customer_rfm.sql`，
**你发现自己能读懂了**。

逐行对照：
1. `WITH customer_agg AS (...)` → 第 4 小时的 CTE
2. `GROUP BY f.customer_id` → 第 2 小时的聚合
3. `NTILE(4) OVER (ORDER BY ...)` → 第 4 小时的窗口函数
4. `CASE WHEN ... THEN ...` → 条件判断（类似 Excel 的 IF）

**能读懂 = 热身完成。**

---

## 学习固化：每天 10 分钟回顾表

| 概念 | 一句话 | 我是否理解 |
|---|---|---|
| SELECT/WHERE | 选列 + 筛选 | ☐ |
| GROUP BY | 分组统计（透视表） | ☐ |
| HAVING | 分组后再筛选 | ☐ |
| JOIN | 两表按共同字段拼 | ☐ |
| LEFT vs INNER | 左边全保留 vs 只留匹配 | ☐ |
| CTE (WITH) | 分步写复杂查询 | ☐ |
| 窗口函数 | 保留每行 + 附加排名 | ☐ |
| NULLIF | 防除零 | ☐ |

**一周内每天扫一遍这张表，知识就固化了。**
