# ================================
# JTech Panel - Ultimate Installer
# ================================

param(
    [Parameter(Mandatory=$true)]
    [string]$token,
    [string]$projectId
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================================
# 🔐 CONFIG
# ================================
$MAX_RETRY = 3
$CHUNK_SIZE = 5MB
$LICENSE_PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----YOUR_KEY-----END PUBLIC KEY-----"

# ================================
# 🔥 ADMIN CHECK
# ================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Run as Administrator!" -ForegroundColor Red
    exit 1
}

# ================================
# 📁 SELECT DIR
# ================================
function Select-InstallDirectory {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Pilih folder install"

    if ($dialog.ShowDialog() -eq "OK") {
        return $dialog.SelectedPath
    } else {
        exit 1
    }
}

# ================================
# 🔐 VERIFY SIGNED MANIFEST
# ================================
function Verify-ManifestSignature {
    param($data, $signature)

    try {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportFromPem($LICENSE_PUBLIC_KEY)

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($data)
        $sigBytes = [Convert]::FromBase64String($signature)

        $valid = $rsa.VerifyData($bytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        if (-not $valid) {
            throw "Signature manifest tidak valid!"
        }

        Write-Host "✅ Manifest signature valid" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Signature verification gagal" -ForegroundColor Red
        exit 1
    }
}

# ================================
# 🌐 LICENSE API
# ================================
function Get-LicenseManifest {
    param($token, $projectId)

    $res = Invoke-RestMethod -Uri "https://api-lisensi.jtechpanel.dpdns.org/api/v1/validate-manifest" -Method POST -Body @{
        token = $token
        project_id = $projectId
    }

    if (-not $res.valid) {
        throw "License invalid"
    }

    # verify signature
    Verify-ManifestSignature -data ($res.file_manifest | ConvertTo-Json -Depth 10) -signature $res.signature

    return $res.file_manifest
}

# ================================
# 🔁 SMART DOWNLOAD (RESUME + RETRY + PROGRESS)
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
            if ($start -gt 0) {
                $req.AddRange($start)
                Write-Host "🔄 Resume dari $start byte"
            }

            $res = $req.GetResponse()
            $stream = $res.GetResponseStream()

            $fs = [System.IO.File]::Open($temp, 'Append')

            $buffer = New-Object byte[] $CHUNK_SIZE
            $total = $start

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
                $total += $read

                Write-Progress -Activity "Downloading $(Split-Path $output -Leaf)" `
                    -Status "$([math]::Round($total/1MB,2)) MB downloaded"
            }

            $fs.Close()
            Rename-Item $temp $output -Force

            Write-Host "✅ Download selesai"
            return
        }
        catch {
            $retry++
            Write-Host "⚠️ Retry $retry/$MAX_RETRY..."

            if ($retry -ge $MAX_RETRY) {
                throw "Download gagal total"
            }
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

    Write-Host "⚡ Download parallel berjalan..."

    $jobs | ForEach-Object { Wait-Job $_ }

    Write-Host "✅ Semua download selesai"
}

# ================================
# 🔐 HASH CHECK
# ================================
function Verify-Hash {
    param($file, $hash)

    if (-not $hash) { return }

    $h = (Get-FileHash $file -Algorithm SHA256).Hash

    if ($h -ne $hash) {
        throw "Hash mismatch!"
    }

    Write-Host "✅ Hash OK"
}

# ================================
# 🚀 PROCESS FILE
# ================================
function Process-Files {
    param($manifest, $downloadDir, $installDir)

    foreach ($file in $manifest) {
        $path = Join-Path $downloadDir $file.name

        Verify-Hash $path $file.hash

        if ($file.type -eq "zip") {
            Expand-Archive $path -DestinationPath $installDir -Force
        }

        if ($file.type -eq "exe") {
            Start-Process $path -Wait
        }
    }
}

# ================================
# 🚀 MAIN FLOW
# ================================

$downloadDir = "$env:TEMP\jtech"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

$installDir = Select-InstallDirectory

$manifest = Get-LicenseManifest -token $token -projectId $projectId

# ⚡ Multi-thread download
Download-AllFiles -manifest $manifest -dir $downloadDir

# fallback individual (resume)
foreach ($file in $manifest) {
    $path = Join-Path $downloadDir $file.name
    if (!(Test-Path $path)) {
        Download-File $file.url $path
    }
}

Process-Files -manifest $manifest -downloadDir $downloadDir -installDir $installDir

Write-Host "🎉 INSTALL SELESAI BRE!" -ForegroundColor Green