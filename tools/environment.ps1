$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:APPDATA = Join-Path $projectRoot '.runtime\roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.runtime\local'
$env:TEMP = Join-Path $projectRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:npm_config_cache = Join-Path $projectRoot '.runtime\npm-cache'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $projectRoot '.runtime\playwright'
$env:PYTHONDONTWRITEBYTECODE = '1'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$env:TEMP | Out-Null
$godot = $env:GODOT_BIN
if (-not $godot) {
    $installedGodot = 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $installedGodot -PathType Leaf) {
        $godot = $installedGodot
    } else {
        $godot = 'godot'
    }
}
