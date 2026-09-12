# 数据源获取：双通道方案

> 通道 A：Kaggle 真实数据（真实感强，有配置门槛）
> 通道 B：本地合成数据（零门槛，30 秒生成）
> **建议：先用 B 跑通全链路，第 6 天再换成 A**

---

## 通道 B（推荐首选）：本地合成数据

### 为什么先走 B

1. **零风险**：不需要注册任何账号
2. **极快**：0.12 秒生成完毕
3. **结构完全一致**：和真实 Olist 数据字段名、表关系一模一样
4. **不阻塞进度**：Kaggle 卡住时项目照样推进

### 操作

```powershell
python scripts/02_generate_synthetic_data.py
```

### 生成内容

| 文件 | 内容 | 行数 |
|---|---|---|
| `olist_customers_dataset.csv` | 客户表 | 30,000 |
| `olist_orders_dataset.csv` | 订单表 | 40,000 |
| `olist_order_items_dataset.csv` | 订单明细表 | 112,650（真实）/ 120,000（合成）|
| `olist_products_dataset.csv` | 商品表 | 30,000 |

总大小 < 20MB。

### 数据是怎么造出来的（理解原理）

```sql
-- 核心思路：用 range() 生成一批数字，每个数字变一条记录
SELECT
    c AS customer_id,                                    -- 客户编号
    (ARRAY['SP','RJ','MG','RS'])[1 + CAST(random()*3 AS INTEGER)] AS customer_state
FROM range(1, 30001) t(c)      -- 生成 1~30000 这 3 万个数字
```

- `range(1, 30001)` → 产生 1 到 30000 的数字流
- `t(c)` → 把这个数字流叫 t，里面的值叫 c
- `ARRAY[...][索引]` → 从列表里随机取一个值
- `random()` → 0~1 之间的随机数

**主外键设计（保证数据可用）**：
```
stg_orders.customer_id      → 1~30000，对应 stg_customers
stg_order_items.order_id    → (行号-1)/3+1，即每 3 行共享一个订单
stg_order_items.order_item_id → (行号-1)%3+1，即 1/2/3 循环
stg_order_items.product_id  → 1~30000，对应 stg_products
```
这样 `(order_id, order_item_id)` 组合全局唯一，外键不越界，
**数据质检规则能全绿**——第一周不给自己找麻烦。

---

## 通道 A：Kaggle 真实数据（可选，第 6 天做）

### 数据集介绍

**Olist Brazilian E-Commerce Public Dataset**

- 来源：巴西电商平台 Olist 的真实脱敏数据
- 时间跨度：2016-09 ~ 2018-10
- 内容：10 万订单、9 张表
- 许可：CC BY-NC-SA 4.0

### 配置步骤（约 10 分钟）

#### 1. 注册 Kaggle

访问 https://www.kaggle.com 注册（需邮箱 + 手机验证）

#### 2. 接受数据集条款

打开 https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
点 "Download" 按钮旁的使用条款确认

> ⚠️ 不点这步，API 下载会报 403

#### 3. 获取 API Token

访问 https://www.kaggle.com/settings
拉到 **API** 区域 → 点 **Create New Token**
浏览器下载 `kaggle.json`

#### 4. 放置 Token

把 `kaggle.json` 放到：
```
C:\Users\<你的用户名>\.kaggle\kaggle.json
```

PowerShell 一行搞定：
```powershell
mkdir $env:USERPROFILE\.kaggle
copy Downloads\kaggle.json $env:USERPROFILE\.kaggle\
```

#### 5. 安装并下载

```powershell
uv pip install kaggle
python scripts/01_download_olist.py
```

### 常见问题

| 问题 | 解决 |
|---|---|
| 403 Forbidden | 没接受数据集条款，或 Token 位置错 |
| 下载慢/中断 | 放弃，用通道 B |
| 提示 dataset not found | 先在网页打开一次数据集页面 |

---

## 两个通道的数据结构对照

| 表名 | 通道 A（真实） | 通道 B（合成） | 差异 |
|---|---|---|---|
| customers | 99,441 行 | 30,000 行 | 量级不同，字段一致 |
| orders | 99,441 行 | 40,000 行 | 同上 |
| order_items | 112,650 行 | 120,000 行 | 合成数据条数固定，真实数据以 CSV 为准 |
| products | 32,951 行 | 30,000 行 | 同上 |

**关键：字段名完全一致，所以换数据源时模型代码一行都不用改。**

---

## 切换方法

```powershell
# 1. 下载真实数据到 data/raw/
python scripts/01_download_olist.py

# 2. 重新装载（脚本会自动覆盖）
python scripts/03_load_raw.py

# 3. 重跑数仓
dbt run --full-refresh
dbt test
```

---

## 真实数据会带来的"惊喜"（学习机会）

换成真实数据后，你可能会遇到：

1. **有订单没有明细**（孤儿订单）→ INNER JOIN 会丢数据
2. **商品品类有空值** → 维度表要处理
3. **客户城市拼写不一致** → 需要标准化

这些正好是**数据质量的真实案例**，
建议你在第 6 天遇到时，把排查过程记录下来——
