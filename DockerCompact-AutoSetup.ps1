# DockerCompact-AutoSetup.ps1
# Run this file ONCE in PowerShell as Administrator.
# It creates/updates the weekly task "DockerCompact".
# The task runs this same file with -RunTask and writes logs automatically.
# Dependency: C:\Scripts\docker-compact.ps1 (the existing compaction script).

param(
    [switch]$RunTask
)

$ErrorActionPreference = "Stop"

$taskName   = "DockerCompact"
$installPath = "C:\Scripts\DockerCompact-AutoSetup.ps1"
$compactPath = "C:\Scripts\docker-compact.ps1"
$logDir     = "C:\Scripts\logs"
$csvPath    = Join-Path $logDir "docker-compact-history.csv"
$txtPath    = Join-Path $logDir "docker-compact.log"
$vhdxPath   = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DiskSnapshot {
    param([string]$Path)

    $logical = $null
    $allocated = $null
    $virtual = $null
    $lastWrite = $null
    $free = $null
    $err = $null

    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $item = Get-Item -LiteralPath $Path
            $logical = [math]::Round($item.Length / 1GB, 3)
            $lastWrite = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if (Get-Command Get-VHD -ErrorAction SilentlyContinue) {
                try {
                    $vhd = Get-VHD -Path $Path -ErrorAction Stop
                    $allocated = [math]::Round($vhd.FileSize / 1GB, 3)
                    $virtual = [math]::Round($vhd.Size / 1GB, 3)
                } catch {
                    $err = "Get-VHD failed: $($_.Exception.Message)"
                }
            } else {
                $err = "Get-VHD unavailable; allocated/virtual size not recorded."
            }
        } else {
            $err = "VHDX not found: $Path"
        }
        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $free = [math]::Round($drive.Free / 1GB, 3)
    } catch {
        $err = (@($err, $_.Exception.Message) | Where-Object { $_ }) -join " | "
    }

    [pscustomobject]@{
        VhdxLogicalGiB = $logical
        VhdxAllocatedGiB = $allocated
        VhdxVirtualGiB = $virtual
        VhdxLastWriteTime = $lastWrite
        CFreeGiB = $free
        SnapshotError = $err
    }
}

if (-not $RunTask) {
    # INSTALL / REGISTER MODE
    if (-not (Test-IsAdministrator)) {
        Write-Host "Please right-click PowerShell and choose 'Run as administrator', then run this file again." -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path -LiteralPath $compactPath -PathType Leaf)) {
        throw "Cannot find the existing compaction script: $compactPath`nKeep that script in place; this installer adds scheduling and logging around it."
    }

    if (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) {
        # Allow running this file from another location, but require it to be copied to the stable task path.
        throw "Copy this file to $installPath first, then run it from that location."
    }

    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$installPath`" -RunTask"

    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "3:00AM"
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal `
        -UserId $currentUser `
        -LogonType Interactive `
        -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 3)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Weekly Docker WSL disk compaction with automatic logging" `
        -Force | Out-Null

    Write-Host ""
    Write-Host "Task '$taskName' created/updated successfully." -ForegroundColor Green
    Write-Host "Schedule: Every Sunday at 03:00 AM (runs when available if missed)"
    Write-Host "Task script: $installPath -RunTask"
    Write-Host "Compaction script: $compactPath"
    Write-Host "Logs: $logDir"
    Write-Host ""
    Write-Host "To test later (this stops Docker/containers while compacting):" -ForegroundColor Yellow
    Write-Host 'Start-ScheduledTask -TaskName "DockerCompact"'
    Write-Host ""
    exit 0
}

# TASK / LOGGING MODE
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$started = Get-Date
$watch = [Diagnostics.Stopwatch]::StartNew()
$status = "Failed"
$exitCode = $null
$errorMessage = ""
$before = $null
$after = $null
$stamp = $started.ToString("yyyyMMdd-HHmmss")
$stdoutPath = Join-Path $env:TEMP "docker-compact-$stamp-stdout.txt"
$stderrPath = Join-Path $env:TEMP "docker-compact-$stamp-stderr.txt"

Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "`r`n===== START $($started.ToString('yyyy-MM-dd HH:mm:ss')) ====="
Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "Compaction script: $compactPath"

try {
    if (-not (Test-Path -LiteralPath $compactPath -PathType Leaf)) {
        throw "Cannot find compaction script: $compactPath"
    }

    $before = Get-DiskSnapshot -Path $vhdxPath
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value ("BEFORE: " + ($before | ConvertTo-Json -Compress))

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$compactPath`"") `
        -PassThru -Wait `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $exitCode = $process.ExitCode

    if (Test-Path -LiteralPath $stdoutPath) {
        Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "--- SCRIPT STDOUT ---"
        Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue |
            Add-Content -LiteralPath $txtPath -Encoding UTF8
    }
    if (Test-Path -LiteralPath $stderrPath) {
        $stderrText = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "--- SCRIPT STDERR ---"
            Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value $stderrText
        }
    }

    if ($exitCode -eq 0) {
        $status = "Success"
    } else {
        $status = "Failed"
        $errorMessage = "Compaction script exited with code $exitCode"
    }
} catch {
    $status = "Failed"
    $errorMessage = $_.Exception.Message
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "ERROR: $errorMessage"
} finally {
    $after = Get-DiskSnapshot -Path $vhdxPath
    $watch.Stop()
    $ended = Get-Date

    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value ("AFTER: " + ($after | ConvertTo-Json -Compress))
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "Status: $status; ExitCode: $exitCode; DurationSeconds: $([math]::Round($watch.Elapsed.TotalSeconds, 2)); Error: $errorMessage"
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "===== END $($ended.ToString('yyyy-MM-dd HH:mm:ss')) ====="

    $row = [pscustomobject]@{
        StartTime = $started.ToString("yyyy-MM-dd HH:mm:ss")
        EndTime = $ended.ToString("yyyy-MM-dd HH:mm:ss")
        DurationSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
        Status = $status
        ExitCode = $exitCode
        VhdxPath = $vhdxPath
        VhdxLogicalBeforeGiB = $before.VhdxLogicalGiB
        VhdxLogicalAfterGiB = $after.VhdxLogicalGiB
        VhdxLogicalDeltaGiB = if ($null -ne $before.VhdxLogicalGiB -and $null -ne $after.VhdxLogicalGiB) { [math]::Round($after.VhdxLogicalGiB - $before.VhdxLogicalGiB, 3) } else { $null }
        VhdxAllocatedBeforeGiB = $before.VhdxAllocatedGiB
        VhdxAllocatedAfterGiB = $after.VhdxAllocatedGiB
        VhdxAllocatedDeltaGiB = if ($null -ne $before.VhdxAllocatedGiB -and $null -ne $after.VhdxAllocatedGiB) { [math]::Round($after.VhdxAllocatedGiB - $before.VhdxAllocatedGiB, 3) } else { $null }
        VhdxVirtualBeforeGiB = $before.VhdxVirtualGiB
        VhdxVirtualAfterGiB = $after.VhdxVirtualGiB
        CFreeBeforeGiB = $before.CFreeGiB
        CFreeAfterGiB = $after.CFreeGiB
        CFreeDeltaGiB = if ($null -ne $before.CFreeGiB -and $null -ne $after.CFreeGiB) { [math]::Round($after.CFreeGiB - $before.CFreeGiB, 3) } else { $null }
        Error = $errorMessage
        BeforeSnapshotError = $before.SnapshotError
        AfterSnapshotError = $after.SnapshotError
    }

    if (Test-Path -LiteralPath $csvPath) {
        $row | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
    } else {
        $row | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    }
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
}

if ($status -ne "Success") { exit 1 }
exit 0
