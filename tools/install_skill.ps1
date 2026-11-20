# 把 gk-adhub skill 装到本机的 AI 编程工具里。两边用的是同一份 SKILL.md：
#   Claude Code → %USERPROFILE%\.claude\skills\gk-adhub
#   Codex       → %USERPROFILE%\.agents\skills\gk-adhub   （OpenAI 文档里的用户级 skill 目录）
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\install_skill.ps1                 # 自动：本机有哪个装哪个
#   powershell -ExecutionPolicy Bypass -File tools\install_skill.ps1 -Target codex   # 只装 Codex（claude / codex / all）
#   加 -Copy 改为复制（默认用目录联接 junction，git pull ad-hub 后自动更新）
param(
    [ValidateSet('auto', 'claude', 'codex', 'all')][string]$Target = 'auto',
    [switch]$Copy
)

$ErrorActionPreference = 'Stop'
$src = (Resolve-Path (Join-Path $PSScriptRoot '..\skill\gk-adhub')).Path
$homeDir = $env:USERPROFILE
$dirs = @{
    claude = Join-Path $homeDir '.claude\skills'
    codex  = Join-Path $homeDir '.agents\skills'
}

function Test-Tool($name) {
    switch ($name) {
        'claude' { return (Test-Path (Join-Path $homeDir '.claude')) -or [bool](Get-Command claude -ErrorAction SilentlyContinue) }
        'codex'  { return (Test-Path (Join-Path $homeDir '.codex')) -or [bool](Get-Command codex -ErrorAction SilentlyContinue) }
    }
}

$targets = switch ($Target) {
    'all'  { @('claude', 'codex') }
    'auto' { @('claude', 'codex') | Where-Object { Test-Tool $_ } }
    default { @($Target) }
}
if (-not $targets) {
    throw '没找到 Claude Code 或 Codex。用 -Target claude 或 -Target codex 指定要装到哪。'
}

foreach ($t in $targets) {
    $skills = $dirs[$t]
    $dst = Join-Path $skills 'gk-adhub'
    New-Item -ItemType Directory -Force $skills | Out-Null
    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        if ($item.LinkType) { $item.Delete() }          # 旧联接：只删联接本身
        else { Remove-Item $dst -Recurse -Force }       # 旧拷贝
    }
    if ($Copy) {
        Copy-Item $src $dst -Recurse
        Write-Host "[$t] 已复制 skill 到 $dst（更新需重新运行本脚本）"
    } else {
        New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
        Write-Host "[$t] 已联接 $dst -> $src（git pull 后自动生效）"
    }
}
Write-Host '重开 Claude Code / Codex 会话后生效。Codex 里看不到 gk-adhub 的话，用 -Copy 重装一次。'
