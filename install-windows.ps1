# ================================
# JTech Panel - Windows Installer
# ================================

param(
    [Parameter(Mandatory=$true)]
    [string]$token
)

# 🔥 Relaunch kalau dari CMD
if (-not $PSVersionTable) {
    Write-Host "Re-launching in PowerShell..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File "%~f0" -token "%token%"
    exit
}

if (-not ([Security.Principal.WindowsPrincipal] 
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator!" -ForegroundColor Red
    exit 1
}

# 🔒 TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function install-connector {
    param([string]$token)

    if (-not $token) { 
        Write-Error "Token cluster lu mana Bre? Pake -token <TOKEN>"
        exit 1
    }

    $installDir = "$env:ProgramFiles\cloudflared"
    $path = "$installDir\cloudflared.exe"

    # ================================
    # 1. Pastikan folder ada
    # ================================
    if (!(Test-Path $installDir)) {
        Write-Host "Membuat directory install..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # ================================
    # 2. Install cloudflared kalau belum ada
    # ================================
    if (Test-Path $path) {
        Write-Host "Cloudflared sudah ada, skip download. Langsung gass!" -ForegroundColor Yellow
    } else {
        Write-Host "Gass download cloudflared terbaru..." -ForegroundColor Cyan
        
        $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
        
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -ErrorAction Stop
            Write-Host "✅ Download selesai!" -ForegroundColor Green
        } catch {
            Write-Host "❌ Gagal download cloudflared" -ForegroundColor Red
            Write-Host $_.Exception.Message
            exit 1
        }
    }

    # ================================
    # 3. Install / reinstall service
    # ================================
    Write-Host "Memasang service JTech Connector..." -ForegroundColor Cyan

    try {
        $service = Get-Service "cloudflared" -ErrorAction SilentlyContinue

        if ($service) {
            Write-Host "Service sudah ada, uninstall dulu..." -ForegroundColor Yellow
            & $path service uninstall | Out-Null
            Start-Sleep -Seconds 2
        }

        & $path service install $token

        if ($LASTEXITCODE -ne 0) {
            throw "Service install gagal"
        }

        Write-Host "----------------------------------------" -ForegroundColor Green
        Write-Host "Mantap Bre! Connector sudah jalan di background." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Gagal install service" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
}

# ================================
# 🚀 RUN
# ================================
install-connector -token $token
