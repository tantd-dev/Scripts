$vhd = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"

# 1. Dọn rác trong Docker (khi Docker còn chạy)
docker system prune -f 2>$null
docker builder prune -f 2>$null

# 2. Tắt Docker Desktop và WSL
Get-Process "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -Force
wsl --shutdown
Start-Sleep -Seconds 10

# 3. Compact VHDX bằng diskpart
$dp = New-TemporaryFile
@"
select vdisk file="$vhd"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@ | Set-Content $dp -Encoding ASCII
diskpart /s $dp
Remove-Item $dp

# 4. Bật lại Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"