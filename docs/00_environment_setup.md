# 第 0 天：环境搭建手册

> 目标：30 分钟内让 `dbt debug` 全绿
> 适用：Windows 10/11，AMD Ryzen 7 PRO 4750U / 32GB RAM

---

## 为什么要先搭环境

小白 80% 的挫败发生在第一天。这一步我按**最小可用**原则设计——
能省的全省，让你尽快看到第一个 `dbt run` 成功。

**原则：不要追求理解每个命令，先跑通，再回头理解。**

---

## 步骤 1：安装 uv（Python 包管理器）

> ⚠️ **这一步的坑（#1 winget 装不上）**
> 如果用 `winget install` 失败（系统旧/商店组件缺失/企业策略禁用），
> **别跟它耗**——直接去官网下载安装包。
> 包管理器只是手段，装上才是目的。


**为什么用 uv 而不是 pip**：pip 装 dbt 要等 3-5 分钟，uv 只要 10-20 秒。
你这周时间紧，每一分钟都值钱。

打开 **PowerShell**（不是 CMD），粘贴：

```powershell
winget install Astral.UV
```

装完**关掉 PowerShell 重新打开**（否则环境变量不生效）。

验证：
```powershell
uv --version
```
看到版本号就是成功。

---

## 步骤 2：安装 Git

> ⚠️ **这一步的坑（#10 git 未初始化 / target 被提交）**
> 装完 Git 不代表仓库建好了。后面 `git add` 报
> `not a git repository` 就是忘了 `git init`。
> **而且建仓库第一件事是写 `.gitignore`**——
> 否则 `target/`（几百个编译产物）会被提交进去。

```powershell
winget install Git.Git
```

同样重启 PowerShell，然后配置身份（改成你自己的）：

```powershell
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
git config --global core.autocrlf false
```

> ⚠️ 最后一行很重要。Windows 默认会把换行符改成 CRLF，
> 会导致 Linux 环境下的脚本报错。设成 false 省心。

---

## 步骤 3：创建项目目录并建虚拟环境

```powershell
# 建议在 D 盘，路径不要有中文和空格！
mkdir D:\projects
cd D:\projects

# 把项目文件夹放进来（或从 GitHub clone）
cd olist-dw

# 创建虚拟环境
uv venv

# 激活虚拟环境
uv run dbt --version
```

**激活成功后，命令行前面会出现 `(.venv)` 字样。**

> 每次新开 PowerShell 都要重新执行 `uv run dbt --version`。
> 忘了这步会导致 "dbt 不是内部或外部命令"。

---

## 步骤 4：安装依赖

> ⚠️ **这一步的坑（#2 TLS 被掐 / #3 杀软拦截）**
> - 报 `SSL: CERTIFICATE_VERIFY_FAILED` → 换国内镜像源
> - 装到一半报权限错误 → **用虚拟环境**（`.venv`），别装到全局
> 虚拟环境既隔离依赖，又能减少杀软误判。


```powershell
uv pip install -r requirements.txt
```

约 30 秒完成。验证：
```powershell
dbt --version
```

看到 dbt 版本号 + duckdb 插件 = 成功。

---

## 步骤 5：配置数据库连接（最容易踩坑）

### 5.1 找到你的用户目录

在 PowerShell 里执行：
```powershell
echo $env:USERPROFILE
```
输出类似 `C:\Users\zhangsan`

### 5.2 创建 .dbt 文件夹并放配置文件

```powershell
mkdir $env:USERPROFILE\.dbt
copy profiles.yml.example $env:USERPROFILE\.dbt\profiles.yml
notepad $env:USERPROFILE\.dbt\profiles.yml
```

### 5.3 修改 path（关键！）

把这一行改成你自己的路径：

```yaml
path: 'D:/projects/olist-dw/data/warehouse/olist.duckdb'
```

> ⚠️ **三个必踩的坑**：
> 1. 必须用**正斜杠** `/`，不能用反斜杠 `\`
> 2. 路径**不能有中文**
> 3. 路径**不能有空格**

错误示范：`D:\我的项目\olist dw\data\olist.duckdb` ❌
正确示范：`D:/projects/olist-dw/data/warehouse/olist.duckdb` ✅

---

## 步骤 6：生成数据

> 🔴 **这一步的坑（#4 GBK 编码 — 中文 Windows 头号坑）**
> 如果报 `UnicodeDecodeError: 'gbk' codec can't decode byte 0xae`：
> 文件是 UTF-8，但 Python 默认按系统编码 **GBK** 读。
>
> ```powershell
> $env:PYTHONUTF8=1          # 临时（当前窗口）
> setx PYTHONUTF8 1          # 永久（重开窗口生效）
> ```
>
> **中文 Windows 上跑任何 Python 项目，第一件事就是设这个。**
> 这个坑后面还会以 3 种变体出现（文件名乱码、解压非法字符、脚本 BOM）。


```powershell
python scripts/02_generate_synthetic_data.py
```

看到 4 个 ✓ 和 CSV 文件列表 = 成功。

数据量：3 万客户 / 4 万订单 / 12 万明细，文件 < 20MB。

---

## 步骤 7：验证（关键里程碑）

```powershell
dbt debug
```

**必须看到全部绿色**。如果报错，对照下面的排查表。

---

## 排错速查表

| 报错信息 | 原因 | 解决 |
|---|---|---|
| `dbt 不是内部或外部命令` | 虚拟环境没激活 | 执行 `uv run dbt --version` |
| `Could not find profile named 'olist_dw'` | profiles.yml 位置或名字错 | 检查 `~\.dbt\profiles.yml` 是否存在 |
| `IO Error: Cannot open file` | 路径用了反斜杠或有中文 | 改成正斜杠、去掉中文 |
| `dbt: command not found`（PowerShell） | 执行策略限制 | 用 `uv run dbt debug` 代替 |
| Python 版本报错 | Python < 3.9 | 装 Python 3.11：`winget install Python.Python.3.11` |
| 安装时卡住不动 | 网络问题 | 换国内源：`uv pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple` |

---

## 步骤 8：第一次运行（感受一下）

```powershell
dbt run
```

看到一串 ✓ 和 `Completed successfully` = 你的数仓建好了！

```powershell
dbt docs generate
dbt docs serve
```

浏览器打开 `http://localhost:8080`，
**点右下角的蓝色圆圈图标，能看到血缘 DAG 图**——
这就是你的第一个治理证据。

---

## 你的机器专属优化

| 设置 | 值 | 原因 |
|---|---|---|
| `threads` | **8**（不是 16） | 4750U 是 8 核 16 线程。分析查询触发 AVX2 后，超线程收益远小于温度降频损失 |
| `memory_limit` | **20GB** | 你有 32G，留 12G 给 Windows + Chrome |
| 跑大任务前 | **关掉 Chrome** | 浏览器常吃 4-6G，关掉能显著减少磁盘溢写 |
| 杀毒软件 | 把项目目录加入 Defender 排除项 | 实时扫描会把 DuckDB 文件 I/O 拖慢数倍 |

添加 Defender 排除项：
```
Windows 安全中心 → 病毒和威胁防护 → 管理设置 → 排除项 → 添加文件夹 → D:\projects
```

---

## 环境快照策略（重要）

**每完成一个小阶段就 git commit 一次。**

```powershell
git add .
git commit -m "第0天：环境搭建完成，dbt debug 全绿"
```

崩了随时 `git checkout .` 回滚。这是小白最重要的保险。

---

## ★ 完整踩坑清单

本文档只标注了**本阶段**的坑。
全部 20 个坑（含模型开发、数据接入、交付协作）见：

> 📄 **`24_pitfalls_mvp.md`**

建议**操作前先翻一遍对应阶段**，能省 80% 调试时间。

---

## 今天结束后你应该有

- [x] `dbt --version` 能输出版本
- [x] `dbt debug` 全绿
- [x] `dbt run` 成功
- [x] 浏览器能打开血缘图
- [x] 至少 1 次 git commit

**全打勾了？明天开始建模。**
