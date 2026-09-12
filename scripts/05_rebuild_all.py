# -*- coding: utf-8 -*-
"""
============================================================
脚本 05：一键重跑全流程（造数 → 装载 → 构建 → 测试）
------------------------------------------------------------
用途：数据或模型改动后，一条命令走完全流程，避免漏步骤。

运行：python scripts/05_rebuild_all.py
============================================================
"""
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable
DBT = ROOT / ".venv" / "Scripts" / "dbt.exe"

STEPS = [
    ("生成数据", [PY, "scripts/02_generate_synthetic_data.py"]),
    ("装载入库", [PY, "scripts/03_load_raw.py"]),
    ("构建模型", [str(DBT), "run"]),
    ("质量断言", [str(DBT), "test"]),
]

print("=" * 60)
print("一键重跑全流程")
print("=" * 60)

for name, cmd in STEPS:
    print(f"\n>>> {name} ...")
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        print(f"\n✗ 「{name}」失败，已停止。请修复后重跑。")
        sys.exit(1)
    print(f"✓ {name} 完成")

print("\n" + "=" * 60)
print("全部完成！下一步：")
print("  .venv\\Scripts\\dbt.exe docs generate")
print("  .venv\\Scripts\\dbt.exe docs serve")
print("=" * 60)
