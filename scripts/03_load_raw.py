# -*- coding: utf-8 -*-
"""
============================================================
脚本 03：把 CSV 原始数据装进 DuckDB（带字段名自动对齐）
------------------------------------------------------------
用途：模拟真实项目里"业务系统导出 CSV → 装载进数仓"这一步。
      在真实公司里，这一步通常由 DataX / SeaTunnel / Flink 等工具做，
      原理都一样：读文件 → 建表 → 写进去。

【本版的增强：字段名自动对齐】
    不同来源的 CSV，字段名可能不一致：
      旧版合成数据 : customer_zip_code    / product_category
      真实 Olist   : customer_zip_code_prefix / product_category_name
    本脚本会自动检测并统一成"真实 Olist 契约"的字段名，
    这样无论手上是哪种 CSV，下游模型都不用改。

运行：python scripts/03_load_raw.py
============================================================
"""
from pathlib import Path
import duckdb

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
DB_PATH = PROJECT_ROOT / "data" / "warehouse" / "olist.duckdb"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

# ------------------------------------------------------------
# 字段名对齐规则：旧名 → 标准名（真实 Olist 契约）
# ------------------------------------------------------------
RENAME_MAP = {
    "raw_customers":   {"customer_zip_code": "customer_zip_code_prefix"},
    "raw_products":    {"product_category": "product_category_name"},
}

FILES = {
    # ---- 交易主题域（原有 4 张）----
    "olist_customers_dataset.csv":   "raw_customers",
    "olist_orders_dataset.csv":      "raw_orders",
    "olist_order_items_dataset.csv": "raw_order_items",
    "olist_products_dataset.csv":    "raw_products",

    # ---- 支付主题域 ----
    "olist_order_payments_dataset.csv":          "raw_order_payments",
    # ---- 评价主题域 ----
    "olist_order_reviews_dataset.csv":           "raw_order_reviews",
    # ---- 卖家主题域 ----
    "olist_sellers_dataset.csv":                 "raw_sellers",
    # ---- 地理主题域（100 万行，本项目最大表）----
    "olist_geolocation_dataset.csv":             "raw_geolocation",
    # ---- 参照数据：品类翻译码表 ----
    "product_category_name_translation.csv":     "raw_category_translation",
}

# 可选文件：缺失不阻断（合成数据方案下没有这些文件）
OPTIONAL = {
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_sellers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "product_category_name_translation.csv",
}

print("=" * 60)
print("脚本 03：装载原始数据到 DuckDB（自动对齐字段名）")
print("=" * 60)

con = duckdb.connect(str(DB_PATH))
con.execute("SET memory_limit='8GB'")
con.execute("SET threads=8")

print("\n开始装载...\n")

for fname, tbl in FILES.items():
    fpath = RAW_DIR / fname
    if not fpath.exists():
        if fname in OPTIONAL:
            print(f"  - 跳过（可选文件）：{fname}")
            continue
        print(f"  ✗ 找不到文件：{fname}")
        print(f"    请先运行：python scripts/02_generate_synthetic_data.py")
        continue

    path_sql = str(fpath).replace(chr(92), "/")

    # 第一步：先读到临时表，看看实际有哪些列
    con.execute(f"CREATE OR REPLACE TABLE _tmp AS "
                f"SELECT * FROM read_csv_auto('{path_sql}', header=true) LIMIT 0")
    cols = [r[0] for r in con.execute("DESCRIBE _tmp").fetchall()]

    # 第二步：按规则生成 SELECT 表达式（旧名 → 新名）
    renames = RENAME_MAP.get(tbl, {})
    exprs = []
    applied = []
    for c in cols:
        if c in renames and renames[c] not in cols:
            exprs.append(f'"{c}" AS "{renames[c]}"')
            applied.append(f"{c} → {renames[c]}")
        else:
            exprs.append(f'"{c}"')

    select_sql = ",\n               ".join(exprs) if exprs else "*"

    con.execute(f"""
        CREATE OR REPLACE TABLE {tbl} AS
        SELECT {select_sql}
        FROM read_csv_auto('{path_sql}', header=true)
    """)

    cnt = con.execute(f"SELECT count(*) FROM {tbl}").fetchone()[0]
    print(f"  ✓ {tbl:<18} {cnt:>10,} 行   <- {fname}")
    if applied:
        print(f"      字段名已自动对齐：{', '.join(applied)}")

con.execute("DROP TABLE IF EXISTS _tmp")

print("\n装载完成。数据库位置：", DB_PATH)
print("\n各表实际字段名（用于核对）：")
for tbl in FILES.values():
    try:
        cols = [r[0] for r in con.execute(f"DESCRIBE {tbl}").fetchall()]
        print(f"  {tbl:<18} {cols}")
    except Exception:
        pass

con.close()
print("\n下一步：dbt run")
