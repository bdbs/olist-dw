# -*- coding: utf-8 -*-
"""
============================================================
脚本 01：从 Kaggle 下载 Olist 真实数据集（方案 A，可选）
------------------------------------------------------------
⚠️ 本脚本依赖 Kaggle 账号和 API Token，配置有门槛。
   如果 10 分钟内搞不定，直接改用方案 B：
       python scripts/02_generate_synthetic_data.py
   合成数据结构完全相同，不影响学习数仓建模。

------------------------------------------------------------
【配置步骤】（只需做一次）
------------------------------------------------------------
1. 注册 Kaggle 账号：https://www.kaggle.com （需邮箱 + 手机验证）

2. 登录后访问 https://www.kaggle.com/settings
   拉到 "API" 区块，点 "Create New Token"
   浏览器会下载一个 kaggle.json 文件

3. 把 kaggle.json 放到这个位置：
       Windows: C:\\Users\\<你的用户名>\\.kaggle\\kaggle.json
   注意是用户目录下，要新建 .kaggle 文件夹

4. 安装依赖： uv pip install kaggle

5. 运行本脚本： python scripts/01_download_olist.py

------------------------------------------------------------
【常见问题】
Q: 提示 403 Forbidden？
A: Token 没放对位置，或文件权限不对。
   Windows 下可试试：把 kaggle.json 的权限设为"仅自己可读"

Q: 提示 dataset not found？
A: 需要先在网页上打开一次该数据集页面并接受使用条款：
   https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Q: 下载很慢/中断？
A: 直接用方案 B 合成数据，完全不影响项目进度。
============================================================
"""
import os
import sys
from pathlib import Path
import zipfile

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)

DATASET = "olistbr/brazilian-ecommerce"

print("=" * 60)
print("脚本 01：下载 Olist 巴西电商数据集")
print("=" * 60)

try:
    from kaggle.api.kaggle_api_extended import KaggleApi
except ImportError:
    print("\n✗ 未安装 kaggle 库")
    print("  请先运行： uv pip install kaggle")
    print("  或者改用方案B：python scripts/02_generate_synthetic_data.py")
    sys.exit(1)

try:
    print(f"\n正在下载数据集：{DATASET} ...")
    api = KaggleApi()
    api.authenticate()
    api.dataset_download_files(DATASET, path=str(RAW_DIR), unzip=True)
    print(f"\n✓ 下载完成，文件在：{RAW_DIR}")
    print("\n目录内容：")
    for f in sorted(RAW_DIR.glob("*.csv")):
        print(f"  {f.name:<45} {f.stat().st_size/1e6:>8.2f} MB")
    print("\n下一步：python scripts/03_load_raw.py")
except Exception as e:
    print(f"\n✗ 下载失败：{e}")
    print("\n建议：改用方案B（合成数据），运行：")
    print("  python scripts/02_generate_synthetic_data.py")
    sys.exit(1)
