$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-processes.ps1')
$receiptPath = Join-Path $workspacePath '.local/processes.json'
if (Test-Path -LiteralPath $receiptPath) {
  $processes = Get-Content -LiteralPath $receiptPath | ConvertFrom-Json
  foreach ($entry in $processes.PSObject.Properties) {
    $serviceProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($entry.Value)" -ErrorAction SilentlyContinue
    if ($serviceProcess -and $serviceProcess.CommandLine -like "*$workspacePath*") {
      Stop-DresslyProcessTree -ProcessId $entry.Value -WorkspacePath $workspacePath
    }
  }
}
Set-Location -LiteralPath $workspacePath
docker compose --env-file .local/services.env -f infra/docker-compose.local.yml stop
Write-Host 'Dressly local stopped. Database volumes and private files are preserved.'
