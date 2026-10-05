param([switch]$SkipChecks, [switch]$RestartServices)
$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-processes.ps1')
$pythonPath = Join-Path $workspacePath 'apps/api/.venv/Scripts/python.exe'
Set-Location -LiteralPath $workspacePath
& $pythonPath scripts/local_runtime.py prepare
if ($LASTEXITCODE -ne 0) { throw 'Local configuration failed' }
docker compose --env-file .local/services.env -f infra/docker-compose.local.yml up -d --wait
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL/Redis startup failed' }
$launcherPath = Join-Path $workspacePath 'scripts/local_runtime.py'
$processes = @{}
$storedProcesses = $null
if (Test-Path -LiteralPath "$workspacePath/.local/processes.json") {
  $storedProcesses = Get-Content -LiteralPath "$workspacePath/.local/processes.json" | ConvertFrom-Json
}
if ($RestartServices -and $storedProcesses) {
  foreach ($serviceName in @('api', 'cleanup', 'web')) {
    if ($storedProcesses.$serviceName) {
      Stop-DresslyProcessTree -ProcessId $storedProcesses.$serviceName -WorkspacePath $workspacePath
      $storedProcesses.$serviceName = $null
    }
  }
  $storedProcesses | ConvertTo-Json | Set-Content -LiteralPath "$workspacePath/.local/processes.json"
}
foreach ($serviceName in @('minio')) {
  try {
    $null = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:19000/minio/health/live'
    if (Test-Path -LiteralPath "$workspacePath/.local/processes.json") {
      $storedProcesses = Get-Content -LiteralPath "$workspacePath/.local/processes.json" | ConvertFrom-Json
      if ($storedProcesses.minio) { $processes['minio'] = $storedProcesses.minio; continue }
    }
    throw 'Port 19000 is occupied by an unmanaged service'
  } catch [System.Net.WebException] { }
  $process = Start-Process -FilePath $pythonPath -ArgumentList @($launcherPath, $serviceName) -WorkingDirectory $workspacePath -WindowStyle Hidden -PassThru -RedirectStandardOutput "$workspacePath/.local/$serviceName.log" -RedirectStandardError "$workspacePath/.local/$serviceName.error.log"
  $processes[$serviceName] = $process.Id
  $processes | ConvertTo-Json | Set-Content -LiteralPath "$workspacePath/.local/processes.json"
}
$storageReady = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
  try { $null = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:19000/minio/health/live'; $storageReady = $true; break } catch { Start-Sleep -Seconds 1 }
}
if (-not $storageReady) { throw 'MinIO failed to start; consult .local/minio.error.log' }
& $pythonPath scripts/local_runtime.py migrate
if ($LASTEXITCODE -ne 0) { throw 'Database migration failed' }
& $pythonPath scripts/local_runtime.py bootstrap
if ($LASTEXITCODE -ne 0) { throw 'Private media bootstrap failed' }
foreach ($serviceName in @('api', 'cleanup')) {
  $storedId = if ($storedProcesses) { $storedProcesses.$serviceName } else { $null }
  $storedProcess = if ($storedId) { Get-CimInstance Win32_Process -Filter "ProcessId=$storedId" -ErrorAction SilentlyContinue } else { $null }
  if ($storedProcess -and $storedProcess.CommandLine -like "*$workspacePath*local_runtime.py*$serviceName*") {
    $processes[$serviceName] = $storedId
    continue
  }
  $process = Start-Process -FilePath $pythonPath -ArgumentList @($launcherPath, $serviceName) -WorkingDirectory $workspacePath -WindowStyle Hidden -PassThru -RedirectStandardOutput "$workspacePath/.local/$serviceName.log" -RedirectStandardError "$workspacePath/.local/$serviceName.error.log"
  $processes[$serviceName] = $process.Id
  $processes | ConvertTo-Json | Set-Content -LiteralPath "$workspacePath/.local/processes.json"
}
Set-Location -LiteralPath (Join-Path $workspacePath 'apps/mobile')
if (-not $SkipChecks) {
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
}
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:18000/api/v1 --dart-define=ENVIRONMENT=development
if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
$storedWebId = if ($storedProcesses) { $storedProcesses.web } else { $null }
$existingWeb = if ($storedWebId) { Get-CimInstance Win32_Process -Filter "ProcessId = $storedWebId" } else { $null }
if ($existingWeb -and $existingWeb.CommandLine -like "*$workspacePath*" -and $existingWeb.CommandLine -like '*http.server*') {
  $processes['web'] = $storedWebId
} else {
  $webProcess = Start-Process -FilePath $pythonPath -ArgumentList @('-m', 'http.server', '18080', '--bind', '127.0.0.1', '--directory', "$workspacePath/apps/mobile/build/web") -WorkingDirectory $workspacePath -WindowStyle Hidden -PassThru -RedirectStandardOutput "$workspacePath/.local/web.log" -RedirectStandardError "$workspacePath/.local/web.error.log"
  $processes['web'] = $webProcess.Id
}
$processes | ConvertTo-Json | Set-Content -LiteralPath "$workspacePath/.local/processes.json"
$apiReady = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
  try { $null = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18000/readiness'; $apiReady = $true; break } catch { Start-Sleep -Seconds 1 }
}
if (-not $apiReady) { throw 'API not ready; consult .local/api.error.log' }
Write-Host 'Dressly: http://127.0.0.1:18080'
Write-Host 'API: http://127.0.0.1:18000/health'
