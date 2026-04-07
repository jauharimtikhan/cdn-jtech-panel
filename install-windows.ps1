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
$installScript = "$env:TEMP\install-windows.ps1"
$fileName = "install-core.ps1"
$downloadUrl = "$repoUrl/$fileName"

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
    Write-Host "Downloading from: $downloadUrl" -ForegroundColor Cyan

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
     Write-Host "❌ Download failed!" -ForegroundColor Red
    Write-Host "URL: $downloadUrl" -ForegroundColor Yellow
    Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor Red

    Write-Host "`n👉 Fix kemungkinan:" -ForegroundColor Cyan
    Write-Host "- Cek nama file di repo" 
    Write-Host "- Cek branch (main/master)"
    Write-Host "- Cek path file"
    exit 1
}
finally {
    # 🧹 Cleanup
    if (Test-Path $installScript) {
        Remove-Item $installScript -Force
    }
}
