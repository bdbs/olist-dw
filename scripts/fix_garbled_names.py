# -*- coding: utf-8 -*-
"""
修复中文文件名乱码（Windows GBK 误读 UTF-8）

【成因】
    文件名原本是 UTF-8 编码，但解压工具按 GBK（中文Windows默认ANSI）读取，
    产生乱码。典型症状："说明" 显示为 "璇存槑"。

【修复原理】
    乱码字符串 --gbk编码--> 原始UTF-8字节 --utf8解码--> 正确文件名
    即：把误读过程反过来走一遍。

【两种修复方式】
    方式1 自动还原：GBK 往返转换（可完整还原）
    方式2 映射表  ：对于含 GBK 无法表示字节的文件（如含 0xa3），
                    往返转换会失败，改用已知正确名映射

【用法】
    .venv\Scripts\python.exe scripts\fix_garbled_names.py
    .venv\Scripts\python.exe scripts\fix_garbled_names.py --dry-run   # 预览不执行
"""

import sys
import os
from pathlib import Path

# 已知的正确文件名（自动还原失败时的兜底）
KNOWN_NAMES = {
    "18b_FIX-006": "18b_FIX-006_说明.md",
    "19": "19_更新交付规范.md",
    "21": "21_发布质检清单.md",
    "22": "22_指标字典与数据资产目录.md",
    "23": "23_代码业务解读_从业务角度理解SQL.md",
    "11": "11_数据质量问题台账.md",
    "12": "12_数据模型设计说明书.md",
    "13": "13_项目进度与问题复盘.md",
    "14": "14_数仓建模规范.md",
    "15": "15_交付件质量检查报告.md",
    "16": "16_技术栈详解_DuckDB_dbt_Metabase.md",
    "17": "17_多主题域扩展_支付评价卖家地理.md",
    "18": "18_修正说明_record.md",
    "20": "20_术语对照表_大白话解释.md",
}

# 扫描范围（可选 docs 与项目根）
SCAN_DIRS = ["docs", "."]


def try_recover(name: str):
    """尝试把乱码名还原为正确名，失败返回 None"""
    # 已经是纯 ASCII → 无需处理（可能是英文版，不动）
    if name.isascii():
        return None
    try:
        recovered = name.encode("gbk").decode("utf-8")
        if recovered != name:
            return recovered
    except Exception:
        pass
    return None


def try_known(name: str):
    """用编号前缀匹配已知正确名"""
    stem = Path(name).stem
    prefix = stem.split("_")[0]
    if prefix in KNOWN_NAMES:
        return KNOWN_NAMES[prefix]
    return None


def is_mojibake(name: str) -> bool:
    """判断是否为乱码名：非ASCII 且能/gbk往返成功，或能匹配已知前缀"""
    if name.isascii():
        return False
    return (try_recover(name) is not None) or (try_known(name) is not None)


def main():
    dry = "--dry-run" in sys.argv
    root = Path(".").resolve()
    print("=" * 66)
    print(" 中文文件名乱码修复工具")
    print("=" * 66)
    print(f" 扫描目录: {root}")
    print(f" 模式    : {'预览（不执行）' if dry else '执行修复'}")
    print()

    fixed, failed, skipped = 0, 0, 0

    for d in SCAN_DIRS:
        base = root / d
        if not base.exists():
            continue
        # 只扫描当前层，不递归（避免动到 data/）
        for f in sorted(base.glob("*.md")):
            name = f.name
            if name.isascii():
                # ASCII 名：可能是英文版文件，不动
                continue
            if not is_mojibake(name):
                continue

            target = try_recover(name) or try_known(name)
            if not target:
                failed += 1
                print(f"  ✗ 无法识别: {name}")
                continue

            # 目标已存在 → 说明是重复文件，删除乱码那个
            dst = base / target
            if dst.exists():
                print(f"  ⚠ 正确文件已存在，删除乱码副本")
                print(f"      {name}")
                if not dry:
                    try:
                        f.unlink()
                        fixed += 1
                    except Exception as e:
                        print(f"      ✗ 删除失败: {e}")
                        failed += 1
                continue

            print(f"  ✓ {name}")
            print(f"    → {target}")
            if not dry:
                try:
                    f.rename(dst)
                    fixed += 1
                except Exception as e:
                    print(f"    ✗ 失败: {e}")
                    failed += 1

    print()
    print("=" * 66)
    print(f" 完成：修复 {fixed} 个，失败 {failed} 个")
    print("=" * 66)
    if dry:
        print("\n 这是预览。实际执行请去掉 --dry-run：")
        print("   .venv\\Scripts\\python.exe scripts\\fix_garbled_names.py")
    else:
        print("\n 建议验证：")
        print("   dir docs\\*.md")
    print()


if __name__ == "__main__":
    main()
