#Requires -Version 5.1
<#
.SYNOPSIS
    一键应用补丁包：解压并覆盖到项目目录

.DESCRIPTION
    用于快速应用增量补丁。相比解压完整包后手工复制，
    本脚本自动处理目录层级探测与镜像覆盖，并列出被覆盖的文件。

.PARAMETER PatchZip
    补丁压缩包路径

.PARAMETER TargetDir
    目标项目根目录，默认为当前目录

.PARAMETER WhatIf
    预览模式：只显示将要覆盖哪些文件，不实际执行

.EXAMPLE
    .\scripts\apply_patch.ps1 -PatchZip patch.zip

.EXAMPLE
    .\scripts\apply_patch.ps1 -PatchZip patch.zip -WhatIf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PatchZip,

    [string]$TargetDir = (Get-Location).Path,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ---------- 0. 前置检查 ----------
if (-not (Test-Path $PatchZip)) {
    Write-Host "  [ERROR] 找不到补丁包：$PatchZip" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $TargetDir)) {
    Write-Host "  [ERROR] 目标目录不存在：$TargetDir" -ForegroundColor Red
    exit 1
}

# 校验目标是项目根（必须含 dbt_project.yml）
if (-not (Test-Path (Join-Path $TargetDir "dbt_project.yml"))) {
    Write-Host "  [WARN] 目标目录下没有 dbt_project.yml" -ForegroundColor Yellow
    Write-Host "        确认这是项目根目录吗？" -ForegroundColor Yellow
    $ans = Read-Host "  继续？(y/N)"
    if ($ans -ne "y") { Write-Host "  已取消"; exit 0 }
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host " 补丁应用工具" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "  补丁包  : $PatchZip"
Write-Host "  目标目录: $TargetDir"
if ($WhatIf) { Write-Host "  模式    : 预览（不实际覆盖）" -ForegroundColor Yellow }
Write-Host ""

# ---------- 1. 解压到临时目录 ----------
$temp = Join-Path $env:TEMP ("patch_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    Write-Host "  [1/4] 解压中..." -ForegroundColor Gray
    Expand-Archive -Path $PatchZip -DestinationPath $temp -Force

    # ---------- 2. 探测并剥离顶层目录 ----------
    # 压缩包可能带 olist-dw/ 前缀，也可能直接是 models/ scripts/
    $src = $temp
    $children = Get-ChildItem $temp

    # 若只有一个子目录，且该目录下含 models 或 docs，则认定为顶层目录
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        $inner = $children[0].FullName
        $innerChildren = Get-ChildItem $inner -Name
        if ($innerChildren -contains "models" -or $innerChildren -contains "docs") {
            $src = $inner
            Write-Host "  [2/4] 已自动剥离顶层目录: $($children[0].Name)" -ForegroundColor Gray
        }
        else {
            Write-Host "  [2/4] 目录结构无需调整" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  [2/4] 目录结构无需调整" -ForegroundColor Gray
    }

    # ---------- 3. 汇总待覆盖文件 ----------
    $files = Get-ChildItem $src -Recurse -File
    Write-Host "  [3/4] 待覆盖文件: $($files.Count) 个" -ForegroundColor Gray
    Write-Host ""
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($src.Length + 1)
        Write-Host "        - $rel"
    }
    Write-Host ""

    if ($WhatIf) {
        Write-Host "  预览模式，未执行覆盖。" -ForegroundColor Yellow
        exit 0
    }

    # ---------- 4. 执行覆盖 ----------
    Write-Host "  [4/4] 覆盖中..." -ForegroundColor Gray
    $copied = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($src.Length + 1)
        $dest = Join-Path $TargetDir $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $copied++
    }

    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Host " 完成：已覆盖 $copied 个文件" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Host ""
    Write-Host " 下一步建议：" -ForegroundColor Cyan
    Write-Host "   .\.venv\Scripts\dbt.exe run"
    Write-Host "   .\.venv\Scripts\dbt.exe test"
    Write-Host ""
}
finally {
    # ---------- 清理临时目录 ----------
    if (Test-Path $temp) {
        Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
