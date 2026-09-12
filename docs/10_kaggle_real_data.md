# Kaggle 真实数据接入指南

> 结论先说：**真实数据确实比合成数据好，建议用。**
> 但我刚发现并修复了 2 个字段名不兼容的地方——所以问得好，否则换数据必报错。

---

> 📌 **术语说明**：本文档中的「质检规则」指对数据质量设定的自动校验条件，
> 业内标准术语叫「**断言**」（英文 assert，对应 dbt 的 `test` 功能）。
> 例如「订单ID不能重复」就是一条质检规则。

## 一、合成 vs 真实，怎么选

| 维度 | 合成数据 | 真实 Olist 数据 |
|---|---|---|
| 数据质量故事 | 人工注入的问题，**一眼假** | ✅ **真实脏数据**，故事天然可信 |
| 准备耗时 | 10 秒 | 约 10-15 分钟（注册+下载） |
| 门槛 | 无 | 需 Kaggle 账号 + 手机验证 |
| 规模 | 3 万/4 万/12 万 | 99,441 单 / 112,650 明细 |

不用像合成数据那样"人工制造问题"。

**但我建议分两步走**（重要）：

```
第 1 步：先用合成数据跑通（5 分钟）  ← 验证管道没问题
第 2 步：换成真实数据（15 分钟）     ← 拿到真实证据
```

**为什么不一上来就用真实数据？**
因为如果直接上真实数据报错了，你分不清是**管道有问题**还是**数据有问题**。
先用已知干净的合成数据跑通一次，确认管道 OK，之后任何报错都只可能是数据的锅，排查快得多。

---

## 二、我发现并已修复的 2 个不兼容

我原本说"表结构完全一致，可零成本切换"——**这句话之前是错的**，实际有两处不一致。现已修复：

| 位置 | 我原来的合成列名 | 真实 Olist 列名 | 状态 |
|---|---|---|---|
| 客户表 | `customer_zip_code` | `customer_zip_code_prefix` | ✅ 已修复 |
| 商品表 | `product_category` | `product_category_name` | ✅ 已修复 |

修复方式：**把合成数据的列名改成和真实数据完全一致**（而不是改模型去兼容两套）。
这样"表结构契约"才真正成立，两套数据可以随时互换，模型和代码一行不用动。

我已用完整的真实 Olist 列名实跑验证，**11 个模型全部通过**。

---

## 三、下载真实数据（不用 API Token！）

### 关键：跳过 `01_download_olist.py`

那个脚本需要配置 Kaggle API Token，配置过程容易卡住。
**其实根本不需要**——直接网页下载最简单：

### 步骤

1. 打开 https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
2. 注册/登录 Kaggle（Google 账号一键登录最省事）
3. **必须完成手机号验证**（Settings → Phone Verification），否则不给下载
4. 点右上角 **Download** 按钮
5. 得到 `archive.zip`（约 40MB），解压

### 解压后放进项目

把里面的 **9 个 CSV** 复制到：

```
D:\projects\olist-dw\data\raw\
```

需要的文件（后 5 个本项目暂未使用，放着不影响）：

| 文件 | 本项目是否用 | 行数 |
|---|---|---|
| `olist_customers_dataset.csv` | ✅ 用 | 99,441 |
| `olist_orders_dataset.csv` | ✅ 用 | 99,441 |
| `olist_order_items_dataset.csv` | ✅ 用 | 112,650 |
| `olist_products_dataset.csv` | ✅ 用 | 32,951 |
| `olist_sellers_dataset.csv` | 暂不用 | 3,095 |
| `olist_order_payments_dataset.csv` | 暂不用 | 103,886 |
| `olist_order_reviews_dataset.csv` | 暂不用 | 99,224 |
| `olist_geolocation_dataset.csv` | 暂不用 | 1,000,163 |
| `product_category_name_translation.csv` | 暂不用 | 71 |

> 行数以实际下载为准，略有出入正常。

---

## 四、装载并运行

```powershell
cd D:\projects\olist-dw

# 1. 装载（会自动识别 data/raw 下的 4 个 CSV）
python scripts\03_load_raw.py

# 2. 跑数仓
.\.venv\Scripts\dbt.exe run

# 3. 跑数据质检规则
.\.venv\Scripts\dbt.exe test
```

**注意**：这次用 `03_load_raw.py`（装载脚本），
不是 `02_generate_synthetic_data.py`（造数脚本）。

---

## 五、真实数据会带来的"惊喜"（这是好事）

真实数据一定有脏数据，而这**正是你项目的核心价值**。
跑完后执行下面的探查，把发现记进 `docs\02_数据质量基线.md`。

### 探查 SQL

新建 `sql\06_真实数据质量探查.sql`，逐条跑：

```sql
-- ① 总规模
SELECT
    (SELECT COUNT(*) FROM raw_orders)      AS 订单数,
    (SELECT COUNT(*) FROM raw_order_items) AS 明细数,
    (SELECT COUNT(*) FROM raw_customers)   AS 客户数,
    (SELECT COUNT(*) FROM raw_products)    AS 商品数;

-- ② 商品品类缺失（真实数据中已知存在）
SELECT COUNT(*) AS 品类缺失商品数
FROM raw_products
WHERE product_category_name IS NULL;

-- ③ 订单状态分布（确认口径基础）
SELECT order_status, COUNT(*) AS cnt
FROM raw_orders GROUP BY order_status ORDER BY cnt DESC;

-- ④ 有无明细的订单（LEFT JOIN 探查）
SELECT COUNT(*) AS 无明细订单数
FROM raw_orders o
LEFT JOIN raw_order_items i ON o.order_id = i.order_id
WHERE i.order_id IS NULL;

-- ⑤ 外键是否失效
SELECT COUNT(*) AS 孤儿商品
FROM raw_order_items i
LEFT JOIN raw_products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL;

-- ⑥ 时间逻辑是否倒挂
SELECT COUNT(*) AS 时间倒挂
FROM raw_orders
WHERE TRY_CAST(order_delivered_customer_date AS TIMESTAMP)
      < TRY_CAST(order_purchase_timestamp AS TIMESTAMP);

-- ⑦ 价格异常
SELECT
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS 空价格,
    SUM(CASE WHEN price <= 0   THEN 1 ELSE 0 END) AS 非正价格
FROM raw_order_items;
```


---

## 六、可能遇到的问题

| 问题 | 原因 | 解决 |
|---|---|---|
| Kaggle 不给下载 | 没做手机验证 | Settings → Phone Verification |
| 下载到 `archive.zip` 但解压报错 | 没下完整 | 重下，约 40MB |
| `dbt run` 报找不到列 | CSV 没放对位置 | 确认在 `data\raw\` 下，文件名一模一样 |
| 报 `product_category_name` 不存在 | 用了旧版文件 | 确认已用最新版补丁覆盖 |
| 数据量变大后变慢 | 正常，11 万行 | 你 32G 内存，几十秒没问题 |
| `dbt test` 有失败 | 真实数据有脏数据 | **好事**，见下节 |

### 如果 dbt test 失败怎么办

**不要慌，这是真实数据的正常现象，而且是你最想要的素材。**


1. 看失败的是哪条质检规则、多少行
2. 回溯到 `raw_` 表定位根因（是空值？越界？外键丢失？）
3. 判断性质：采集问题 / 业务确实如此 / 模型逻辑错
4. 决定处理方式：过滤 / 置空 / 归入"未知"维度
5. 改模型，重新跑，**并补一条质检规则防止复发**

把这五步记录下来，就是一份完整的《数据质量问题处理台账》。

---


```markdown
- 基于 Kaggle 公开数据集 Olist 巴西电商真实数据（9.9 万订单 / 11.3 万明细）
  构建四层主题数仓，设计 1 事实表 + 2 维度表星型模型
- 探查发现 N 类数据质量问题（品类缺失 X 条 / 时间倒挂 Y 条 / ...），
  建立 8 项自动化数据质检规则并闭环处理，通过率 100%
```

**关键差异**：用了真实数据，"11.3 万明细"是真实规模，

---

## 八、决策建议

如果你现在就想用真实数据：

1. 先跑 `python scripts\02_generate_synthetic_data.py` + `dbt run` 冒烟测试（5 分钟）
2. 确认全绿后，去 Kaggle 下载真实数据
3. 放进 `data\raw\`，跑 `03_load_raw.py` + `dbt run`

**如果 Kaggle 注册/手机验证卡住超过 15 分钟** → 先用合成数据推进，
不要阻塞。真实数据可以第 6 天再换，因为**两套数据结构现在完全一致，随时可切**。
