# -*- coding: utf-8 -*-
"""
一键规范化 docs 文件名

【解决什么】
    补丁包用 ASCII 名交付（规避 Windows 编码问题），
    解压后需要改回中文名；同时清理此前解压产生的乱码副本。
    本脚本一次性完成，不用一条条敲 Rename-Item。

【三件事】
    1. 英文/ASCII 名  → 中文正确名（映射表）
    2. 删除乱码副本（保留正确名那份）
    3. 报告缺失文件（对照 27 份基准清单）

【为什么脚本名用 ASCII】
    若命名为「规范化文件名.py」，它自己会在中文 Windows 上乱码。
    前三次踩坑（Python GBK、Expand-Archive 非法字符、文件名乱码）
    的教训：跨工具传递的路径一律优先 ASCII。

【用法】
    .venv\Scripts\python.exe scripts\standardize_names.py
    .venv\Scripts\python.exe scripts\standardize_names.py --dry-run
"""

import sys
from pathlib import Path

# 英文/ASCII 名 → 中文正确名
EN_TO_CN = {
    "00_environment_setup": "00_第0天_环境搭建手册",
    "01_sql_crash_course": "01_SQL热身5小时",
    "02_data_sources": "02_数据源获取双通道",
    "03_naming_convention": "03_目录结构与命名规范",
    "04_daily_checklist": "04_7天日清检查清单",
    "06_design_document": "06_数据仓库建设方案",
    "07_metabase_guide": "07_Metabase看板配置指南",
    "08_github_pages": "08_GitHubPages发布指南",
    "09_incremental_scd": "09_进阶补丁_增量模型与SCD",
    "10_kaggle_real_data": "10_Kaggle真实数据接入指南",
    "11_quality_issue_log": "11_数据质量问题台账",
    "12_data_model_spec": "12_数据模型设计说明书",
    "13_progress_review": "13_项目进度与问题复盘",
    "14_modeling_standards": "14_数仓建模规范",
    "15_qc_report": "15_交付件质量检查报告",
    "16_tech_stack_guide": "16_技术栈详解_DuckDB_dbt_Metabase",
    "17_multi_domain_extension": "17_多主题域扩展_支付评价卖家地理",
    "18_fix_record": "18_修正说明_record",
    "18b_fix_006": "18b_FIX-006_说明",
    "18c_fix_008": "18c_FIX-008_说明",
    "18d_fix_009": "18d_FIX-009_说明",
    "19_update_delivery_spec": "19_更新交付规范",
    "20_glossary_plain_language": "20_术语对照表_大白话解释",
    "21_release_qc_checklist": "21_发布质检清单",
    "22_kpi_catalog": "22_指标字典与数据资产目录",
    "23_business_view_of_code": "23_代码业务解读_从业务角度理解SQL",
}

# 27 份基准清单（用于缺失检查）
BASELINE = sorted(EN_TO_CN.values())

# 编号前缀 → 正确名（用于识别乱码副本）
CN_BY_PREFIX = {}
for cn in BASELINE:
    CN_BY_PREFIX[cn.split("_")[0]] = cn


def is_pure_ascii(s: str) -> bool:
    return s.isascii()


def main():
    dry = "--dry-run" in sys.argv
    docs = Path("docs")
    if not docs.exists():
        print("  [ERROR] 找不到 docs 目录，请在项目根执行")
        return 1

    print("=" * 68)
    print(" docs 文件名一键规范化")
    print("=" * 68)
    print(f" 目录: {docs.resolve()}")
    print(f" 模式: {'预览（不执行）' if dry else '执行'}")
    print()

    renamed = deleted = 0

    # ---- 第 1 步：英文/ASCII 名 → 中文名 ----
    print("【1】英文/ASCII 名 → 中文名")
    for f in sorted(docs.glob("*.md")):
        stem = f.stem
        if stem in EN_TO_CN:
            target = docs / f"{EN_TO_CN[stem]}.md"
            if target.exists():
                print(f"  ⚠ 已存在中文版，删除英文副本: {f.name}")
                if not dry:
                    f.unlink()
                    deleted += 1
                continue
            print(f"  ✓ {f.name}")
            print(f"    → {target.name}")
            if not dry:
                f.rename(target)
                renamed += 1
    if renamed == 0 and deleted == 0:
        print("  （无需处理）")

    # ---- 第 2 步：清理乱码副本 ----
    print()
    print("【2】清理乱码副本（保留正确名）")
    d2 = 0
    for f in sorted(docs.glob("*.md")):
        stem = f.stem
        if is_pure_ascii(stem):
            continue  # 纯 ASCII 且不在映射表 → 可能是自定义文件，不动
        prefix = stem.split("_")[0]
        correct = CN_BY_PREFIX.get(prefix)
        if correct and f.name != f"{correct}.md":
            has_correct = (docs / f"{correct}.md").exists()
            if has_correct:
                print(f"  ✓ 删除乱码副本: {f.name}")
                if not dry:
                    f.unlink()
                    d2 += 1
    deleted += d2
    if d2 == 0:
        print("  （无需处理）")

    # ---- 第 3 步：缺失检查 ----
    print()
    print("【3】缺失检查（对照 27 份基准）")
    have = {f.stem for f in docs.glob("*.md")}
    missing = [c for c in BASELINE if c not in have]
    if missing:
        for m in missing:
            print(f"  ⚠ 缺失: {m}.md")
    else:
        print("  ✓ 27 份齐全")
    extra = sorted(have - set(BASELINE))
    if extra:
        print()
        print("  另有非基准文件（可能是你的自定义文档，未处理）:")
        for e in extra:
            print(f"    - {e}.md")

    print()
    print("=" * 68)
    print(f" 完成：重命名 {renamed} 个，删除 {deleted} 个，缺失 {len(missing)} 份")
    print("=" * 68)
    if dry:
        print("\n 预览模式。实际执行：")
        print("   .venv\\Scripts\\python.exe scripts\\standardize_names.py")
    else:
        print("\n 验证：")
        print("   dir docs\\*.md")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
