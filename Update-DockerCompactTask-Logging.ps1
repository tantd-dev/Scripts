# Update-DockerCompactTask-Logging.ps1
# Run in PowerShell as Administrator after placing docker-compact-logged.ps1 in C:\Scripts.

$ErrorActionPreference = "Stop"

$taskName = "DockerCompact"
$wrapperPath = "C:\Scripts\docker-compact-logged.ps1"

if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
    throw "Cannot find logging wrapper: $wrapperPath"
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""

Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null

Write-Host ""
Write-Host "Task '$taskName' now runs through the logging wrapper." -ForegroundColor Green
Write-Host "Wrapper: $wrapperPath"
Write-Host "CSV log: C:\Scripts\logs\docker-compact-history.csv"
Write-Host "Text log: C:\Scripts\logs\docker-compact.log"
Write-Host ""
Write-Host "Existing task trigger and principal were kept."
Read-Host "Press Enter to close"
