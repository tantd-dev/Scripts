
$vhd = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
$dockerExe = "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"

# 1. Dọn rác Docker (Docker phải đang chạy)
docker system prune -f 2>$null
docker builder prune -f 2>$null

# 2. Tắt Docker Desktop và WSL
Get-Process "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -Force
wsl --shutdown
Start-Sleep -Seconds 10

# 3. Compact VHDX bằng DiskPart
if (-not (Test-Path $vhd)) {
    throw "Không tìm thấy VHDX: $vhd"
}

$dp = New-TemporaryFile
@"
select vdisk file="$vhd"
attach vdisk
compact vdisk
detach vdisk
exit
"@ | Set-Content $dp -Encoding ASCII

try {
    diskpart /s $dp
}
finally {
    Remove-Item $dp -Force -ErrorAction SilentlyContinue
}

# 4. Khởi động lại Docker Desktop
if (Test-Path $dockerExe) {
    Start-Process -FilePath $dockerExe
}
else {
    throw "Không tìm thấy Docker Desktop: $dockerExe"
}
