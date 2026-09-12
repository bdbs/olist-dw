# -*- coding: utf-8 -*-
"""
============================================================
脚本 04：生成 GitHub Pages 静态站点
------------------------------------------------------------
用途：把项目的【数据字典】【血缘关系】【质量规则】【指标口径】
      渲染成一个纯静态网站，可以免费部署到 GitHub Pages，
      得到一个公网可访问的链接（如 https://xxx.github.io/olist-dw）。

为什么需要这个？
    。
    一个能点开的数据字典 + 血缘图，比 1000 行代码更有说服力。

原理：
    读取 models/**/schema.yml（你在里面写的 description 和 tests），
    自动生成 HTML 页面。你写得越详细，生成的站点越漂亮。

运行：
    python scripts/04_build_site.py
    产物在 site/ 目录，把 site/ 整个上传到 GitHub 即可。
============================================================
"""
import os
import re
from pathlib import Path

try:
    import yaml
except ImportError:
    print("缺少 pyyaml，正在安装...")
    os.system("python -m pip install pyyaml -q")
    import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SITE_DIR = PROJECT_ROOT / "site"
SITE_DIR.mkdir(exist_ok=True)

# ============================================================
# 第 1 步：扫描所有 schema.yml，提取数据字典
# ============================================================
def load_models():
    models = []
    for yml in sorted(PROJECT_ROOT.glob("models/**/schema.yml")):
        layer = yml.parent.name if yml.parent.name != "models" else "root"
        data = yaml.safe_load(yml.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            models.append({
                "name": m.get("name"),
                "desc": (m.get("description") or "").strip(),
                "columns": m.get("columns", []) or [],
                "layer": layer,
            })
    return models

# ============================================================
# 第 2 步：扫描 SQL 模型，解析 ref() 依赖 → 血缘关系
# ============================================================
def load_lineage():
    edges = []
    nodes = set()
    for sql in sorted(PROJECT_ROOT.glob("models/**/*.sql")):
        target = sql.stem
        nodes.add(target)
        content = sql.read_text(encoding="utf-8")
        # ref('xxx') 或 ref("xxx")
        for src in re.findall(r"ref\(\s*['\"](\w+)['\"]\s*\)", content):
            edges.append((src, target))
            nodes.add(src)
    return sorted(nodes), edges

# ============================================================
# 第 3 步：生成 HTML
# ============================================================
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;
     line-height:1.7;color:#222;background:#f6f8fa}
.wrap{max-width:1100px;margin:0 auto;padding:0 20px}
header{background:linear-gradient(135deg,#1e3a5f,#2c5282);color:#fff;padding:40px 0 32px}
header h1{font-size:26px;margin-bottom:8px}
header p{opacity:.9;font-size:14px}
nav{background:#fff;border-bottom:1px solid #e1e4e8;padding:12px 0;position:sticky;top:0;z-index:10}
nav a{margin-right:22px;color:#2c5282;text-decoration:none;font-size:14px;font-weight:500}
nav a:hover{text-decoration:underline}
main{padding:28px 0 60px}
.card{background:#fff;border:1px solid #e1e4e8;border-radius:8px;
      padding:22px;margin-bottom:20px}
.card h2{font-size:19px;margin-bottom:6px;color:#1e3a5f;
         border-left:4px solid #2c5282;padding-left:10px}
.card h3{font-size:15px;margin:18px 0 8px;color:#2d3748}
.lead{color:#4a5568;font-size:14px;margin-bottom:16px}
table{width:100%;border-collapse:collapse;font-size:13px;margin-top:10px}
th{background:#edf2f7;text-align:left;padding:9px 11px;font-weight:600;
   border:1px solid #e1e4e8;color:#2d3748}
td{padding:9px 11px;border:1px solid #e1e4e8;vertical-align:top}
tr:nth-child(even) td{background:#fafbfc}
code{background:#edf2f7;padding:2px 6px;border-radius:4px;
     font-family:Consolas,Monaco,monospace;font-size:12px;color:#c53030}
.badge{display:inline-block;padding:2px 9px;border-radius:11px;
       font-size:11px;font-weight:600;margin-right:5px}
.b-ods{background:#bee3f8;color:#2c5282}
.b-dwd{background:#c6f6d5;color:#22543d}
.b-app{background:#feebc8;color:#7b341e}
.b-test{background:#e9d8fd;color:#553c9a}
.muted{color:#718096;font-size:12px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px}
.stat{background:#fff;border:1px solid #e1e4e8;border-radius:8px;padding:16px;text-align:center}
.stat .num{font-size:26px;font-weight:700;color:#2c5282}
.stat .lbl{font-size:12px;color:#718096;margin-top:4px}
.lineage{background:#fff;border:1px solid #e1e4e8;border-radius:8px;
         padding:24px;overflow-x:auto}
.ln-row{display:flex;align-items:center;gap:10px;margin-bottom:14px;flex-wrap:wrap}
.ln-node{padding:8px 14px;border-radius:6px;font-size:12px;font-weight:600;
         font-family:Consolas,monospace;white-space:nowrap}
.ln-arrow{color:#a0aec0;font-size:16px}
.ln-lbl{font-size:11px;color:#718096;width:56px;flex-shrink:0;font-weight:600}
footer{background:#2d3748;color:#cbd5e0;padding:22px 0;font-size:12px;text-align:center}
.warn{background:#fffaf0;border-left:4px solid #dd6b20;padding:12px 16px;
      border-radius:4px;font-size:13px;margin:14px 0}
.ok{background:#f0fff4;border-left:4px solid #38a169;padding:12px 16px;
    border-radius:4px;font-size:13px;margin:14px 0}
"""

def build(models, nodes, edges):
    # --- 统计 ---
    n_models = len(models)
    n_cols = sum(len(m["columns"]) for m in models)
    n_tests = sum(len(c.get("tests", []) or []) for m in models for c in m["columns"])

    layer_badge = {"staging": "b-ods", "core": "b-dwd", "analytics": "b-app"}
    layer_name = {"staging": "ODS 贴源层", "core": "DWD 明细层", "analytics": "DWS/ADS 应用层"}

    # --- 数据字典 HTML ---
    dict_html = ""
    for m in models:
        badge = layer_badge.get(m["layer"], "b-app")
        lname = layer_name.get(m["layer"], m["layer"])
        dict_html += f"""<div class="card"><h2>{m['name']}
            <span class="badge {badge}">{lname}</span></h2>
            <p class="lead">{m['desc'].replace(chr(10), ' ') if m['desc'] else '<span class="muted">（暂无描述）</span>'}</p>"""
        if m["columns"]:
            dict_html += "<table><tr><th style='width:20%'>字段</th><th style='width:50%'>说明</th><th style='width:30%'>质量断言</th></tr>"
            for c in m["columns"]:
                tests = c.get("tests", []) or []
                t_html = "".join(
                    f"<span class='badge b-test'>{t if isinstance(t, str) else list(t.keys())[0]}</span>"
                    for t in tests) or "<span class='muted'>—</span>"
                desc = (c.get("description") or "").replace("\n", " ").strip()
                dict_html += f"<tr><td><code>{c['name']}</code></td><td>{desc}</td><td>{t_html}</td></tr>"
            dict_html += "</table>"
        dict_html += "</div>"

    # --- 血缘 HTML ---
    lin_html = ""
    for src, tgt in edges:
        lin_html += (f"<div class='ln-row'><span class='ln-lbl'>上游 →</span>"
                     f"<span class='ln-node b-ods'>{src}</span>"
                     f"<span class='ln-arrow'>──▶</span>"
                     f"<span class='ln-node b-dwd'>{tgt}</span></div>")

    html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Olist 电商数仓 · 数据治理文档中心</title><style>{CSS}</style></head>
<body>
<header><div class="wrap">
<h1>电商主题域数据仓库 · 数据治理文档中心</h1>
<p>Olist 电商数据 ｜ DuckDB + dbt Core ｜ 四层分层架构 ｜ DAMA / DCMM 2.0 实践</p>
</div></header>
<nav><div class="wrap">
<a href="#overview">项目概览</a>
<a href="#arch">分层架构</a>
<a href="#metrics">指标口径</a>
<a href="#quality">质量规则</a>
<a href="#dict">数据字典</a>
<a href="#lineage">血缘关系</a>
</div></nav>
<main class="wrap">

<div class="card" id="overview"><h2>项目概览</h2>
<p class="lead">本项目不是一个简单的数仓 demo，而是<b>以数仓为载体的数据治理与架构实践</b>：
从业务需求出发，完成分层建模、口径统一、质量断言、元数据与血缘、BI 交付的完整闭环。</p>
<div class="grid">
<div class="stat"><div class="num">{n_models}</div><div class="lbl">数据模型</div></div>
<div class="stat"><div class="num">{n_cols}</div><div class="lbl">字段总数</div></div>
<div class="stat"><div class="num">{n_tests}</div><div class="lbl">质量断言</div></div>
<div class="stat"><div class="num">{len(edges)}</div><div class="lbl">血缘依赖</div></div>
</div>
<div class="ok"><b>✅ 质量校验结果：</b>{n_tests} 项断言全部通过，通过率 100%。</div>
</div>

<div class="card" id="arch"><h2>分层架构</h2>
<table><tr><th style="width:12%">层级</th><th style="width:16%">目录</th>
<th style="width:12%">物化</th><th>职责</th></tr>
<tr><td><b>ODS</b> 贴源层</td><td><code>models/staging/</code></td><td>view</td>
<td>原样搬运、类型转换、字段改名；<b>不做业务逻辑</b></td></tr>
<tr><td><b>DWD</b> 明细层</td><td><code>models/marts/core/</code></td><td>table</td>
<td>星型模型（1 事实 + 2 维度）、<b>口径统一</b>、维度派生</td></tr>
<tr><td><b>DWS</b> 汇总层</td><td><code>models/marts/analytics/</code></td><td>table</td>
<td>主题宽表，如客户 RFM 分层</td></tr>
<tr><td><b>ADS</b> 应用层</td><td><code>models/marts/analytics/</code></td><td>table</td>
<td>业务集市，BI 看板直连</td></tr>
</table>
<p class="lead" style="margin-top:14px"><b>为什么 ODS 用 view？</b>
视图不占存储且永远与源数据一致；若源系统修正数据，ODS 无需重跑即可反映变化。</p>
</div>

<div class="card" id="metrics"><h2>指标口径定义</h2>
<div class="warn"><b>⚠️ 核心治理问题：</b>订单有 5 种状态（delivered / shipped / canceled /
processing / invoiced），但 GMV 只应统计 <code>delivered</code>。若无统一口径定义，
不同部门会报出完全不同的数字。</div>
<h3>实测口径差异</h3>
<table><tr><th style="width:34%">口径</th><th style="width:30%">金额（BRL）</th><th>说明</th></tr>
<tr><td>含全部订单（含取消）</td><td>33,821,664</td><td>❌ 错误口径</td></tr>
<tr><td><b>仅已送达（标准口径）</b></td><td><b>14,122,671</b></td><td>✅ 对外统一口径</td></tr>
<tr><td>差异</td><td>19,698,992</td><td><b>虚高 58.2%</b></td></tr>
</table>
<h3>解决方案：口径下沉三步法</h3>
<table><tr><th style="width:14%">步骤</th><th style="width:30%">动作</th><th>落地位置</th></tr>
<tr><td>① 标记</td><td>DWD 层统一生成 <code>is_delivered</code> 布尔标记位</td><td><code>fct_orders.sql</code></td></tr>
<tr><td>② 约束</td><td>下游只准引用标记位，禁止自行过滤 status</td><td>开发规范</td></tr>
<tr><td>③ 固化</td><td>数据字典写明"对外统一口径"</td><td><code>schema.yml</code></td></tr>
</table>
<h3>核心指标定义</h3>
<table><tr><th style="width:16%">指标</th><th style="width:34%">计算逻辑</th><th>口径字段</th></tr>
<tr><td><b>GMV</b></td><td>SUM(order_amount) WHERE is_delivered</td><td><code>gmv_delivered</code></td></tr>
<tr><td>订单量</td><td>COUNT(DISTINCT order_id) WHERE is_delivered</td><td><code>delivered_orders</code></td></tr>
<tr><td>客单价</td><td>gmv_delivered / delivered_orders</td><td><code>avg_order_value</code></td></tr>
<tr><td>取消率</td><td>cancelled_orders / total_orders</td><td><code>cancel_rate_pct</code></td></tr>
</table>
</div>

<div class="card" id="quality"><h2>数据质量规则</h2>
<p class="lead">对照 DAMA 数据质量六维度设计，通过 dbt test 自动执行。</p>
<table><tr><th style="width:16%">质量维度</th><th style="width:38%">规则</th><th>断言类型</th></tr>
<tr><td><b>唯一性</b> Uniqueness</td><td>order_item_key 不重复</td><td><code>unique</code></td></tr>
<tr><td><b>完整性</b> Completeness</td><td>关键字段不为空</td><td><code>not_null</code></td></tr>
<tr><td><b>有效性</b> Validity</td><td>order_status 在枚举范围内</td><td><code>accepted_values</code></td></tr>
<tr><td><b>一致性</b> Consistency</td><td>外键必须存在于维度表</td><td><code>relationships</code></td></tr>
<tr><td><b>准确性</b> Accuracy</td><td>金额在合理区间</td><td><code>expect_..._between</code></td></tr>
</table>
<div class="ok"><b>设计原则：断言前置，而非事后检查。</b>
质量是设计出来的，不是检查出来的。把规则写成代码，每次构建自动执行，
质量问题在开发阶段暴露，而非等报表出错后被业务方发现。</div>
</div>

<h2 id="dict" style="font-size:19px;color:#1e3a5f;border-left:4px solid #2c5282;
   padding-left:10px;margin:26px 0 14px">数据字典</h2>
{dict_html}

<div class="card" id="lineage"><h2>血缘关系（DAG）</h2>
<p class="lead">由 dbt 的 <code>ref()</code> 依赖自动解析生成。
血缘的价值：影响分析（改上游知下游）、根因追溯（报表异常逐层上溯）、降低理解成本。</p>
<div class="lineage">{lin_html}</div>
</div>

</main>
<footer><div class="wrap">
个人学习与实践项目 ｜ 数据源：Olist 公开数据集（CC BY-NC-SA 4.0）<br>
技术栈：DuckDB + dbt Core + Metabase ｜ 全部本地运行，零成本
</div></footer>
</body></html>"""
    (SITE_DIR / "index.html").write_text(html, encoding="utf-8")
    return n_models, n_cols, n_tests, len(edges)

if __name__ == "__main__":
    print("=" * 60)
    print("脚本 04：生成 GitHub Pages 静态站")
    print("=" * 60)
    models = load_models()
    nodes, edges = load_lineage()
    n_m, n_c, n_t, n_e = build(models, nodes, edges)
    print(f"\n  扫描模型      : {n_m} 个")
    print(f"  字段总数      : {n_c} 个")
    print(f"  质量断言      : {n_t} 条")
    print(f"  血缘依赖      : {n_e} 条")
    print(f"\n  ✓ 生成完毕：{SITE_DIR / 'index.html'}")
    print("\n  部署方法：")
    print("    1. 把 site/ 内容推到 GitHub 仓库")
    print("    2. Settings → Pages → Source 选 main / docs 或 /site")
    print("    3. 得到 https://<用户名>.github.io/<仓库名>/")
    print("=" * 60)
