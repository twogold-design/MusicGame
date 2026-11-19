. (Join-Path $PSScriptRoot 'environment.ps1')
$browserCandidates = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
$browser = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browser) { throw 'Please install Chrome or Edge, then open index.html.' }
$profile = Join-Path $projectRoot '.runtime\player-browser'
$cache = Join-Path $projectRoot '.runtime\player-cache'
New-Item -ItemType Directory -Force -Path $profile,$cache | Out-Null
$entry = ([Uri](Join-Path $projectRoot 'index.html')).AbsoluteUri
Start-Process -FilePath $browser -ArgumentList @("--user-data-dir=`"$profile`"","--disk-cache-dir=`"$cache`"",'--no-first-run','--no-default-browser-check','--disable-crash-reporter','--disable-breakpad',"--app=$entry",'--window-size=1440,960') -WindowStyle Normal
