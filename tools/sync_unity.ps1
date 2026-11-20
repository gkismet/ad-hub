# 把 ad-hub 的 Unity 模块同步到某个 Unity 项目（覆盖 Assets/AdHub/）
# 用法：powershell -ExecutionPolicy Bypass -File tools\sync_unity.ps1 -Project D:\Games\MyGame
param([Parameter(Mandatory = $true)][string]$Project)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot '..\unity\Assets\AdHub' | Resolve-Path
if (-not (Test-Path (Join-Path $Project 'ProjectSettings\ProjectVersion.txt'))) {
    throw "$Project 不是 Unity 项目根目录（找不到 ProjectSettings\ProjectVersion.txt）"
}
$dst = Join-Path $Project 'Assets\AdHub'
$old = if (Test-Path "$dst\VERSION") { (Get-Content "$dst\VERSION" -Raw).Trim() } else { '无' }
$new = (Get-Content "$src\VERSION" -Raw).Trim()

New-Item -ItemType Directory -Force $dst | Out-Null
# 只删 .cs 和 VERSION，保留 Unity 生成的 .meta，避免 GUID 变化
Get-ChildItem $dst -File | Where-Object { $_.Extension -ne '.meta' } | Remove-Item -Force
Copy-Item "$src\*" $dst -Force
Write-Host "AdHub: $old -> $new  已同步到 $dst"

$bundled = Join-Path $Project 'Assets\Resources\adhub_config.json'
if (-not (Test-Path $bundled)) {
    Write-Warning "缺少广告配置：运行 tools\sync_config.ps1 -App <app> -Project $Project"
}
