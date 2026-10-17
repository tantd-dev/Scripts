[CmdletBinding()]
param(
    # Only prune Docker objects when explicitly requested.
    [switch]$Prune
)

$ErrorActionPreference = "Stop"

$vhd = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"
$dockerExe = Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\Docker Desktop.exe"

$restartDocker = $false
$compactSucceeded = $false

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-DiskPart {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Commands,

        [switch]$AllowAlreadyDetached
    )

    $scriptFile = New-TemporaryFile

    try {
        $Commands | Set-Content -LiteralPath $scriptFile -Encoding ASCII

        $output = @(
            & diskpart.exe /s $scriptFile 2>&1 |
                ForEach-Object { "$_" }
        )

        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $output | ForEach-Object { Write-Host $_ }

        # DiskPart can return a non-zero code when detaching an
        # already-detached VHDX. Accept only this specific condition
        # when the caller explicitly allows it.
        if (
            $AllowAlreadyDetached -and
            $text -match "(?i)already detached"
        ) {
            return ,$output
        }

        if ($exitCode -ne 0) {
            throw "DiskPart exited with code $exitCode."
        }

        return ,$output
    }
    finally {
        Remove-Item -LiteralPath $scriptFile `
            -Force -ErrorAction SilentlyContinue
    }
}

function Detach-DockerVhdx {
    $output = Invoke-DiskPart `
        -Commands @(
            "select vdisk file=`"$vhd`"",
            "detach vdisk",
            "exit"
        ) `
        -AllowAlreadyDetached

    $text = $output -join "`n"

    if ($text -match "(?i)successfully detached the virtual disk file") {
        Write-Host "VHDX detached successfully." -ForegroundColor Green
        return
    }

    if ($text -match "(?i)already detached") {
        Write-Host "VHDX is already detached; continuing." -ForegroundColor DarkGray
        return
    }

    throw "Could not confirm that the VHDX was detached. Stopping for safety."
}

if (-not (Test-IsAdministrator)) {
    throw "Please run PowerShell as Administrator."
}

if (-not (Test-Path -LiteralPath $vhd -PathType Leaf)) {
    throw "Docker VHDX not found: $vhd"
}

if (-not (Test-Path -LiteralPath $dockerExe -PathType Leaf)) {
    throw "Docker Desktop executable not found: $dockerExe"
}

try {
    # 1. Optional cleanup.
    # Never prune unless -Prune was explicitly supplied.
    if ($Prune) {
        Write-Host "Checking Docker Engine..."

        & docker.exe info *> $null

        if ($LASTEXITCODE -ne 0) {
            throw "Docker Engine is unavailable. Prune and compaction cancelled."
        }

        Write-Host "Pruning unused Docker objects..."

        & docker.exe system prune -f

        if ($LASTEXITCODE -ne 0) {
            throw "docker system prune failed. Compaction cancelled."
        }

        & docker.exe builder prune -f

        if ($LASTEXITCODE -ne 0) {
            throw "docker builder prune failed. Compaction cancelled."
        }
    }

    # 2. Close Docker Desktop gracefully first.
    Write-Host "Closing Docker Desktop..."

    $restartDocker = $true

    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue |
        ForEach-Object {
            [void]$_.CloseMainWindow()
        }

    $deadline = (Get-Date).AddSeconds(30)

    while (
        (Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue) -and
        (Get-Date) -lt $deadline
    ) {
        Start-Sleep -Seconds 2
    }

    # Force-close the Desktop UI only if it has not exited.
    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    # 3. Shut down WSL.
    Write-Host "Shutting down WSL..."

    & wsl.exe --shutdown

    if ($LASTEXITCODE -ne 0) {
        throw "wsl --shutdown failed. Compaction cancelled."
    }

    Start-Sleep -Seconds 5

    # 4. Release a stale VHDX attachment, if one exists.
    # This is important because the previous failure was a sharing violation.
    Write-Host "Checking for a stale VHDX attachment..."

    Detach-DockerVhdx

    Start-Sleep -Seconds 2

    # 5. Attach the VHDX.
    Write-Host "Attaching Docker VHDX..."

    $attachOutput = Invoke-DiskPart @(
        "select vdisk file=`"$vhd`"",
        "attach vdisk readonly",
        "exit"
    )

    if (
        ($attachOutput -join "`n") -notmatch
        "(?i)successfully attached the virtual disk file"
    ) {
        throw "DiskPart did not confirm attachment. Compact was not attempted."
    }

    # 6. Compact the VHDX.
    Write-Host "Compacting Docker VHDX..."

    $compactOutput = Invoke-DiskPart @(
        "select vdisk file=`"$vhd`"",
        "compact vdisk",
        "exit"
    )

    if (
        ($compactOutput -join "`n") -notmatch
        "(?i)successfully compacted the virtual disk file"
    ) {
        throw "DiskPart did not confirm successful compaction."
    }

    # 7. Detach the VHDX before Docker starts again.
    Write-Host "Detaching Docker VHDX..."

    $detachOutput = Invoke-DiskPart @(
        "select vdisk file=`"$vhd`"",
        "detach vdisk",
        "exit"
    )

    if (
        ($detachOutput -join "`n") -notmatch
        "(?i)successfully detached the virtual disk file"
    ) {
        throw "Compaction may have succeeded, but VHDX detach was not confirmed."
    }

    $compactSucceeded = $true

    Write-Host ""
    Write-Host "Docker VHDX compacted and detached successfully." `
        -ForegroundColor Green
}
finally {
    # 8. On failure, try to detach the VHDX before restarting Docker.
    # Never delete, reset, unregister, or reformat the VHDX.
    if ($restartDocker -and -not $compactSucceeded) {
        try {
            Write-Host "Attempting VHDX cleanup after failure..."

            Detach-DockerVhdx
        }
        catch {
            Write-Warning (
                "Could not confirm VHDX detach. Check DiskPart output " +
                "before retrying. $($_.Exception.Message)"
            )
        }
    }

    # 9. Always attempt to restart Docker if shutdown was initiated.
    if ($restartDocker) {
        try {
            Write-Host "Starting Docker Desktop..."

            Start-Process -FilePath $dockerExe
        }
        catch {
            Write-Warning "Could not start Docker Desktop: $($_.Exception.Message)"
        }
    }
}

if (-not $compactSucceeded) {
    throw "Docker VHDX compaction did not complete successfully."
}