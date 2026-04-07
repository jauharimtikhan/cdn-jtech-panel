# ================================
# JTech Panel Installer (Windows)
# ================================

# 🔥 Detect jika dijalankan dari CMD
if (-not $PSVersionTable) {
    Write-Host "Re-launching in PowerShell..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File "%~f0"
    exit
}

# 🔒 Force TLS 1.2 (hindari error download)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 🧠 Config
$repoUrl = "https://raw.githubusercontent.com/jauharimtikhan/cdn-jtech-panel/main"
$installScript = "$env:TEMP\intall-windows.ps1"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " JTech Panel Installer" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# ⚠️ Confirm user intent (anti-malware flag)
$confirm = Read-Host "Do you want to continue installation? (y/n)"
if ($confirm -ne "y") {
    Write-Host "Installation cancelled."
    exit
}

try {
    Write-Host "Downloading installer..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri "$repoUrl/install-windows.ps1" -OutFile $installScript -UseBasicParsing

    if (-not (Test-Path $installScript)) {
        throw "Download failed"
    }

    Write-Host "Download complete." -ForegroundColor Green

    # 🔥 Run script (NO iex)
    Write-Host "Running installer..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File $installScript

    Write-Host "Installation finished." -ForegroundColor Green
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # 🧹 Cleanup
    if (Test-Path $installScript) {
        Remove-Item $installScript -Force
    }
}
