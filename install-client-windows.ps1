# ================================
# JTech Panel - Ultimate Installer + Connector (HMAC HARDENED)
# ================================

param(
    [Parameter(Mandatory = $true)]
    [string]$token,
    [string]$projectId
)

$ErrorActionPreference = "Stop"

# ================================
# 🔒 TLS
# ================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# 🔐 CONFIG
# ================================
$MAX_RETRY = 3
$CHUNK_SIZE = 5MB

# ================================
# 🔥 ADMIN CHECK
# ================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "❌ Run as Administrator!" -ForegroundColor Red
    exit 1
}

# ================================
# 📁 SELECT DIR
# ================================
function Select-InstallDirectory {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq "OK") {
        return $dialog.SelectedPath
    }
    else {
        throw "User cancelled install"
    }
}

# ================================
# 🔐 VERIFY HASH
# ================================
function Verify-Hash {
    param($file, $hash)

    if (-not $hash) { return }

    $h = (Get-FileHash $file -Algorithm SHA256).Hash
    if ($h -ne $hash) {
        throw "Hash mismatch: $file"
    }
}

# ================================
# 🔐 VERIFY EXE SIGNATURE
# ================================
function Verify-BinarySignature {
    param($filePath)

    $sig = Get-AuthenticodeSignature $filePath
    if ($sig.Status -ne "Valid") {
        throw "Invalid binary signature: $filePath"
    }
}

# ================================
# 🔐 VERIFY HMAC
# ================================
function Verify-ManifestSignature {
    param($data, $signature, $secret)

    if (-not $secret) {
        throw "Missing client secret"
    }

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($secret)

    $bytes = [Text.Encoding]::UTF8.GetBytes($data)
    $hashBytes = $hmac.ComputeHash($bytes)

    $computed = ([BitConverter]::ToString($hashBytes)) -replace "-", ""
    $computed = $computed.ToLower()

    if ($computed -ne $signature.ToLower()) {
        throw "Invalid manifest signature"
    }

    Write-Host "✅ Signature verified" -ForegroundColor Green
}

# ================================
# 🌐 LICENSE API
# ================================
function Get-LicenseManifest {
    param($projectId, $token)

    Write-Host "🔐 Validating license..." -ForegroundColor Cyan

    try {
        $body = @{
            project_id = $projectId
            token      = $token
        } | ConvertTo-Json -Compress # 🔥 FIX: Convert ke JSON

        $res = Invoke-RestMethod -Uri "https://api-lisensi.jtechpanel.dpdns.org/api/v1/validate-manifest" -Method POST -Body $body -ContentType "application/json"
    }
    catch {
        throw "API request failed: $($_.Exception.Message)"
    }

    if (-not $res.valid) {
        throw "License invalid"
    }

    if (-not $res.client_secret) {
        throw "Missing client secret"
    }

    if (-not $res.file_manifest) {
        throw "Empty manifest"
    }

    $data = ($res.file_manifest | ConvertTo-Json -Depth 10 -Compress)

    Verify-ManifestSignature -data $data -signature $res.signature -secret $res.client_secret

    return $res.file_manifest
}

# ================================
# 🔁 DOWNLOAD (RESUME)
# ================================
function Download-File {
    param($url, $output)

    $temp = "$output.part"
    $retry = 0

    while ($retry -lt $MAX_RETRY) {
        try {
            Write-Host "⬇️ Downloading: $url"

            $start = 0
            if (Test-Path $temp) {
                $start = (Get-Item $temp).Length
            }

            $req = [System.Net.HttpWebRequest]::Create($url)
            if ($start -gt 0) { $req.AddRange($start) }

            $res = $req.GetResponse()
            if ($res.StatusCode -ne 200 -and $res.StatusCode -ne 206) {
                throw "HTTP Error: $($res.StatusCode)"
            }

            $stream = $res.GetResponseStream()
            
            # 🔥 FIX: Tambah explicit 'Write' access biar gak ArgumentException
            $fs = [System.IO.File]::Open($temp, 'Append', 'Write')

            $buffer = New-Object byte[] $CHUNK_SIZE

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
            }

            $fs.Close()
            Rename-Item $temp $output -Force

            Write-Host "✅ Download complete"
            return
        }
        catch {
            if ($null -ne $fs) { $fs.Close() } # Pastikan memory file di-release kalau error
            
            $retry++
            Write-Host "⚠️ Retry $retry/$MAX_RETRY"

            if ($retry -ge $MAX_RETRY) {
                throw "Download failed: $url"
            }
        }
    }
}

# ================================
# 📦 PROCESS FILE
# ================================
function Process-Files {
    param($manifest, $downloadDir, $installDir)

    foreach ($file in $manifest) {
        $path = Join-Path $downloadDir $file.name

        if (!(Test-Path $path)) {
            throw "File missing: $path"
        }

        Verify-Hash $path $file.hash

        if ($file.type -eq "exe") {
            Verify-BinarySignature $path
            Start-Process $path -Wait
        }

        if ($file.type -eq "zip") {
            Expand-Archive $path -DestinationPath $installDir -Force
        }
    }
}

# ================================
# 🚀 CONNECTOR
# ================================
function Install-Connector {
    param($token)

    $installDir = "$env:ProgramFiles\cloudflared"
    $path = "$installDir\cloudflared.exe"

    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    if (!(Test-Path $path)) {
        Write-Host "⬇️ Download cloudflared..."
        Invoke-WebRequest "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $path
    }

    Verify-BinarySignature $path

    $service = Get-Service "cloudflared" -ErrorAction SilentlyContinue
    if ($service) {
        & $path service uninstall | Out-Null
        Start-Sleep 2
    }

    & $path service install $token

    Write-Host "✅ Connector installed"
}

# ================================
# 🚀 MAIN
# ================================

try {
    $downloadDir = "$env:TEMP\jtech"
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    $installDir = Select-InstallDirectory

    $manifest = Get-LicenseManifest -projectId $projectId -token $token

    foreach ($file in $manifest) {
        $path = Join-Path $downloadDir $file.name
        if (!(Test-Path $path)) {
            Download-File $file.url $path
        }
    }

    Process-Files -manifest $manifest -downloadDir $downloadDir -installDir $installDir

    Install-Connector -token $token

    Write-Host "🎉 INSTALL COMPLETE BRE!" -ForegroundColor Green
}
catch {
    Write-Host "❌ INSTALL FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}