# ================================
# JTech Panel Installer (Windows)
# ================================

# 🔥 Relaunch jika dari CMD
if (-not $PSVersionTable) {
    Write-Host "Re-launching in PowerShell..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File "%~f0"
    exit
}

# 🔒 TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " JTech Panel Installer" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# ⚠️ Confirm
$confirm = Read-Host "Do you want to continue installation? (y/n)"
if ($confirm -ne "y") {
    Write-Host "Installation cancelled."
    exit
}

# ================================
# 🔍 CHECK CLOUDLFARED
# ================================

$cloudflaredPath = "$env:ProgramFiles\cloudflared\cloudflared.exe"

if (-not (Test-Path $cloudflaredPath)) {
    Write-Host "❌ cloudflared not found!" -ForegroundColor Red
    Write-Host "Please install cloudflared first:" -ForegroundColor Yellow
    Write-Host "https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/" -ForegroundColor Cyan
    exit 1
}

Write-Host "✅ cloudflared found at: $cloudflaredPath" -ForegroundColor Green

# ================================
# 🔍 CHECK SERVICE
# ================================

$serviceName = "cloudflared"

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    Write-Host "⚠️ Service 'cloudflared' already exists (Status: $($service.Status))" -ForegroundColor Yellow

    $choice = Read-Host "Do you want to reinstall service? (y/n)"
    if ($choice -ne "y") {
        Write-Host "Skipping service installation..."
        exit
    }

    # stop & delete existing service
    Write-Host "Removing existing service..." -ForegroundColor Yellow
    sc.exe stop $serviceName | Out-Null
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
}

# ================================
# 🚀 INSTALL SERVICE
# ================================

try {
    Write-Host "Installing cloudflared service..." -ForegroundColor Cyan

    & $cloudflaredPath service install

    if ($LASTEXITCODE -ne 0) {
        throw "Service installation failed"
    }

    Write-Host "✅ Service installed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to install service" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# ================================
# 🧠 DONE
# ================================

Write-Host "=====================================" -ForegroundColor Green
Write-Host " Installation Complete" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
