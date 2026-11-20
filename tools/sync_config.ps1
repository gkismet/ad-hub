# 校验 ad-hub 里某个项目的广告配置，并拷进该项目（随包发布）。
#   Unity  项目 → Assets\Resources\adhub_config.json
#   Flutter 项目 → assets\adhub_config.json（pubspec 的 flutter.assets 里要声明）
# 用法：powershell -ExecutionPolicy Bypass -File tools\sync_config.ps1 -App my_app -Project D:\Games\MyGame
param(
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Project
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$src = Join-Path $root "config\apps\$App.json"
if (-not (Test-Path $src)) { throw "找不到 $src（先从 config\apps\_template.json 复制一份）" }

$env:PYTHONIOENCODING = 'utf-8'
python (Join-Path $root 'tools\validate_config.py') $src
if ($LASTEXITCODE -ne 0) { throw '配置校验没通过，未拷贝' }

if (Test-Path (Join-Path $Project 'ProjectSettings\ProjectVersion.txt')) {
    $dst = Join-Path $Project 'Assets\Resources\adhub_config.json'
} elseif (Test-Path (Join-Path $Project 'pubspec.yaml')) {
    $dst = Join-Path $Project 'assets\adhub_config.json'
    if (-not (Select-String -Path (Join-Path $Project 'pubspec.yaml') -Pattern 'adhub_config\.json' -Quiet)) {
        Write-Warning 'pubspec.yaml 的 flutter.assets 里还没声明 assets/adhub_config.json'
    }
} else {
    throw "$Project 既不是 Unity 项目也不是 Flutter 项目"
}

New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
Copy-Item $src $dst -Force
Write-Host "已拷贝 $App.json -> $dst"
Write-Host '注意：配置随包发布，改配置要重新出包才对玩家生效。'
