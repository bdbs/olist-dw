[![dbt CI](https://github.com/bdbs/olist-dw/actions/workflows/dbt.yml/badge.svg)](https://github.com/bdbs/olist-dw/actions/workflows/dbt.yml)

# olist-dw：以数仓为载体的数据治理与架构实践

> 面向岗位：**数据治理 / 数据管理 / 数据架构**
> 技术栈：DuckDB + dbt Core + Metabase，全部本地运行，**现金成本 0 元**

---

## 一、这个项目是什么

这不是一个"数仓 demo"，而是一次**按 DAMA/DCMM 规范完成的端到端交付**：

从业务需求出发 → 分层建模 → 口径统一 → 质量断言 → 元数据与血缘 → BI 交付 → 建设方案。

数仓是载体，**治理与架构才是要证明的东西**。

### 业务背景（虚构但真实）

Olist 是巴西一家电商平台（真实存在的公司，数据已公开脱敏）。
业务方提出需求：**想知道 GMV 的变化趋势，以及哪些客户值得重点维护。**

原始数据分散在 4 张业务表里，口径不统一、状态混杂，无法直接回答业务问题。

---

## 二、分层架构

```
原始数据 CSV
     │  03_load_raw.py
     ▼
┌─────────────────────────────────────────┐
│ ODS 贴源层  staging/                     │  原样搬运 + 清洗改名
│ stg_customers / stg_orders / ...         │  物化：view
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ DWD 明细层  marts/core/                  │  星型模型 + 口径统一
│ fct_orders（事实）                        │  物化：table
│ dim_customers / dim_products（维度）      │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ DWS/ADS 应用层  marts/analytics/         │  主题宽表 + 业务集市
│ dws_customer_rfm / ads_gmv_monthly       │  物化：table
│ ads_category_sales / ads_region_overview │
└─────────────────────────────────────────┘
     │
     ▼
  Metabase 看板
```

---

## 三、本项目如何落地 DAMA 各知识领域

| DAMA 知识领域 | 落地体现 | 证据物 |
|---|---|---|
| 数据建模与设计 | 四层分层、星型模型、一致性维度 | 模型 SQL + ER 图 |
| 元数据管理 | 字段级描述（schema.yml） | `dbt docs` 生成的在线数据字典 |
| 数据质量管理 | 8 类断言：唯一/非空/区间/枚举/参照完整性 | `dbt test` 报告 |
| 数据仓库与 BI | 主题域划分、指标口径统一 | 分层架构 + Metabase 看板 |
| 数据治理 | 口径下沉、Owner 标注、模型分级 | 数据字典中的口径说明 |

---

## 四、核心设计：指标口径下沉（本项目的点睛之笔）

订单有 5 种状态，但 GMV 只该算 `delivered`。

**错误做法**：每个分析师在自己 SQL 里各写各的 `WHERE order_status='delivered'`。
**本项目做法**：在 DWD 层统一标记 `is_delivered`，下游只能引用标记位。

实测差距有多大？

| 口径 | 金额 | 说明 |
|---|---|---|
| gmv_all（含取消） | 33,821,664 | ❌ 错误 |
| gmv_delivered（标准） | 14,122,671 | ✅ 对外口径 |
| **差异** | **19,698,992（58.2%）** | 报表会虚高一半以上 |


详见 `models/marts/analytics/ads_gmv_monthly.sql` 注释。

---

## 五、快速开始

```bash
# 1. 装依赖
uv venv && .venv/Scripts/activate
uv pip install -r requirements.txt

# 2. 配置连接：把 profiles.yml.example 复制到 ~/.dbt/profiles.yml
#    并修改 path 为你本机的实际路径

# 3. 造数据（或用 Kaggle 真实数据，见 scripts/01_download_olist.py）
python scripts/02_generate_synthetic_data.py

# 4. 跑数仓
dbt debug          # 必须全绿
dbt run            # 构建全部模型
dbt test           # 跑质量断言

# 5. 生成血缘 + 数据字典
dbt docs generate
dbt docs serve     # 浏览器打开 localhost:8080
```

---

## 六、目录说明

| 目录 | 内容 |
|---|---|
| `scripts/` | 数据获取、装载、静态站生成脚本 |
| `models/staging/` | ODS 贴源层（4 个模型） |
| `models/marts/core/` | DWD 明细层（星型模型，3 个） |
| `models/marts/analytics/` | DWS/ADS 应用层（4 个） |
| `models/advanced/` | 增量模型（进阶补丁） |
| `snapshots/` | SCD Type 2 慢变维快照（进阶补丁） |
| `models/**/schema.yml` | 数据字典 + 质量规则（治理证据核心） |
| `site/` | GitHub Pages 静态站（数据字典 + 血缘图） |
| `docs/` | 9 份说明文档（md + Word 双格式） |

## 六·补充、进阶模块

完成基础版后可继续：

| 模块 | 说明 | 文档 |
|---|---|---|
| **增量模型** | `fct_orders` 改为 incremental，效率提升约 9 倍 | `docs/07_进阶补丁_增量模型与SCD.md` |
| **SCD Type 2** | 客户维度历史追踪，支持任意时点回溯 | 同上 |
| **静态站** | 数据字典 + 血缘图生成公网可访问页面 | `docs/08_GitHubPages部署指南.md` |

```bash
dbt snapshot                    # 跑 SCD 快照（注意不是 dbt run）
python scripts/04_build_site.py # 生成静态站到 site/
```

---

## 七、数据规模

| 表 | 行数 |
|---|---|
| stg_customers | 30,000 |
| stg_orders | 40,000 |
| stg_order_items | 120,000 |
| stg_products | 30,000 |
| fct_orders | 119,999 |
| dws_customer_rfm | 12,275 |
| ads_gmv_monthly | 25（月） |

数据库文件 < 100MB，普通笔记本轻松跑。

---

## 七·补充、质量与元数据实测

| 项目 | 数量 |
|---|---|
| 数据模型 | 11 个 |
| 字段总数 | 45 个 |
| 质量断言 | 34 条（通过率 100%） |
| 血缘依赖 | 12 条 |

## 八、对应 DCMM 2.0 能力域

| 能力域 | 本项目覆盖 |
|---|---|
| 数据架构 | 四层分层、数据模型、数据分布 ✅ |
| 数据标准 | 命名规范、业务术语、指标口径 ✅ |
| 数据质量 | 8 类质量断言 ✅ |
| 元数据管理 | 字段级数据字典、血缘 DAG ✅ |
| 数据治理 | 口径治理、Owner 标注 ✅ |
| 数据应用 | BI 看板、主题分析 ✅ |

---

## 九、文档导航

| 文档 | 什么时候看 |
|---|---|
| `docs/00_environment_setup` | **第一个打开**，照着做 |
| `docs/01_sql_crash_course` | SQL 零基础必看，含自测题 |
| `docs/02_data_sources` | 拿数据时看 |
| `docs/03_naming_convention` | 写代码时对照 |
| `docs/04_daily_checklist` | 每天开工前扫一眼 |
| `docs/06_design_document` | Day 6 正式交付物 ★ |
| `docs/07_metabase_guide` | Day 6 做看板时 |
| `docs/08_GitHubPages发布指南` | Day 7 拿公网链接 |
| `docs/09_incremental_scd` | 基础版完成后补工程深度 |

所有文档均提供 **Markdown + Word 双格式**（Word 在 `docs/word/`）。

---

## 十、项目证据站

`site/index.html` 是一个自包含的项目展示页，含：
- 分层架构图
- **GMV 口径差异 58.4%** 的可视化对比
- 8 项质量断言清单
- 血缘 DAG
- DCMM 2.0 能力域覆盖

