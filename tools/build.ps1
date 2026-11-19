param([switch]$UpdatePreview)

. (Join-Path $PSScriptRoot 'environment.ps1')
if (-not (Get-Command $godot -ErrorAction SilentlyContinue)) {
    throw 'Godot 4.7.2 was not found. Set GODOT_BIN to its executable or put godot on PATH.'
}
if ($env:GODOT_WEB_TEMPLATE) {
    $templateSource = Get-Item -LiteralPath $env:GODOT_WEB_TEMPLATE
    if ($templateSource.PSIsContainer -or $templateSource.Name -ne 'web_nothreads_release.zip') {
        throw 'GODOT_WEB_TEMPLATE must point to the Godot 4.7.2 web_nothreads_release.zip.'
    }
    $templateDirectory = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable'
    New-Item -ItemType Directory -Force -Path $templateDirectory | Out-Null
    $templateTarget = Join-Path $templateDirectory $templateSource.Name
    if ($templateSource.FullName -ne $templateTarget) {
        Copy-Item -LiteralPath $templateSource.FullName -Destination $templateTarget -Force
    }
}
New-Item -ItemType Directory -Force -Path 'build\web','dist' | Out-Null
& $godot --headless --editor --path $projectRoot --import 2>&1 | Tee-Object -FilePath '.runtime\import.log'
if ($LASTEXITCODE -ne 0 -or (Select-String -Path '.runtime\import.log' -Pattern 'SCRIPT ERROR|Parse Error')) { throw 'Godot import failed' }
& $godot --headless --path $projectRoot --export-release Web 'build/web/index.html' 2>&1 | Tee-Object -FilePath '.runtime\export.log'
if ($LASTEXITCODE -ne 0 -or (Select-String -Path '.runtime\export.log' -Pattern 'SCRIPT ERROR|Parse Error|Export failed')) { throw 'Godot export failed' }
& node 'tools/prepare_web.cjs'
if ($LASTEXITCODE -ne 0) { throw 'Web preparation failed' }
Copy-Item 'assets\fonts\FONT-LICENSE.txt' 'build\web\FONT-LICENSE.txt' -Force
Copy-Item 'docs\GODOT-LICENSE.txt' 'build\web\GODOT-LICENSE.txt' -Force
Copy-Item 'docs\比赛提交说明.txt' 'build\web\README.txt' -Force
$files = Get-ChildItem -LiteralPath 'build\web' -File
$total = ($files | Measure-Object -Property Length -Sum).Sum
if ($total -ge 200000000) { throw 'Uncompressed package must be less than 200 MB' }
Compress-Archive -Path 'build\web\*' -DestinationPath 'dist\MeowBeat-Web.zip' -Force -CompressionLevel Optimal
$zipBytes = (Get-Item 'dist\MeowBeat-Web.zip').Length
if ($zipBytes -ge 200000000) { throw 'ZIP must be less than 200 MB' }
[ordered]@{game='商场拆迁王';engine='Godot 4.7.2';entry='index.html';web_bytes=$total;zip_bytes=$zipBytes;limit_bytes=200000000;files=@($files | ForEach-Object { @{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })} | ConvertTo-Json -Depth 5 | Set-Content 'dist\manifest.json' -Encoding UTF8
Write-Output ('Web {0:N2} MB / ZIP {1:N2} MB' -f ($total/1000000),($zipBytes/1000000))
if ($UpdatePreview) {
    $previewPath = Join-Path $projectRoot 'preview'
    New-Item -ItemType Directory -Force -Path $previewPath | Out-Null
    foreach ($webFile in $files) {
        Copy-Item -LiteralPath $webFile.FullName -Destination $previewPath -Force
    }
    Write-Output 'Updated the checked-in browser preview.'
}
