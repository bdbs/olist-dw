# Metabase 看板配置指南（Day 6 上午，约 1.5 小时）

> 目标：装好 Metabase，做 3 张看板，截图存档
> 前提：`dbt run` 已成功，`data/warehouse/olist.duckdb` 存在

---

## 0. 先看：为什么要做看板

数仓做到 ADS 层，数据已经"能查"了。但**业务方不看 SQL，他们只看图**。

有了看板，它就是"一个能用的数据产品"。

**三张必做看板**：

| 看板 | 用哪张表 | 图表类型 | 回答什么业务问题 |
|---|---|---|---|
| 月度 GMV 趋势 | `ads_gmv_monthly` | 折线图 | 生意在涨还是跌 |
| 品类销售占比 | `ads_category_sales` | 柱状图/饼图 | 哪些品类最赚钱 |
| 客户 RFM 分布 | `dws_customer_rfm` | 柱状图 | 客户结构健康吗 |

---

## 1. 安装 Metabase（30 分钟）

### 1.1 为什么用 JAR 版而不是 Docker

| 方案 | 内存占用 | 启动 | 适合你吗 |
|---|---|---|---|
| Docker Desktop | 常驻 2GB+ | 需装 Docker | ❌ 你 32G 内存但低压 U，Docker 常驻很拖 |
| **JAR 版** | 约 500MB | 一条命令 | ✅ **推荐** |

### 1.2 装 Java（如果没装过）

Metabase 是 Java 程序，需要 Java 运行环境。

```powershell
winget install EclipseAdoptium.Temurin.17.JDK
```

装完**重启 PowerShell**，验证：

```powershell
java -version
```

看到 `openjdk version "17..."` 就是成功。

### 1.3 下载 Metabase

访问 https://www.metabase.com/start/jar/
下载 `metabase.jar`（约 200MB）

放到一个固定位置，比如 `D:\tools\metabase.jar`

### 1.4 启动

```powershell
cd D:\tools
java -jar metabase.jar
```

**第一次启动要等 2-5 分钟**（它在初始化内置数据库）。
看到 `Metabase Initialization COMPLETE` 就可以用了。

浏览器打开：**http://localhost:3000**

> ⚠️ 这个 PowerShell 窗口**不能关**，关了 Metabase 就停了。
> 以后每次用都要重新 `java -jar metabase.jar`。

---

## 2. 首次配置（15 分钟）

### 2.1 创建管理员账号

第一次打开会让你填：
- 姓名、邮箱、密码（自己记住就行）
- 公司名：随便填

### 2.2 添加 DuckDB 数据库 ⚠️ 最关键的坑

Metabase **官方不支持 DuckDB**，需要手动加驱动。

**这是个真实的坑，但有个简单绕法**：

#### 方案 A：导出为 CSV 再导入（小白推荐，5 分钟搞定）

Metabase 内置支持 SQLite/Postgres/MySQL，但都要求装服务。
所以最快的方式是——**绕过数据库连接，直接用 CSV**。

```powershell
# 把 ADS 层三张表导出成 CSV
python -c "
import duckdb
con = duckdb.connect('data/warehouse/olist.duckdb')
con.execute(\"COPY ads_gmv_monthly TO 'data/export/ads_gmv_monthly.csv' (HEADER, DELIMITER ',')\")
con.execute(\"COPY ads_category_sales TO 'data/export/ads_category_sales.csv' (HEADER, DELIMITER ',')\")
con.execute(\"COPY dws_customer_rfm TO 'data/export/dws_customer_rfm.csv' (HEADER, DELIMITER ',')\")
print('导出完成')
"
```

然后在 Metabase 里：
- 添加数据 → 选 **SQLite**（或直接上传 CSV）

#### 方案 B：用 DuckDB 的 SQLite 兼容层（更优雅）

```powershell
# 把 DuckDB 库导出为一个 SQLite 文件
python -c "
import duckdb
con = duckdb.connect('data/warehouse/olist.duckdb')
con.execute(\"ATTACH 'data/warehouse/metabase.sqlite' AS sqlite_db (TYPE sqlite)\")
con.execute('COPY FROM DATABASE memory TO sqlite_db')
print('已生成 metabase.sqlite')
"
```

然后在 Metabase 添加数据库时选 **SQLite**，文件指向 `metabase.sqlite`。

> "Metabase 原生不支持 DuckDB，我用导出中间层的方式解决了连接问题。
> 这其实是个典型的工具适配问题——**选型的边界比选型本身更值得关注**。"

### 2.3 ⚠️ 重要：BI 层的正确做法

严格来说，BI 工具应该直连数仓。但本项目规模小，
**导出中间文件是合理的工程权衡**——避免为一个演示项目搭建 JDBC 驱动环境。


> "生产环境我会让 BI 直连数仓，并做查询权限管控。
> 本项目数据只有十几万行、更新频率低，
> 用导出文件的方式能省掉一整套驱动配置成本，性价比更高。"

---

## 3. 做三张看板（45 分钟）

### 看板 1：月度 GMV 趋势（折线图）

**数据源**：`ads_gmv_monthly`

**步骤**：
1. 点右上角 **+ New** → **Question**
2. 选数据库 → 选表 `ads_gmv_monthly`
3. 左下角 **Visualization** 选 **Line（折线）**
4. 配置：
   - X 轴：`order_month`
   - Y 轴：`gmv_delivered`（✅ 标准口径，不是 gmv_all！）
5. 点 **Save**，命名"月度 GMV 趋势"

**⭐ 加分操作**：再加一条 `gmv_all` 的线，做成双线对比图。
这样一眼就能看到两个口径的差距——**把你的治理故事可视化了**。


### 看板 2：品类销售占比（柱状图）

**数据源**：`ads_category_sales`

**步骤**：
1. New → Question → 选 `ads_category_sales`
2. Visualization 选 **Bar（柱状图）**
3. 配置：
   - X 轴：`product_category_cn`（中文品类名）
   - Y 轴：`gmv`
   - 排序：按 gmv 降序
4. Save 为"品类销售排行"

**可选**：改饼图看占比，用 `gmv_share_pct` 字段。

### 看板 3：客户 RFM 分布（柱状图）

**数据源**：`dws_customer_rfm`

**步骤**：
1. New → Question → 选 `dws_customer_rfm`
2. **Summarize** → Count by `rfm_segment`
3. Visualization 选 **Bar**
4. Save 为"客户 RFM 分布"

**⭐ 加分操作**：加一个筛选器，按 `m_score`（消费金额分）过滤，
做成"不同消费层级的客户分布"。

---

## 4. 组装 Dashboard（15 分钟）

1. 点 **+ New** → **Dashboard**
2. 命名"Olist 电商经营看板"
3. 把刚才做的三个 Question 拖进去
4. 调整布局

**最终效果应该是一屏能看到三张图**。

---

## 5. 截图存档（5 分钟）

保存到 `docs/images/`：

| 文件名 | 内容 |
|---|---|
| `bi_gmv_trend.png` | GMV 趋势（**双线对比版**） |
| `bi_category.png` | 品类排行 |
| `bi_rfm.png` | RFM 分布 |
| `bi_dashboard.png` | 完整看板一屏截图 |

**截图要求**：
- 全屏或足够大，字要看得清
- 包含浏览器地址栏（证明是本地跑的）
- 命名清晰，方便以后找

---

## 6. 常见故障

| 问题 | 解决 |
|---|---|
| `java 不是内部命令` | Java 没装或没重启 PowerShell |
| 端口 3000 被占用 | `java -jar metabase.jar -p 3001` 换端口 |
| 启动后打不开 | 等 3-5 分钟，第一次初始化很慢 |
| 找不到表 | 确认 `dbt run` 成功，且导出步骤执行了 |
| 中文乱码 | CSV 用 UTF-8 编码导出（DuckDB 默认就是） |

---

## 7. 时间不够时的降级方案

如果 Metabase 卡住超过 40 分钟，**立刻降级**：

### 方案：用 Python 直接画图（15 分钟）

```python
import duckdb
import matplotlib.pyplot as plt

con = duckdb.connect('data/warehouse/olist.duckdb')
df = con.execute("""
    SELECT order_month, gmv_delivered, gmv_all
    FROM ads_gmv_monthly ORDER BY order_month
""").df()

plt.figure(figsize=(12, 5))
plt.plot(df['order_month'], df['gmv_delivered'], label='标准口径(已送达)')
plt.plot(df['order_month'], df['gmv_all'], label='含取消(错误口径)')
plt.legend()
plt.title('GMV 口径对比')
plt.savefig('docs/images/bi_gmv_trend.png', dpi=150)
print('已保存')
```


> **永远记住**：跑通的降级方案 > 卡住的完美方案。
