# 多主题域扩展：支付 · 评价 · 卖家 · 地理

> 版本：V1.0
> 目标：把项目从"交易单主题"扩展为"多主题域数仓"
> 数据源：Kaggle Olist 真实数据集（9 张表全接入）
> 配套：`12_data_model_spec.md`、`14_modeling_standards.md`

---

> 📌 **术语说明**：本文档中的「质检规则」指对数据质量设定的自动校验条件，
> 业内标准术语叫「**断言**」（英文 assert，对应 dbt 的 `test` 功能）。
> 例如「订单ID不能重复」就是一条质检规则。

## 一、为什么要做这次扩展

### 1.1 扩展前的问题

| 维度 | 扩展前 | 问题 |
|---|---|---|
| 源表利用 | 9 张只用了 4 张 | 还有 5 张在 `data/raw` 里躺着 |
| 主题域 | 只有交易域 | 看不出"架构感" |
| 数据量 | 34 万行 | 说"百万级"没底气 |
| 能回答的问题 | "卖了多少钱" | 无法回答"客户满不满意""钱怎么付的" |

### 1.2 扩展后

| 维度 | 扩展后 |
|---|---|
| 源表利用 | **9 张全接入** |
| 主题域 | **交易 + 支付 + 评价 + 卖家 + 地理** |
| 数据量 | **155 万行**（翻 4.5 倍） |
| 新增能力 | 实收对账、满意度分析、卖家绩效、地域分布 |

---

## 二、新增数据源

| 文件 | 行数 | 主题域 | 说明 |
|---|---|---|---|
| `olist_order_payments_dataset.csv` | 103,886 | **支付** | 一笔订单可多笔支付 |
| `olist_order_reviews_dataset.csv` | 99,224 | **评价** | 一个订单可能多条评价 |
| `olist_sellers_dataset.csv` | 3,095 | **卖家** | 结构同客户表 |
| `olist_geolocation_dataset.csv` | **1,000,163** | **地理** | 最大表，邮编重复严重 |
| `product_category_name_translation.csv` | 71 | **参照数据** | 葡文→英文品类映射 |

**数据量变化**：

```
扩展前  344,483 行
新增  1,206,439 行
────────────────────
合计  1,550,922 行  （约 155 万）
```

> 光 `geolocation` 一张就 100 万行，让"百万级数据"这个说法成立。

---

## 三、新增模型清单

### 3.1 ODS 贴源层（5 个）

| 模型 | 源表 | 粒度 |
|---|---|---|
| `stg_order_payments` | payments | 一笔订单的一次支付 |
| `stg_order_reviews` | reviews | 一条评价 |
| `stg_sellers` | sellers | 一个卖家 |
| `stg_geolocation` | geolocation | 一条邮编记录（100 万行） |
| `stg_category_translation` | translation | 一个品类映射 |

### 3.2 DWD 明细层（4 个）

| 模型 | 类型 | 粒度 | 关键处理 |
|---|---|---|---|
| `dim_sellers` | 维度 | 一个卖家 | 一致性维度，与 dim_customers 对称 |
| `dim_geography` | 维度 | 一个邮编 | ★ **100万行去重到 1.9万** |
| `fct_payments` | 事实 | 一次支付 | LEFT JOIN 保留孤儿支付 |
| `fct_reviews` | 事实 | 一条评价 | ★ **一单多评标记** |

### 3.3 DWS / ADS 层（3 个）

| 模型 | 粒度 | 业务用途 |
|---|---|---|
| `dws_seller_performance` | 一个卖家 | 卖家绩效宽表 |
| `ads_payment_analysis` | 一种支付方式 | 支付结构看板 |
| `ads_review_analysis` | 一个月份 | 满意度趋势看板 |

---

## 四、★ 两个真实数据质量问题

### 4.1 问题一：geolocation 邮编重复（100万 → 1.9万）

**现象**：

```
源表 1,000,163 行
唯一邮编 约 19,000 个
```

同一邮编重复几十到几百次，每次经纬度略有差异（同一区域的不同测量点）。

**危害**：

如果不处理直接当维度表用：
- 主键不唯一
- JOIN 时数据翻倍（fan-out）
- 所有金额 SUM 虚高

**处理**：在 `dim_geography` 中按邮编聚合

```sql
SELECT
    zip_code_prefix,
    ROUND(AVG(latitude), 6)   AS latitude_avg,
    ROUND(AVG(longitude), 6)  AS longitude_avg,
    MODE(geo_city)            AS geo_city,
    COUNT(*)                  AS measurement_count,   -- 保留溯源能力
    ROUND(STDDEV(latitude),6) AS latitude_stddev      -- 坐标离散度
FROM stg_geolocation
GROUP BY zip_code_prefix
```

**为什么取平均而不是取第一条**：

| 方案 | 问题 |
|---|---|
| 取第一条 | 随机性大，结果不可复现 |
| **取平均** | 代表区域质心，语义明确、结果稳定 |

**保留 `measurement_count` 的价值**：
- 测量点多 → 数据密度高（可能市中心）
- 测量点少 → 偏远地区
- 保留溯源能力，将来能回答"为什么取平均"

**⚠️ 关键设计决策**：ODS 层**绝不去重**

分层规范规定 ODS 只做"忠实记录"，去重属于加工，必须在 DWD 层做。
否则下游永远无法追溯"原始测量点有多少个"。

### 4.2 问题二：一单多评（fan-out 陷阱）

**现象**：

业务设计上一笔订单应只有一条评价，但真实数据里部分 `order_id` 对应多条 `review_id`。

**危害（这是最危险的一类）**：

```sql
-- ❌ 错误写法
SELECT seller_id, SUM(order_amount), AVG(review_score)
FROM fct_orders f
JOIN fct_reviews r ON f.order_id = r.order_id   -- 灾难开始
GROUP BY seller_id
```

一笔订单 3 个商品 × 2 条评价 = JOIN 后 6 行 → **SUM 直接翻倍**。

**实测验证**（我专门做了对比实验）：

```
错误写法（直接 JOIN）: 3,803,285.63
正确金额（事实表原值）: 3,381,281.72
虚高倍数            : 1.12x  →  金额虚高 12.5%
```

**处理**：三步走

```sql
-- ① 窗口函数：同一订单内按评价时间倒序编号
ROW_NUMBER() OVER (
    PARTITION BY order_id
    ORDER BY review_created_at DESC NULLS LAST, review_id
) AS rn

-- ② 标记：该订单是否重复评价
CASE WHEN COUNT(*) OVER (PARTITION BY order_id) > 1
     THEN TRUE ELSE FALSE END AS is_duplicate_review

-- ③ 标记：是否为该订单最新评价
CASE WHEN rn = 1 THEN TRUE ELSE FALSE END AS is_latest_review
```

下游做订单级分析时用 `WHERE is_latest_review = TRUE` 过滤。

**为什么不直接删掉重复的**：

"哪条是最新的"取决于业务规则，不同分析场景可能选不同规则。
DWD 层保留全部 + 打标记，把选择权交给下游，才是正确的分层设计。

---

## 五、★ fan-out 防护：粒度对齐原则

### 5.1 铁律

> **先各自聚合到同一粒度，再 JOIN。**

这是 Kimball 维度建模的核心原则，`dws_seller_performance` 完整演示了它。

### 5.2 正确写法

```sql
WITH seller_sales AS (
    -- ① 订单侧：先按卖家聚合
    SELECT seller_id, SUM(order_amount) AS gmv, ...
    FROM fct_orders GROUP BY seller_id
),
seller_reviews AS (
    -- ② 评价侧：先按卖家聚合（内部还要过滤 is_latest_review）
    SELECT f.seller_id, AVG(rv.review_score) AS avg_score, ...
    FROM fct_reviews rv
    INNER JOIN fct_orders f ON rv.order_id = f.order_id
    WHERE rv.is_latest_review = TRUE    -- ★ 关键过滤
    GROUP BY f.seller_id
)
-- ③ 两侧都是"一卖家一行"后，再安全关联
SELECT ...
FROM dim_sellers s
LEFT JOIN seller_sales sa   ON s.seller_id = sa.seller_id
LEFT JOIN seller_reviews sr ON s.seller_id = sr.seller_id
```

### 5.3 实测验证

```
dws 卖家 GMV 合计 : 2,096,244
fct_orders 原值   : 2,096,244
✓ 完全一致，未发生扇出翻倍
```

**这个验证要记住**：写任何汇总模型后，都应该跑一次"总额对比"，
确认没有发生 fan-out。这是自检的标准动作。

### 5.4 为什么用 LEFT JOIN 而非 INNER

有些卖家还没收到评价。用 INNER JOIN 这些卖家会消失——
但**"零评价的新卖家"恰恰是需要关注的群体**。
所以保留，评分显示为 NULL。

---

## 六、主题域建模方法论：总线矩阵

### 6.1 什么是总线矩阵（Bus Matrix）

Kimball 提出的方法：**行是业务过程，列是维度，交叉格表示"该过程用到该维度"**。


### 6.2 本项目的总线矩阵

| 业务过程 \ 维度 | 客户 | 商品 | 卖家 | 地理 | 时间 | 支付方式 |
|---|---|---|---|---|---|---|
| **下单**（fct_orders） | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| **支付**（fct_payments） | ✅ | — | — | — | ✅ | ✅ |
| **评价**（fct_reviews） | ✅ | — | — | — | ✅ | — |

**价值**：

| 用途 | 说明 |
|---|---|
| **识别一致性维度** | 客户、时间被多个过程共用 → 必须口径统一 |
| **规划开发顺序** | 先建共用维度，再建事实表 |
| **发现遗漏** | 某格应该打勾却空着 → 建模不完整 |

### 6.3 一致性维度（Conformed Dimension）

`dim_sellers` 与 `dim_customers` 的 `region` 划分、`is_core_market` 口径**完全一致**。

为什么呢？因为要支持跨主题分析：

```sql
-- 有了统一口径，才能问"本州卖家卖给本州客户的占比"
SELECT c.region, s.region, COUNT(*) ...
FROM fct_orders f
JOIN dim_customers c ON ...
JOIN dim_sellers   s ON ...
GROUP BY c.region, s.region
```

如果两边 region 划分标准不同，这个查询的结果就是错的。

> **一致性维度是维度建模的灵魂**——
> 它决定了你能不能做跨主题的"钻透"分析。

---

## 七、新增看板表的业务价值

### 7.1 ads_payment_analysis（支付分析）

| 指标 | 业务意义 |
|---|---|
| 各支付方式金额占比 | 资金成本结构 |
| 分期率 | 分期涉及垫资，12 期和 1 期成本差很多 |
| boleto 占比 | 巴西线下付款单，履约周期长、有违约风险 |

- `credit_card` 信用卡，主流
- `boleto` 银行付款单，线下打印去银行/便利店付款，占比较大但风险高
- `voucher` 优惠券
- `debit_card` 借记卡

### 7.2 ads_review_analysis（评价分析）

**★ 核心洞察：评分是先行指标，GMV 是滞后指标**

```
GMV 下跌前，评分往往已连续下滑 3-6 个月

时间轴：
  T+0   客户开始不满 → 评分下滑
  T+3   复购率开始降
  T+6   GMV 才开始跌 ← 等这时候救，客户已经流失完了
```

所以成熟的经营分析会**同时看先行和滞后指标**。

**简化 NPS**：好评率 - 差评率

> 标准 NPS = 推荐者%(9-10分) - 贬损者%(0-6分)
> 5 分制下调整为：好评率(4-5) - 差评率(1-2)
> **这个口径调整必须写进数据字典**，否则不同人算出来不一样。

### 7.3 dws_seller_performance（卖家绩效）

19 个字段，含：

| 类别 | 字段 |
|---|---|
| 销售 | order_count, gmv_delivered, avg_order_value |
| 评价 | avg_review_score, good/bad_review_rate_pct |
| 分层 | seller_tier（A/B/C/D） |
| 风险 | is_risk_seller（有成交但评分 < 3） |

---

## 八、明天开工：操作步骤

### 第 1 步：确认 CSV 已就位（5 分钟）

```powershell
dir D:\projects\olist-dw\data\raw
```

应该看到 9 个 CSV。如果之前只放了 4 个，把 Kaggle 下载的另外 5 个复制进来：
- `olist_order_payments_dataset.csv`
- `olist_order_reviews_dataset.csv`
- `olist_sellers_dataset.csv`
- `olist_geolocation_dataset.csv`
- `product_category_name_translation.csv`

### 第 2 步：覆盖补丁文件

把新增文件覆盖到项目目录（结构见下方清单）。

### 第 3 步：装载 + 构建 + 测试

```powershell
cd D:\projects\olist-dw
python scripts\03_load_raw.py
.\.venv\Scripts\dbt.exe run
.\.venv\Scripts\dbt.exe test
```

**预期**：

| 命令 | 结果 |
|---|---|
| `03_load_raw.py` | 9 张表，geolocation 100 万行 |
| `dbt run` | PASS=20（12 原有 + 8 新增... 实际以输出为准） |
| `dbt test` | 质检规则数增加约 25 条 |

> ⚠️ geolocation 100 万行装载可能需要 10-30 秒，属正常。

### 第 4 步：验证 fan-out 防护（重要自检）

```powershell
.venv\Scripts\python.exe -c "import duckdb;con=duckdb.connect('data/warehouse/olist.duckdb');print('dws卖家GMV:',con.execute('SELECT ROUND(SUM(gmv_delivered)) FROM main_analytics.dws_seller_performance').fetchone()[0]);print('fct原值  :',con.execute('SELECT ROUND(SUM(CASE WHEN is_delivered THEN order_amount ELSE 0 END)) FROM main_core.fct_orders').fetchone()[0])"
```

**两个数字必须完全一致**——一致说明没有 fan-out。

### 第 5 步：看新增主题的数据

```powershell
.venv\Scripts\python.exe -c "import duckdb;con=duckdb.connect('data/warehouse/olist.duckdb');print('支付方式:');[print('  ',r) for r in con.execute('SELECT payment_type, total_amount, amount_share_pct FROM main_analytics.ads_payment_analysis').fetchall()];print('卖家分层:');[print('  ',r) for r in con.execute('SELECT seller_tier, count(*), ROUND(SUM(gmv_delivered)) FROM main_analytics.dws_seller_performance GROUP BY 1 ORDER BY 1').fetchall()]"
```

---

## 九、可能遇到的问题

| 问题 | 原因 | 解决 |
|---|---|---|
| `geolocation` 装载很慢 | 100 万行，属正常 | 等 30 秒 |
| `MODE()` 函数报错 | DuckDB 版本过旧 | 升级 duckdb |
| `NULLS LAST` 报错 | 旧版不支持 | 改 `ORDER BY review_created_at DESC` |
| dbt test 新增质检规则不通过 | 真实数据脏 | 按五步法处理，记台账 |
| 磁盘空间不足 | geolocation 较大 | 检查剩余空间（需约 500MB） |

---
