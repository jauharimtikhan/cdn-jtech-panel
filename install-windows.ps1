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

# 🔒 TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# 🔥 CHECK ADMIN
# ================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "❌ Harus dijalankan sebagai Administrator!" -ForegroundColor Red
    Write-Host "👉 Klik kanan → Run as Administrator" -ForegroundColor Yellow
    exit 1
}

# ================================
# 🔐 VERIFY SIGNATURE FUNCTION
# ================================
function Verify-BinarySignature {
    param([string]$filePath)

    if (!(Test-Path $filePath)) {
        throw "File tidak ditemukan untuk verifikasi"
    }

    $signature = Get-AuthenticodeSignature $filePath

    if ($signature.Status -ne "Valid") {
        throw "Signature tidak valid! Status: $($signature.Status)"
    }

    Write-Host "✅ Signature valid: $($signature.SignerCertificate.Subject)" -ForegroundColor Green
}

# ================================
# 🔐 OPTIONAL HASH CHECK
# ================================
function Verify-Hash {
    param(
        [string]$filePath,
        [string]$expectedHash
    )

    if (-not $expectedHash) {
        Write-Host "⚠️ Hash tidak disediakan, skip hash check" -ForegroundColor Yellow
        return
    }

    $actualHash = (Get-FileHash $filePath -Algorithm SHA256).Hash

    if ($actualHash -ne $expectedHash) {
        throw "Hash mismatch! File mungkin sudah dimodifikasi"
    }

    Write-Host "✅ Hash verified" -ForegroundColor Green
}

# ================================
# 🚀 INSTALL FUNCTION
# ================================
function install-connector {
    param([string]$token)

    if (-not $token) { 
        Write-Error "Token cluster lu mana Bre? Pake -token <TOKEN>"
        exit 1
    }

    $installDir = "$env:ProgramFiles\cloudflared"
    $path = "$installDir\cloudflared.exe"

    # 1. Ensure directory
    if (!(Test-Path $installDir)) {
        Write-Host "Membuat directory install..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # 2. Install kalau belum ada
    if (Test-Path $path) {
        Write-Host "Cloudflared sudah ada, skip download. Langsung gass!" -ForegroundColor Yellow
    } else {
        Write-Host "Download cloudflared terbaru..." -ForegroundColor Cyan
        
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
    # 🔐 VERIFY BINARY
    # ================================
    try {
        Verify-BinarySignature -filePath $path

        # 🔥 optional (isi kalau mau strict)
        # Verify-Hash -filePath $path -expectedHash "ISI_HASH_RESMI_DI_SINI"
    } catch {
        Write-Host "❌ Verifikasi binary gagal!" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }

    # ================================
    # 🔧 SERVICE SETUP
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
