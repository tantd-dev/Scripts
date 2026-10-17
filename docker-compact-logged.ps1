            if (Get-Command Get-VHD -ErrorAction SilentlyContinue) {
                try {
                    $vhd = Get-VHD -Path $VhdxPath -ErrorAction Stop
                    $vhdxFileSizeGiB = [math]::Round($vhd.FileSize / 1GB, 3)
                    $vhdxVirtualSizeGiB = [math]::Round($vhd.Size / 1GB, 3)
                } catch {
                    $snapshotError = "Get-VHD unavailable/failed: $($_.Exception.Message)"
                }
            } else {
                $snapshotError = "Get-VHD cmdlet unavailable; allocated/virtual size not recorded."
            }
        } else {
            $snapshotError = "VHDX not found: $VhdxPath"
        }

        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $cFreeGiB = [math]::Round($drive.Free / 1GB, 3)
    } catch {
        $snapshotError = ($snapshotError, $_.Exception.Message | Where-Object { $_ }) -join " | "
    }

    [pscustomobject]@{
        VhdxLogicalGiB    = $vhdxLogicalGiB
        VhdxAllocatedGiB  = $vhdxFileSizeGiB
        VhdxVirtualGiB    = $vhdxVirtualSizeGiB
        VhdxLastWriteTime = $vhdxLastWriteTime
        CFreeGiB          = $cFreeGiB
        SnapshotError     = $snapshotError
    }
}

$runStarted = Get-Date
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$status = "Failed"
$errorMessage = ""
$exitCode = $null
$before = $null
$after = $null
$stdoutPath = Join-Path $env:TEMP "docker-compact-$timestamp-stdout.txt"
$stderrPath = Join-Path $env:TEMP "docker-compact-$timestamp-stderr.txt"

$path = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"

Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "`r`n===== START $($runStarted.ToString('yyyy-MM-dd HH:mm:ss')) ====="
Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "Wrapper: $PSCommandPath"
Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "Target script: $scriptPath"
Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

try {
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Cannot find target script: $scriptPath"
    }

    $before = Get-DiskSnapshot -VhdxPath $path
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value ("BEFORE: " + ($before | ConvertTo-Json -Compress))

    # Run the existing compact script as a child PowerShell process and capture its output.
    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"") `
        -PassThru `
        -Wait `
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
        $errorMessage = "Compact script exited with code $exitCode"
    }
} catch {
    $status = "Failed"
    $errorMessage = $_.Exception.Message
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "ERROR: $errorMessage"
} finally {
    # Take a final snapshot even when the target script fails.
    $after = Get-DiskSnapshot -VhdxPath $path
    $stopwatch.Stop()
    $runEnded = Get-Date

    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value ("AFTER: " + ($after | ConvertTo-Json -Compress))
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "Status: $status; ExitCode: $exitCode; DurationSeconds: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)); Error: $errorMessage"
    Add-Content -LiteralPath $txtPath -Encoding UTF8 -Value "===== END $($runEnded.ToString('yyyy-MM-dd HH:mm:ss')) ====="

    $row = [pscustomobject]@{
        StartTime           = $runStarted.ToString("yyyy-MM-dd HH:mm:ss")
        EndTime             = $runEnded.ToString("yyyy-MM-dd HH:mm:ss")
        DurationSeconds     = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        Status              = $status
        ExitCode            = $exitCode
        VhdxPath            = $path
        VhdxLogicalBeforeGiB = $before.VhdxLogicalGiB
        VhdxLogicalAfterGiB  = $after.VhdxLogicalGiB
        VhdxLogicalDeltaGiB  = if ($null -ne $before.VhdxLogicalGiB -and $null -ne $after.VhdxLogicalGiB) { [math]::Round($after.VhdxLogicalGiB - $before.VhdxLogicalGiB, 3) } else { $null }
        VhdxAllocatedBeforeGiB = $before.VhdxAllocatedGiB
        VhdxAllocatedAfterGiB  = $after.VhdxAllocatedGiB
        VhdxAllocatedDeltaGiB  = if ($null -ne $before.VhdxAllocatedGiB -and $null -ne $after.VhdxAllocatedGiB) { [math]::Round($after.VhdxAllocatedGiB - $before.VhdxAllocatedGiB, 3) } else { $null }
        VhdxVirtualBeforeGiB = $before.VhdxVirtualGiB
        VhdxVirtualAfterGiB  = $after.VhdxVirtualGiB
        CFreeBeforeGiB       = $before.CFreeGiB
        CFreeAfterGiB        = $after.CFreeGiB
        CFreeDeltaGiB        = if ($null -ne $before.CFreeGiB -and $null -ne $after.CFreeGiB) { [math]::Round($after.CFreeGiB - $before.CFreeGiB, 3) } else { $null }
        Error                = $errorMessage
        BeforeSnapshotError  = $before.SnapshotError
        AfterSnapshotError   = $after.SnapshotError
    }

    if (Test-Path -LiteralPath $csvPath) {
        $row | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
    } else {
        $row | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    }

    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
}

if ($status -ne "Success") {
    exit 1
}