# ================================
# JTech Panel - Ultimate Installer + Connector (HMAC)
# ================================

param(
    [Parameter(Mandatory=$true)]
    [string]$token,
    [string]$projectId
)

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
    Write-Host "❌ Harus dijalankan sebagai Administrator!" -ForegroundColor Red
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
    } else {
        exit 1
    }
}

# ================================
# 🔐 VERIFY HASH FILE
# ================================
function Verify-Hash {
    param($file, $hash)

    if (-not $hash) { return }

    $h = (Get-FileHash $file -Algorithm SHA256).Hash
    if ($h -ne $hash) {
        throw "Hash mismatch!"
    }
}

# ================================
# 🔐 VERIFY BINARY SIGNATURE
# ================================
function Verify-BinarySignature {
    param([string]$filePath)

    $sig = Get-AuthenticodeSignature $filePath
    if ($sig.Status -ne "Valid") {
        throw "Signature tidak valid!"
    }
}

# ================================
# 🔐 VERIFY HMAC SIGNATURE
# ================================
function Verify-ManifestSignature {
    param($data, $signature, $secret)

    try {
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($data)
        $hashBytes = $hmac.ComputeHash($bytes)

        $computed = ([BitConverter]::ToString($hashBytes)) -replace "-", ""
        $computed = $computed.ToLower()

        if ($computed -ne $signature.ToLower()) {
            throw "Signature tidak valid!"
        }

        Write-Host "✅ Signature valid (HMAC)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Signature verification gagal" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
}

# ================================
# 🌐 LICENSE API
# ================================
function Get-LicenseManifest {
    param($projectId, $token)

    Write-Host "🔐 Validating license..." -ForegroundColor Cyan

    $res = Invoke-RestMethod -Uri "https://api-lisensi.jtechpanel.dpdns.org/api/v1/validate-manifest" -Method POST -Body @{
        project_id = $projectId
        token = $token
    }

    if (-not $res.valid) {
        throw "License invalid"
    }

    $secret = $res.client_secret

    $data = ($res.file_manifest | ConvertTo-Json -Depth 10 -Compress)

    Verify-ManifestSignature -data $data -signature $res.signature -secret $secret

    return $res.file_manifest
}

# ================================
# 🔁 DOWNLOAD FILE (RESUME)
# ================================
function Download-File {
    param($url, $output)

    $temp = "$output.part"
    $retry = 0

    while ($retry -lt $MAX_RETRY) {
        try {
            $start = 0
            if (Test-Path $temp) {
                $start = (Get-Item $temp).Length
            }

            $req = [System.Net.HttpWebRequest]::Create($url)
            if ($start -gt 0) { $req.AddRange($start) }

            $res = $req.GetResponse()
            $stream = $res.GetResponseStream()
            $fs = [System.IO.File]::Open($temp, 'Append')

            $buffer = New-Object byte[] $CHUNK_SIZE
            $total = $start

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
                $total += $read

                Write-Progress -Activity "Downloading" -Status "$([math]::Round($total/1MB,2)) MB"
            }

            $fs.Close()
            Rename-Item $temp $output -Force
            return
        }
        catch {
            $retry++
            if ($retry -ge $MAX_RETRY) { throw }
        }
    }
}

# ================================
# ⚡ MULTI THREAD DOWNLOAD
# ================================
function Download-AllFiles {
    param($manifest, $dir)

    $jobs = @()

    foreach ($file in $manifest) {
        $output = Join-Path $dir $file.name

        $jobs += Start-Job -ScriptBlock {
            param($url, $output)
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $url -Destination $output
        } -ArgumentList $file.url, $output
    }

    $jobs | ForEach-Object { Wait-Job $_ }
}

# ================================
# 📦 PROCESS FILE
# ================================
function Process-Files {
    param($manifest, $downloadDir, $installDir)

    foreach ($file in $manifest) {
        $path = Join-Path $downloadDir $file.name

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
# 🚀 CONNECTOR INSTALL
# ================================
function install-connector {
    param($token)

    $installDir = "$env:ProgramFiles\cloudflared"
    $path = "$installDir\cloudflared.exe"

    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    if (!(Test-Path $path)) {
        Invoke-WebRequest "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $path
    }

    Verify-BinarySignature $path

    $service = Get-Service "cloudflared" -ErrorAction SilentlyContinue
    if ($service) {
        & $path service uninstall | Out-Null
        Start-Sleep 2
    }

    & $path service install $token
}

# ================================
# 🚀 MAIN FLOW
# ================================

$downloadDir = "$env:TEMP\jtech"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

$installDir = Select-InstallDirectory

$manifest = Get-LicenseManifest -projectId $projectId -token $token

Download-AllFiles -manifest $manifest -dir $downloadDir

foreach ($file in $manifest) {
    $path = Join-Path $downloadDir $file.name
    if (!(Test-Path $path)) {
        Download-File $file.url $path
    }
}

Process-Files -manifest $manifest -downloadDir $downloadDir -installDir $installDir

install-connector -token $token

Write-Host "🎉 INSTALL COMPLETE BRE!" -ForegroundColor Green