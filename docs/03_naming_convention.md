# 目录结构与命名规范

> 规范本身就是治理能力的体现。

---

> 📌 **术语说明**：本文档中的「质检规则」指对数据质量设定的自动校验条件，
> 业内标准术语叫「**断言**」（英文 assert，对应 dbt 的 `test` 功能）。
> 例如「订单ID不能重复」就是一条质检规则。

## 一、完整目录结构

```
olist-dw/
│
├── requirements.txt               # 依赖清单
├── dbt_project.yml                # dbt 主配置
├── profiles.yml.example           # 连接配置模板
│
├── scripts/                       # 数据获取与装载
│   ├── 01_download_olist.py       # 通道A：Kaggle 下载
│   ├── 02_generate_synthetic_data.py  # 通道B：合成数据
│   └── 03_load_raw.py             # CSV → DuckDB
│
├── data/
│   ├── raw/                       # 原始 CSV（.gitignore，不提交）
│   └── warehouse/olist.duckdb     # 数据库文件（.gitignore）
│
├── models/                        # ★ 数仓模型（核心）
│   ├── staging/                   # ODS 贴源层
│   │   ├── stg_customers.sql
│   │   ├── stg_orders.sql
│   │   ├── stg_order_items.sql
│   │   ├── stg_products.sql
│   │   └── schema.yml             # 数据字典 + 质量规则
│   │
│   └── marts/
│       ├── core/                  # DWD 明细层（星型模型）
│       │   ├── fct_orders.sql
│       │   ├── dim_customers.sql
│       │   ├── dim_products.sql
│       │   └── schema.yml
│       │
│       └── analytics/             # DWS/ADS 应用层
│           ├── dws_customer_rfm.sql
│           ├── ads_gmv_monthly.sql
│           ├── ads_category_sales.sql
│           ├── ads_region_overview.sql
│           └── schema.yml
│
├── macros/                        # 可复用 SQL 片段
├── tests/                         # 自定义质量测试
├── snapshots/                     # 慢变维历史追踪（第二周）
├── seeds/                         # 小维表 CSV
│
├── target/                        # dbt 生成物（.gitignore）
│   ├── index.html                 # 数据字典首页
│   ├── catalog.json               # 元数据
│   └── manifest.json              # 血缘关系
│
└── docs/                          # 各环节说明文档
    ├── 00_environment_setup.md
    ├── 01_sql_crash_course.md
    ├── 02_data_sources.md
    ├── 03_naming_convention.md
    ├── 04_daily_checklist.md
```

---


### 2.1 分层前缀

| 前缀 | 层级 | 全称 | 含义 |
|---|---|---|---|
| `stg_` | ODS | Staging | 贴源层，原样搬运 |
| `dim_` | DWD | Dimension | 维度表 |
| `fct_` | DWD | Fact | 事实表 |
| `dws_` | DWS | Data Warehouse Summary | 轻度汇总 |
| `ads_` | ADS | Application Data Store | 应用集市 |

**为什么这样命名**：打开文件就知道它在哪一层、是什么角色。
这是团队协作的基础——不用打开 SQL 看内容。

### 2.2 目录分层

| 目录 | 层级 | 物化方式 | 原则 |
|---|---|---|---|
| `models/staging/` | ODS | view | 不存数据，永远和源一致 |
| `models/marts/core/` | DWD | table | 建实体表，星型模型 |
| `models/marts/analytics/` | DWS/ADS | table | 建实体表，直接给 BI 用 |

### 2.3 字段命名

```sql
-- ✅ 好的命名
customer_id          -- 小写 + 下划线（snake_case）
order_purchased_at   -- 时间字段用 _at 结尾
order_date           -- 日期字段用 _date 结尾
is_delivered         -- 布尔字段用 is_ 开头
gmv_delivered        -- 金额带口径后缀
cancel_rate_pct      -- 比率带 _pct 后缀

-- ❌ 差的命名
CustomerID           -- 驼峰，SQL 里不规范
客户ID                -- 中文，绝对禁止
flag                 -- 看不懂什么意思
amount1              -- 数字后缀无意义
```

### 2.4 口径命名规则（本项目亮点）

同一个指标不同口径，**必须在字段名上区分开**，不能只靠注释：

```sql
gmv_all          -- 含取消（错误口径，仅供对比）
gmv_delivered    -- ✅ 标准口径
gmv_cancelled    -- 取消金额
```

> 这条规则本身就是治理动作：**让口径错误在命名阶段就无法隐藏**。

---

## 三、模型文件的标准注释模板

每个 `.sql` 文件开头都要有这段，**这是职业习惯**：

```sql
-- ============================================================
-- 模型：模型名（中文说明）
-- 层级：所属层级
-- 物化：view / table / incremental
-- ------------------------------------------------------------
-- 【这一层是干什么的？】
--   ...
-- 【新手知识点：XXX】
--   ...
-- ============================================================
```

---

## 四、schema.yml 的写法（治理证据核心）

### 为什么它最重要

`schema.yml` 里的 `description` 会被 dbt 渲染成**在线数据字典**，
`tests` 会变成**自动质量检查**。

**你写得越详细，治理证据越漂亮。这是你区别于普通 demo 的关键。**

### 必写三项

```yaml
models:
  - name: 模型名
    description: >      # ① 模型说明：粒度、来源、用途
      一行 = 什么。来源哪。注意什么。
    columns:
      - name: 字段名
        description: >  # ② 字段说明：含义、单位、口径
          什么含义，单位是什么，什么口径。
        tests:          # ③ 数据质检规则
          - unique
          - not_null
```

### 常用数据质检规则速查

| 质检规则 | 作用 |
|---|---|
| `unique` | 不重复 |
| `not_null` | 不为空 |
| `accepted_values` | 只能是指定值 |
| `relationships` | 外键必须在另一表存在 |
| `expect_column_values_to_be_between` | 数值区间 |

---

## 五、.gitignore（必须配）

```
# 数据文件不提交
data/raw/
data/warehouse/
*.duckdb
*.csv

# dbt 生成物
target/
dbt_packages/
logs/

# Python
.venv/
__pycache__/
*.pyc

# 环境
.env
profiles.yml
```

> ⚠️ `profiles.yml` 里有你的本地路径，**绝对不能提交到公开仓库**。

---

## 六、规范检查清单

提交前自查：

- [ ] 所有模型文件有标准注释头
- [ ] 命名符合分层前缀（stg_/dim_/fct_/dws_/ads_）
- [ ] 字段全小写 + 下划线
- [ ] 布尔字段 `is_` 开头
- [ ] 口径不同的指标字段名有区分
- [ ] 每个 schema.yml 有 description
- [ ] 关键字段有 tests
- [ ] .gitignore 已配置，数据文件未提交
- [ ] README 能让人 3 分钟看懂项目
