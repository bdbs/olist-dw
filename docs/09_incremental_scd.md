# 进阶补丁：增量模型与慢变维（SCD）

> 适用时机：**完成 Day 1-7 基础版之后**再来做
> 预计耗时：2-3 小时

---

## 为什么要做这个补丁



如果你答"全量"，对方会认为这是玩具项目。

做完这个补丁，你可以答：

> "核心事实表我改造成了增量模型，并实现了客户维度的 SCD Type 2 历史追踪。
> 同时我知道增量的边界——迟到数据和历史修改需要额外处理。"

**这一句话，就把项目从"学习 demo"拉到"接近生产"的水平。**

---

## 补丁 1：增量模型（约 1.5 小时）

### 问题：全量刷新有什么毛病

```
每天跑一次 dbt run
  → 删掉 12 万行
  → 重新计算 12 万行
  → 其中 99% 的数据根本没变过
```

数据量到千万行时，这就是**浪费几十分钟 + 大量计算资源**。

### 解法：增量模型

```
第 1 次：全量构建（建表）
第 2 次起：只处理"比上次更新的数据"
```

### 文件位置

`models/advanced/fct_orders_incremental.sql`

### 核心代码（带逐字解释）

```sql
{{
    config(
        materialized = 'incremental',      -- ① 物化方式改成增量
        unique_key   = 'order_item_key',   -- ② 用哪个字段判断"重复"
        incremental_strategy = 'append'    -- ③ 只追加，不覆盖
    )
}}
```

**③ 的三种策略怎么选？**

| 策略 | 行为 | 适用 |
|---|---|---|
| `append` | 只追加新行 | 数据只增不改（如日志、订单） |
| `merge` | 按主键匹配，存在则更新、不存在则插入 | 数据会被修改（如客户信息） |
| `delete+insert` | 删掉受影响分区再插入 | 按分区更新的场景 |

**本项目用 append**：订单一旦产生就不会改，适合追加。

```sql
{% if is_incremental() %}
WHERE order_date > (SELECT MAX(order_date) FROM {{ this }})
{% endif %}
```

**逐字解释**：

| 片段 | 含义 |
|---|---|
| `is_incremental()` | dbt 问："我是第几次跑？" 第1次=False，之后=True |
| `{{ this }}` | 指代"当前这个模型自己" |
| `MAX(order_date)` | 表里现在最新的日期 |
| `WHERE order_date >` | 只要比它更新的 |

### 实测效果

```
第1次 全量构建 : 112,650 行
源表新增       : 5,000 单 / 15,000 行明细
第2次 增量后   : 134,998 行（新增 14,999）→ 历史一行未动 ✅
```

效率提升约 **9 倍**（只处理 1/9 的数据）。

#### 坑 1：迟到数据（late-arriving data）

**场景**：10 月的订单，11 月才进源系统。

`WHERE order_date > MAX(order_date)` 会**永久漏掉**这批数据。

**解法**：加回溯窗口

```sql
WHERE order_date > (SELECT MAX(order_date) - INTERVAL 7 DAY FROM {{ this }})
```

重复处理最近 7 天，配合 `unique_key` 去重，牺牲一点性能换数据完整。

#### 坑 2：历史数据被修改

**场景**：源系统把某笔历史订单的金额改了。

`append` 策略**感知不到**，数仓里还是旧值。

**解法**（三选一）：

1. 改用 `merge` 策略（按主键更新）
2. 定期 `--full-refresh` 全量重建兜底（如每月一次）
3. 源系统保证数据不可变（最理想）

> "我用 append 策略，因为订单数据基本只增不改。
> 同时我清楚它的边界：迟到数据用回溯窗口兜底，
> 历史修改用定期全量重建兜底。"

---

## 补丁 2：SCD Type 2 慢变维（约 1.5 小时）

### 问题：维度表被覆盖会出错

```
1月：客户张三住「圣保罗」，下了 10 单
2月：张三搬到了「里约」
```

如果直接 UPDATE 覆盖：

```
统计 1 月"圣保罗的订单" → 张三的 10 单消失了 ❌
```

因为 1 月他确实住圣保罗，历史分析必须保留旧地址。

### 解法：SCD Type 2

**每一行加"有效起止时间"**：

| customer_id | city | valid_from | valid_to |
|---|---|---|---|
| C001 | sao paulo | 2026-01-01 | 2026-02-01 | ← 旧版本被"封口" |
| C001 | rio | 2026-02-01 | NULL | ← 当前有效 |

`valid_to IS NULL` = 现在有效。

### SCD 的四种类型

| 类型 | 行为 | 适用 |
|---|---|---|
| **Type 0** | 永不变化 | 身份证号、出生日期 |
| **Type 1** | 直接覆盖，不留历史 | 修正错别字 |
| **Type 2** | ★ 保留全部历史版本 | 客户地址、商品价格 |
| **Type 3** | 只留最近一次变化（加"上次值"列） | 只需要对比新旧时 |

### 文件位置

`snapshots/snap_customers.sql`

### 运行方式（⭐ 注意：不是 dbt run）

```bash
dbt snapshot          # 快照必须用这个命令
dbt run               # 这个跑不到快照！
```

这是新手最容易懵的地方。

### 配置含义

```sql
{{
    config(
        target_schema = 'snapshots',
        unique_key    = 'customer_id',   -- 用它识别"同一个客户"
        strategy      = 'timestamp',     -- 靠时间戳判断变化
        updated_at    = 'updated_at'     -- 源表的更新时间字段
    )
}}
```

**strategy 两种怎么选？**

| 策略 | 判断方式 | 适用 |
|---|---|---|
| `timestamp` | 对比 `updated_at` 字段 | 源表有可靠的更新时间戳 |
| `check` | 直接对比指定字段的值 | 源表没有时间戳 |

`check` 写法：

```sql
strategy   = 'check',
check_cols = ['customer_city', 'customer_state']
```

### 前置准备

快照需要源表有 `updated_at` 字段。我已把它加进 `stg_customers.sql`：

```sql
CURRENT_TIMESTAMP AS updated_at
```

> 真实项目里这个字段应来自源系统的数据库时间戳，
> 本项目 CSV 里没有，用装载时间代替。

### 实测效果

```
3,000 个客户中 300 个搬家了
当前有效版本 : 3,000 行
历史封存版本 :   300 行  ✅
```

现在可以回答："**这个客户 2 月 1 日之前住在哪个城市**"。

### 查询方法

```sql
-- ① 查当前最新状态
SELECT * FROM snap_customers WHERE dbt_valid_to IS NULL;

-- ② 历史回溯：查 2026-01-15 那天的客户状态
SELECT * FROM snap_customers
WHERE DATE '2026-01-15' >= dbt_valid_from
  AND (dbt_valid_to IS NULL OR DATE '2026-01-15' < dbt_valid_to);
```

---


### 改动前

```
- 构建 1 个事实表 + 2 个维度表的星型模型
```

### 改动后

```
- 构建 1 个事实表 + 2 个维度表的星型模型，覆盖 12 万行订单明细；
  将核心事实表改造为增量模型（append 策略），刷新效率提升约 9 倍
- 实现客户维度 SCD Type 2 历史追踪，支持任意时点状态回溯，
  解决"维度变更导致历史分析失真"问题
```

## 常见报错

| 报错 | 原因 | 解决 |
|---|---|---|
| `dbt snapshot` 提示找不到 `updated_at` | stg_customers 没加这个字段 | 已修复，确认文件是最新版 |
| 快照表没生成 | 用了 `dbt run` 而不是 `dbt snapshot` | 换命令 |
| 增量模型第二次跑行数没变 | 源表没有更新的数据 | 用合成脚本再造一批新数据 |
| `{{ this }}` 报错 | 在非 incremental 模型里用了它 | 确认 materialized='incremental' |

---

## 学习检验

做完后问自己：

- [ ] 能说出 incremental 三种策略的区别和适用场景？
- [ ] 能解释 `{{ this }}` 是什么？
- [ ] 能说出增量模型的两个坑及解法？
- [ ] 能说出 SCD 四种类型的区别？
- [ ] 知道 `dbt snapshot` 和 `dbt run` 的区别？

**五题全会 = 工程能力已超过 80% 的治理岗候选人。**
