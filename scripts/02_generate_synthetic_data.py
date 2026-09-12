# -*- coding: utf-8 -*-
"""
============================================================
脚本 02：生成合成电商数据（数据源兜底方案 B）
------------------------------------------------------------
用途：当 Kaggle 下载 Olist 数据失败时，用本脚本生成结构完全一致的
      合成数据，保证项目不中断。

小白说明：
    Olist 是巴西一家电商平台的真实脱敏数据。它的表结构长这样：
      - customers     客户表（谁买的）
      - orders        订单表（哪一单）
      - order_items   订单明细表（单里有什么商品）
      - products      商品表（商品是什么）
      这四张表通过 ID 互相连接，构成一个典型的电商业务模型。

    本脚本用 DuckDB 的 range() 函数批量"造"出同样结构的假数据。
    为什么要造假数据？因为数仓项目关心的是【表怎么设计、怎么关联、
    怎么分层】，数据是真的假的并不影响你学习这些。

产出：
    data/raw/ 目录下 4 个 CSV 文件

运行：
    python scripts/02_generate_synthetic_data.py
============================================================
"""

import os
import sys
from pathlib import Path

import duckdb

# ------------------------------------------------------------
# 第 0 步：确定路径
# ------------------------------------------------------------
# __file__ 是本脚本自己的路径，.parent 是上一级
# 所以 PROJECT_ROOT 就是 olist-dw 这个文件夹
PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)  # 不存在就创建

print("=" * 60)
print("脚本 02：生成合成电商数据")
print("=" * 60)

# ------------------------------------------------------------
# 第 1 步：连接 DuckDB
# ------------------------------------------------------------
# DuckDB 是一个"数据库"，但它不需要安装服务器，
# 就是一个文件（像 Word 文档一样），放在你的硬盘上。
# 下面这行就是"打开/创建一个数据库文件"
DB_PATH = PROJECT_ROOT / "data" / "warehouse" / "olist.duckdb"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(DB_PATH))

# 根据你的机器调参（你的是 8核16线程 / 32G内存）
# 这里设小一点没关系，合成数据量很小
con.execute("SET memory_limit='4GB'")
con.execute("SET threads=4")

print(f"\n[1/4] 数据库已连接：{DB_PATH}")

# ------------------------------------------------------------
# 第 2 步：生成 4 张原始表（ODS 层的数据来源）
# ------------------------------------------------------------
# 每条 SQL 都配了大白话解释，你可以对照着理解

print("\n[2/4] 正在生成原始数据...")

# ---- 表 1：客户表 customers ----
# 大白话：造 3 万个客户，每人一个 ID，随机分配所在州和城市
# range(1, 30001) 的意思是生成 1 到 30000 这 3 万个数字，
# 每个数字变成一个客户，c 就是客户编号
con.execute("""
CREATE OR REPLACE TABLE stg_customers AS
SELECT
    c                                    AS customer_id,        -- 客户ID（主键）
    'cust_' || printf('%05d', c)         AS customer_unique_id, -- 客户唯一标识（补零成5位）
    CAST(random() * 99999999 AS INTEGER) AS customer_zip_code_prefix,  -- 邮编前缀（对齐真实 Olist 列名）
    -- ARRAY[...] 造一个列表，[1+随机整数] 从中随机取一个值
    (ARRAY['SP','RJ','MG','RS','PR','SC','BA','DF','GO','PE'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS customer_state,  -- 州（2位缩写）
    (ARRAY['sao paulo','rio de janeiro','belo horizonte',
           'porto alegre','curitiba','florianopolis',
           'salvador','brasilia','goiania','recife'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS customer_city    -- 城市
FROM range(1, 30001) t(c)
""")
print("      ✓ stg_customers  客户表：30,000 行")

# ---- 表 2：订单表 orders ----
# 大白话：造 4 万笔订单，每笔随机挂在一个客户名下，
# 随机给一个状态，随机给一个下单时间
con.execute("""
CREATE OR REPLACE TABLE stg_orders AS
SELECT
    o                                    AS order_id,           -- 订单ID（主键）
    CAST(random() * 29999 AS INTEGER) + 1 AS customer_id,       -- 属于哪个客户（外键，1~30000）
    -- 订单状态：只有 delivered 才算真正成交，这个细节后面会成"坑"
    (ARRAY['delivered','delivered','delivered','shipped',
           'canceled','processing','invoiced'])
        [1 + CAST(random() * 6 AS INTEGER)] AS order_status,
    -- 下单时间：从 2016-09-01 往后随机推 0~730 天（两年）
    (TIMESTAMP '2016-09-01 00:00:00'
        + INTERVAL (CAST(random() * 730 AS INTEGER)) DAY) AS order_purchase_timestamp
FROM range(1, 40001) t(o)
""")
print("      ✓ stg_orders     订单表：40,000 行")

# ---- 表 3：订单明细表 order_items ----
# 大白话：造 12 万条明细。一笔订单可以含多个商品，
# 所以明细表比订单表大。这是数仓里最重要的"事实表"来源
# ---- 表 5：卖家表 sellers ----
con.execute("""
CREATE OR REPLACE TABLE stg_sellers AS
SELECT
    s                                    AS seller_id,
    CAST(random() * 99999 AS INTEGER)    AS seller_zip_code_prefix,
    (ARRAY['sao paulo','rio de janeiro','belo horizonte',
           'porto alegre','curitiba','florianopolis',
           'salvador','brasilia','goiania','recife'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS seller_city,
    (ARRAY['SP','RJ','MG','RS','PR','SC','BA','DF','GO','PE'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS seller_state
FROM range(1, 3001) t(s)
""")
print("      ✓ stg_sellers   卖家表：3,000 行")

# ---- 表 6：支付表 order_payments ----
con.execute("""
CREATE OR REPLACE TABLE stg_order_payments AS
SELECT
    o                                    AS order_id,
    1                                    AS payment_sequential,
    (ARRAY['credit_card','credit_card','credit_card','boleto',
           'voucher','debit_card'])
        [1 + CAST(random() * 5 AS INTEGER)] AS payment_type,
    CAST(1 + random() * 10 AS INTEGER)   AS payment_installments,
    CAST(20 + random() * 480 AS DECIMAL(12,2)) AS payment_value
FROM range(1, 40001) t(o)
""")
print("      ✓ stg_order_payments 支付表：40,000 行")

# ---- 表 7：评价表 order_reviews ----
con.execute("""
CREATE OR REPLACE TABLE stg_order_reviews AS
SELECT
    ROW_NUMBER() OVER (ORDER BY o)       AS review_id,
    o                                    AS order_id,
    CAST(1 + random() * 4 AS INTEGER)    AS review_score,
    CASE WHEN random() < 0.3
         THEN 'otimo produto' ELSE NULL END AS review_comment_title,
    CASE WHEN random() < 0.4
         THEN 'entrega rapida, recomendo' ELSE NULL END AS review_comment_message,
    (TIMESTAMP '2016-09-01 00:00:00'
        + INTERVAL (CAST(random() * 730 AS INTEGER)) DAY) AS review_creation_date,
    (TIMESTAMP '2016-09-01 00:00:00'
        + INTERVAL (CAST(random() * 730 AS INTEGER) + 1) DAY) AS review_answer_timestamp
FROM range(1, 40001) t(o)
WHERE random() < 0.6
""")
print("      ✓ stg_order_reviews 评价表：约 24,000 行")

# ---- 表 8：地理表 geolocation ----
con.execute("""
CREATE OR REPLACE TABLE stg_geolocation AS
SELECT
    CAST(random() * 99999 AS INTEGER)    AS geolocation_zip_code_prefix,
    CAST(-33.0 + random() * 20 AS DOUBLE) AS geolocation_lat,
    CAST(-73.0 + random() * 25 AS DOUBLE) AS geolocation_lng,
    (ARRAY['sao paulo','rio de janeiro','belo horizonte',
           'porto alegre','curitiba','florianopolis',
           'salvador','brasilia','goiania','recife'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS geolocation_city,
    (ARRAY['SP','RJ','MG','RS','PR','SC','BA','DF','GO','PE'])
        [1 + CAST(random() * 9 AS INTEGER)]  AS geolocation_state
FROM range(1, 5001) t(g)
""")
print("      ✓ stg_geolocation 地理表：5,000 行")

# ---- 表 9：品类翻译表 category_translation ----
con.execute("""
CREATE OR REPLACE TABLE stg_category_translation AS
SELECT * FROM (VALUES
    ('electronics',            'electronics'),
    ('home_appliance',         'home_appliance'),
    ('furniture_decor',        'furniture_decor'),
    ('books',                  'books'),
    ('sports_leisure',         'sports_leisure'),
    ('toys',                   'toys'),
    ('health_beauty',          'health_beauty'),
    ('computers_accessories',  'computers_accessories'),
    ('watches_gifts',          'watches_gifts'),
    ('auto',                   'auto')
) AS t(product_category_name, product_category_name_english)
""")
print("      ✓ stg_category_translation 品类翻译表：10 行")
# ---- 表 4：商品表 products ----
con.execute("""
CREATE OR REPLACE TABLE stg_products AS
SELECT
    p                                     AS product_id,      -- 商品ID（主键）
    CAST(50 + random() * 4950 AS INTEGER) AS product_weight_g,-- 重量（克）
    CAST(10 + random() * 90 AS INTEGER)   AS product_length_cm,
    CAST(5 + random() * 45 AS INTEGER)    AS product_height_cm,
    (ARRAY['electronics','home_appliance','furniture_decor',
           'books','sports_leisure','toys','health_beauty',
           'computers_accessories','watches_gifts','auto'])
        [1 + CAST(random() * 9 AS INTEGER)] AS product_category_name  -- 品类（对齐真实 Olist 列名）
FROM range(1, 30001) t(p)
""")
print("      ✓ stg_products   商品表：30,000 行")

# ------------------------------------------------------------
# 第 3 步：导出成 CSV 文件
# ------------------------------------------------------------
# 为什么要导出 CSV？因为真实项目里，原始数据通常就是 CSV/Excel，
# 我们要模拟"从业务系统拿到原始文件"这个环节
print("\n[3/4] 正在导出 CSV 到 data/raw/ ...")

tables = {
    "stg_customers":   "olist_customers_dataset.csv",
    "stg_orders":      "olist_orders_dataset.csv",
    "stg_order_items": "olist_order_items_dataset.csv",
    "stg_products":    "olist_products_dataset.csv",
    "stg_sellers":              "olist_sellers_dataset.csv",
    "stg_order_payments":       "olist_order_payments_dataset.csv",
    "stg_order_reviews":        "olist_order_reviews_dataset.csv",
    "stg_geolocation":          "olist_geolocation_dataset.csv",
    "stg_category_translation": "product_category_name_translation.csv",
}

for tbl, fname in tables.items():
    out_path = RAW_DIR / fname
    # COPY 是 DuckDB 的导出命令，相当于"另存为"
    con.execute(f"""
        COPY {tbl}
        TO '{str(out_path).replace(chr(92), "/")}'
        (FORMAT CSV, HEADER TRUE)
    """)
    size_mb = out_path.stat().st_size / 1e6
    print(f"      ✓ {fname:<38} {size_mb:>6.2f} MB")

# ------------------------------------------------------------
# 第 4 步：清理 & 完成
# ------------------------------------------------------------
# 把临时表删掉，保持数据库干净
for tbl in tables.keys():
    con.execute(f"DROP TABLE IF EXISTS {tbl}")

con.close()

print("\n[4/4] 完成！")
print("=" * 60)
print(f"生成的 CSV 文件在：{RAW_DIR}")
print()
print("下一步：运行  python scripts/03_load_raw.py  把 CSV 装进数据库")
print("=" * 60)
