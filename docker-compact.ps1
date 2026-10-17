```powershell
param(
    [switch]$Prune
)

$ErrorActionPreference = "Stop"

$vhd = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
$dockerExe = "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"

function Invoke-DiskPart {
    param([string[]]$Commands)

    $dp = New-TemporaryFile
    try {
        $Commands | Set-Content -LiteralPath $dp -Encoding ASCII
        $output = @(& diskpart.exe /s $dp 2>&1 | ForEach-Object { "$_" })
        $output | ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "DiskPart thất bại với exit code $LASTEXITCODE."
        }

        return $output
    }
    finally {
        Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $vhd)) {
    throw "Không tìm thấy VHDX: $vhd"
}

if (-not (Test-Path -LiteralPath $dockerExe)) {
    throw "Không tìm thấy Docker Desktop: $dockerExe"
}

# 1. Chỉ prune khi người chạy chủ động truyền -Prune
if ($Prune) {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Engine chưa sẵn sàng; bỏ qua prune."
    }

    docker system prune -f
    if ($LASTEXITCODE -ne 0) {
        throw "docker system prune thất bại."
    }

    docker builder prune -f
    if ($LASTEXITCODE -ne 0) {
        throw "docker builder prune thất bại."
    }
}

try {
    # 2. Đóng Docker Desktop
    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.CloseMainWindow() | Out-Null }

    Start-Sleep -Seconds 15

    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    # 3. Dừng WSL và đợi hệ thống giải phóng ổ
    wsl.exe --shutdown
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --shutdown thất bại."
    }

    Start-Sleep -Seconds 5

    # 4. Tháo VHDX nếu còn trạng thái attach cũ.
    # Lệnh detach có thể báo lỗi nếu ổ vốn đã detached; bỏ qua riêng bước này.
    $cleanup = Invoke-DiskPart @(
        "select vdisk file=`"$vhd`"",
        "detach vdisk",
        "exit"
    )

    Start-Sleep -Seconds 2

    # 5. Attach -> compact -> detach
    $result = Invoke-DiskPart @(
        "select vdisk file=`"$vhd`"",
        "attach vdisk",
        "compact vdisk",
        "detach vdisk",
        "exit"
    )

    $joined = $result -join "`n"

    if ($joined -match "(?i)error|failed|failure") {
        throw "DiskPart báo lỗi trong quá trình compact. Kiểm tra log ở trên."
    }

    if ($joined -notmatch "(?i)successfully compacted the virtual disk file") {
        throw "Không xác nhận được DiskPart đã compact thành công."
    }

    if ($joined -notmatch "(?i)successfully detached the virtual disk file") {
        throw "Compact có thể đã xong nhưng chưa xác nhận detach thành công. Cần kiểm tra trạng thái VHDX."
    }

    Write-Host "Compact VHDX thành công." -ForegroundColor Green
}
finally {
    # 6. Luôn thử khởi động lại Docker Desktop
    Start-Process -FilePath $dockerExe
}
```