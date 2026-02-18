# JTech Panel - Windows Auto Installer
function install-connector {
    param([string]$token)

    if (-not $token) { 
        Write-Error "Token cluster lu mana Bre? Pake -token <TOKEN>"; return 
    }

    $installDir = "$env:ProgramFiles\cloudflared"
    $path = "$installDir\cloudflared.exe"

    # 1. Bikin folder sistem kalau belum ada
    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # 2. Cek apakah cloudflared sudah terinstall (Skip Download)
    if (Test-Path $path) {
        Write-Host "Cloudflared sudah ada, skip download. Langsung gass!" -ForegroundColor Yellow
    } else {
        Write-Host "Gass download cloudflared terbaru dari GitHub..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
        Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    }

    Write-Host "Memasang service JTech Connector..." -ForegroundColor Cyan
    
    # 3. Stop service lama kalau ada biar nggak bentrok
    if (Get-Service "cloudflared" -ErrorAction SilentlyContinue) {
        & $path service uninstall | Out-Null
    }

    # 4. Jalankan perintah install service
    & $path service install $token

    Write-Host "----------------------------------------" -ForegroundColor Green
    Write-Host "Mantap Bre! Connector sudah jalan di background."
}

# Jalankan fungsinya jika script ini dipanggil langsung
install-connector -token $token