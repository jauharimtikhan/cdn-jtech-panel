# ================================
# JTech Panel - Ultimate Installer + Connector
# ================================

param(
    [Parameter(Mandatory=$true)]
    [string]$token,
    [string]$projectId
)

# 🔥 Relaunch kalau dari CMD
if (-not $PSVersionTable) {
    Write-Host "Re-launching in PowerShell..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File "%~f0" -token "%token%" -projectId "%projectId%"
    exit
}

# 🔒 TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# 🔐 CONFIG
# ================================
$MAX_RETRY = 3
$CHUNK_SIZE = 5MB
$LICENSE_PUBLIC_KEY = @"
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1MEbxWiu5c0DSnp6Y8ha
nrQaXqeclNUdl5XUtC78+DSnO1WrgvmeiNiliiQIV6t4fPtRi1AOdHtyN9FezcTt
sxs/s1A6GVlYHA3Ed+whMf1/1PUhCaj5luinO5S6bG8tPjT4SZ0SaA7vnpFcwCMe
ccqsKncZ/3UKYA0rL+kKlcBKwbZ1FGZr+ths5acqeruErOBEEo2FDkZY9X7rIs/J
EHgCsVk2V1+gWUyPuqMM09dHu9TpuB3OzkvzY5avH1LqTUCPHCrMp8/FRQBkJkN3
xr0QLvViGXPMOEG7WYaTkKRGbzDv9mX14TF8O888tbyubOMJr2NtJawZ4hWcC/kZ
hQIDAQAB
-----END PUBLIC KEY-----
"@

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
# 🔐 VERIFY SIGNATURE
# ================================
function Verify-BinarySignature {
    param([string]$filePath)

    $sig = Get-AuthenticodeSignature $filePath
    if ($sig.Status -ne "Valid") {
        throw "Signature tidak valid!"
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
        throw "Hash mismatch!"
    }
}

# ================================
# 🔐 VERIFY MANIFEST SIGNATURE
# ================================
function Verify-ManifestSignature {
    param($data, $signature)

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($LICENSE_PUBLIC_KEY)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($data)
    $sigBytes = [Convert]::FromBase64String($signature)

    if (-not $rsa.VerifyData($bytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
        throw "Manifest signature invalid!"
    }

    Write-Host "✅ Manifest valid"
}

# ================================
# 🌐 LICENSE API
# ================================
function Get-LicenseManifest {
    param($projectId)

    $res = Invoke-RestMethod -Uri "https://api-lisensi.jtechpanel.dpdns.org/api/v1/validate-manifest" -Method POST -Body @{
        project_id = $projectId
    }

    if (-not $res.valid) {
        throw "License invalid"
    }

    Verify-ManifestSignature -data ($res.file_manifest | ConvertTo-Json -Depth 10) -signature $res.signature

    return $res.file_manifest
}

# ================================
# 🔁 DOWNLOAD (RESUME + PROGRESS)
# ================================
function Download-File {
    param($url, $output)

    $temp = "$output.part"
    $retry = 0

    while ($retry -lt $MAX_RETRY) {
        try {
            $start = (Test-Path $temp) ? (Get-Item $temp).Length : 0

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

$manifest = Get-LicenseManifest -projectId $projectId

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