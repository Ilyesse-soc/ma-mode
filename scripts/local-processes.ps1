function Stop-DresslyProcessTree {
  param([int]$ProcessId, [string]$WorkspacePath)
  $targetProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $targetProcess -or $targetProcess.CommandLine -notlike "*$WorkspacePath*") { return }
  foreach ($child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)) {
    Stop-DresslyProcessTree -ProcessId $child.ProcessId -WorkspacePath $WorkspacePath
  }
  Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
}
