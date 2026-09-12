# 项目进度总结与问题复盘

> 更新时间：2026-09-11
> 当前阶段：**Day 2 完成，项目主体已跑通**
> 数据源：Kaggle Olist 真实数据集（已从合成数据切换）

---

> 📌 **术语说明**：本文档中的「质检规则」指对数据质量设定的自动校验条件，
> 业内标准术语叫「**断言**」（英文 assert，对应 dbt 的 `test` 功能）。
> 例如「订单ID不能重复」就是一条质检规则。

## 一、当前进度：到哪一步了

### 完成状态总览

| 阶段 | 任务 | 状态 | 产出 |
|---|---|---|---|
| **Day 0** | 环境搭建 | ✅ 完成 | Python 3.12 + uv + dbt 1.12 + DuckDB 1.11 |
| **Day 1** | 合成数据跑通 | ✅ 完成 | 12 模型 / 38 质检规则 / 血缘图 |
| **Day 2** | 切换真实数据 | ✅ 完成 | 99,441 订单 / 112,650 明细 |
| **Day 2** | 质量台账 | ✅ 完成 | 4 个真实问题归档 |
| **Day 3-5** | SQL 深化学习 | ⏳ 待做 | `01_sql_crash_course.md` |
| **Day 6** | 建设方案 + 看板 | ⏳ 待做 | 方案已更新，看板待做 |

### 当前技术成果（真实数据）

```
数据源        Kaggle Olist 真实数据集
              99,441 订单 / 112,650 明细 / 覆盖 24 个月

模型          12 个（ODS 4 + DWD 3 + DWS 1 + ADS 3 + 增量 1）
              另含 1 个 SCD2 快照

数据质检规则      38 项（Day2）→ 74 项（Day3 多主题域扩展后），全部通过

核心指标      GMV 标准口径   15,419,774 BRL
              GMV 全口径     15,843,553 BRL
              口径差异        423,779 BRL（2.67%）
              平均客单价      154.39 BRL
              平均取消率      1.95%

质量发现      无明细订单      775 单（0.78%）★ 核心案例
              商品品类缺失    610 条
              状态枚举超预期  8 种（设计 5 种）
```

### 一句话概括

**管道已完全跑通，真实数据已接入，数据质检规则全绿，质量台账已归档。**
剩下的是"深化"和"包装"，不再是"能不能跑"的问题。

---

## 二、踩过的坑全记录（重要资产）

这一路的调试不是浪费，**每一个坑都是经验**。按类别整理：

### A. 环境安装类

| # | 问题 | 根因 | 解法 |
|---|---|---|---|
| 1 | `winget install astral.uv` 找不到包 | 源未更新 | `winget source update`，或改用官方脚本安装 |
| 2 | `uv pip install` TLS 握手失败 | uv 用 Rust reqwest，与中间网络冲突 | **改用 Python 自带 pip**（Python 能联网返回 200） |
| 3 | `.venv` 里没有 pip | `uv venv` 默认不装 pip | `python -m ensurepip --upgrade` |
| 4 | pip 报 `access violation writing` | 杀毒软件拦截临时写入 | 用离线 wheel 包 `--no-index` 安装 |

### B. 命令写法类

| # | 问题 | 根因 | 解法 |
|---|---|---|---|
| 5 | `.venv\Scripts\activate` 报找不到命令 | 这是 bash/CMD 写法 | PowerShell 用 `.\.venv\Scripts\Activate.ps1`，或统一用 `uv run dbt` |
| 6 | `Activate.ps1` 执行策略被禁 | Windows 默认禁止 .ps1 | `Set-ExecutionPolicy -Scope Process RemoteSigned`（仅当前窗口生效） |
| 7 | `python -m dbt` 报 No module named | **dbt 没有 `__main__.py`** | 用 `.venv\Scripts\dbt.exe` |

### C. 编码与语法类

| # | 问题 | 根因 | 解法 |
|---|---|---|---|
| 8 | `'gbk' codec can't decode` | Windows 中文版 Python 默认 GBK 读 UTF-8 文件 | `$env:PYTHONUTF8=1` 或 `setx PYTHONUTF8 1` |
| 9 | Jinja `invalid syntax for function call` | 在 `{{ config() }}` 块内写了 SQL 注释 `--` | 注释移到 `{{ }}` 外面（Jinja 注释是 `{# #}`） |
| 10 | YAML `did not find expected key` | `description: >` 折叠块缩进敏感 | **改用单行 `description: "..."`** |

### D. 数据与逻辑类

| # | 问题 | 根因 | 解法 |
|---|---|---|---|
| 11 | 1 条孤儿明细（order_id=40001） | DuckDB 中 `/` 是浮点除法，CAST 四舍五入 | 改用 `//` 整数除法 |
| 12 | `Binder Error: column not found` | CSV 是旧字段名，模型是新的 | 装载脚本加**字段名自动对齐** |
| 13 | 枚举质检规则失败（3 种状态） | 真实数据 8 种状态，设计只写 5 种 | 扩充枚举至 8 种 |

### E. 使用习惯类

| # | 问题 | 解法 |
|---|---|---|
| 14 | `git add` 漏了点，且提交了 target/ | 先建 `.gitignore`，再 `git rm -r --cached target` |
| 15 | 端口 10048 被占用 | 换端口 `--port 8081`，或 taskkill 旧进程 |
| 16 | 查表报 `main.ads_gmv_monthly` 不存在 | 正确表名是 **`main_analytics.ads_gmv_monthly`** |

> 随便挑两三个讲，比空谈"我学习能力强"有说服力得多。

---

## 三、文档更新说明

### 已更新（本轮）

| 文档 | 更新内容 |
|---|---|
| `00_environment_setup.md` | 命令改为 `uv run dbt` / `dbt.exe`；新增 5 条踩坑排错（gbk、python -m dbt、Jinja、Binder） |
| `06_design_document.md` | 全部数字换真实；新增 **5.3 静默数据丢失**章节（核心案例） |
| `11_quality_issue_log.md` | 新建，4 个真实问题五步法归档 |
| `12_data_model_spec.md` | 新建，概念/逻辑/物理三层模型 + 代码逐行讲解 |

### 关键修正：58.2% → 2.67%

| | 合成数据 | 真实数据 |
|---|---|---|
| GMV 差异 | 58.2% | **2.67%** |

**原因**：合成数据时状态分布配置不合理（取消单占比过高），
真实 Olist 中 96%+ 订单都是 delivered。

> ⚠️ **这是必须记住的教训**：
> 指标口径结论必须建立在真实数据之上。

### 文档体系现状

```
docs/
├── 00_environment_setup.md      ✅ 已更新（含踩坑）
├── 01_sql_crash_course.md            ⏳ 待学
├── 02_data_sources.md
├── 03_naming_convention.md
├── 04_daily_checklist.md
├── 06_design_document.md        ✅ 已更新（新增核心案例）
├── 07_metabase_guide.md    ⏳ 待用
├── 08_GitHubPages发布指南.md     ⏳ 待用
├── 09_incremental_scd.md
├── 10_kaggle_real_data.md
├── 11_quality_issue_log.md        ✅ 新建
└── 12_data_model_spec.md      ✅ 新建（概念/逻辑/物理模型 + 代码讲解）
```

---

## 四、下一步建议（按优先级）

### P0：加固核心证据（1 小时）

**1. 给 775 单加 `severity: warn` 质检规则**

打开 `models/staging/schema.yml`，在 `stg_orders` 的 `order_id` 下加：

```yaml
      - name: order_id
        tests:
          - unique
          - not_null
          - relationships:
              to: ref('stg_order_items')
              field: order_id
              severity: warn
```

加完 `dbt test` 会显示 `WARN=1 PASS=37`——**黄色告警正是你要的治理态度**：
"我知道它存在，并且我在监控它"。

**2. 截图留证**：告警页面 + 血缘图 + 各层模型详情页

### P1：深化理解（Day 3-5，按 01 文档推进）

- 窗口函数 `NTILE / ROW_NUMBER`
- CTE 与复杂 JOIN
- 聚合与分组

### P2：包装交付（Day 6-7）

1. Metabase 做 3 张看板（或 matplotlib 降级）
2. GitHub Pages 发布证据站

---

### 故事 1：775 单静默丢失（★ 最强）

```
发现：订单表 99,441，事实表去重只有 98,666，差 775
危害：INNER JOIN 从明细表出发，这 775 单永远进不了事实表，
      无报错、无日志、无告警
决策：不改 LEFT JOIN（会污染粒度），而是保持粒度纯洁
      + ADS 层另建订单总数口径 + severity:warn 质检规则监控
沉淀：丢失比错误更可怕；可见即可控
```

### 故事 2：GMV 口径统一

```
发现：含取消订单 GMV 比标准口径多 423,779 BRL（2.67%）
决策：口径下沉三步法（DWD 标记位 → 下游只引用 → 字典固化）
      + ADS 层保留多口径字段让差异可见
沉淀：口径问题不是技术问题，是管理问题；
      技术手段的作用是让分歧显性化
```

### 故事 3：状态枚举超预期

```
发现：质检规则不通过，真实数据 8 种状态，设计只写 5 种
决策：扩充枚举 + 数据字典明确"只有 delivered 计入 GMV"
沉淀：维度枚举不能靠想当然，必须以真实数据校验；
      质检规则在建模阶段就暴露了设计假设与现实的差距
```

---

## 六、给后续自己的提醒

1. **命令统一用 `uv run dbt` 或 `.venv\Scripts\dbt.exe`**，别再用 `python -m dbt`
2. **查询表名带 schema**：`main_analytics.ads_gmv_monthly`
3. **改 YAML 用单行 `description: "..."`**，别用 `>` 折叠块
4. **Jinja 块 `{{ }}` 内不写 SQL 注释**
5. **每半天 `git commit` 一次**，崩了能回滚
