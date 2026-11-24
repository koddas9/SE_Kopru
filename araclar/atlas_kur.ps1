<#
.SYNOPSIS
    C:\SE_Kopru\ Atlas kurulum ve butunluk dogrulama betigi.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\SE_Kopru\araclar\atlas_kur.ps1"
#>
[CmdletBinding()]
param(
    [string]$BaseDir = "C:\SE_Kopru",
    [string]$OllamaUrl = "http://127.0.0.1:11434"
)

$ErrorActionPreference = "Continue"

$AraclarDir = Join-Path $BaseDir "araclar"
$Utf8Bom    = New-Object System.Text.UTF8Encoding($true)
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

$HataSayisi = 0
$UyariSayisi = 0

function Write-OK {
    param([string]$Mesaj)
    Write-Host "[OK] $Mesaj" -ForegroundColor Green
}

function Write-Uyari {
    param([string]$Mesaj)
    $script:UyariSayisi++
    Write-Host "[UYARI] $Mesaj" -ForegroundColor Yellow
}

function Write-Hata {
    param([string]$Mesaj)
    $script:HataSayisi++
    Write-Host "[HATA] $Mesaj" -ForegroundColor Red
}

function Test-HasUtf8Bom {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    } catch {
        return $false
    }
}

Write-Host "=== Atlas Kopru Kurulum ve Dogrulama ===" -ForegroundColor Cyan
Write-Host "Kok Dizin : $BaseDir"
Write-Host "Arac Dizini: $AraclarDir"
Write-Host ""

# 1. Klasor kontrolu
foreach ($dir in @($BaseDir, $AraclarDir)) {
    if (Test-Path -LiteralPath $dir) {
        Write-OK "Klasor mevcut: $dir"
    } else {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-OK "Klasor olusturuldu: $dir"
        } catch {
            Write-Hata "Klasor olusturulamadi: $dir ($($_.Exception.Message))"
        }
    }
}

# 2. Iletisim dosyalarinin kontrolu / olusturulmasi
$IletisimDosyalari = @("sohbet.txt", "cevap.txt", "komut.txt", "telemetri.txt")
foreach ($fileName in $IletisimDosyalari) {
    $fullPath = Join-Path $BaseDir $fileName
    if (Test-Path -LiteralPath $fullPath) {
        $len = (Get-Item -LiteralPath $fullPath).Length
        Write-OK "Iletisim dosyasi hazir: $fileName ($len bayt)"
    } else {
        try {
            [System.IO.File]::WriteAllText($fullPath, "", $Utf8NoBom)
            Write-OK "Iletisim dosyasi olusturuldu: $fileName"
        } catch {
            Write-Hata "Iletisim dosyasi olusturulamadi: $fileName ($($_.Exception.Message))"
        }
    }
}

# 3. Dokuman ve ifade dosyalarinin kontrolu
$DokumanVeIfadeler = @(
    @{ Yol = (Join-Path $BaseDir "README.md"); BomGerekli = $true }
    @{ Yol = (Join-Path $BaseDir "CHANGELOG.md"); BomGerekli = $true }
    @{ Yol = (Join-Path $AraclarDir "turkce_ifadeler.txt"); BomGerekli = $true }
)

foreach ($item in $DokumanVeIfadeler) {
    $yol = $item.Yol
    if (Test-Path -LiteralPath $yol) {
        $len = (Get-Item -LiteralPath $yol).Length
        if ($len -le 0) {
            Write-Uyari "Dosya bos: $yol"
        } elseif ($item.BomGerekli -and (-not (Test-HasUtf8Bom -Path $yol))) {
            Write-Uyari "UTF-8 BOM bulunamadi: $yol"
        } else {
            Write-OK "Dosya ve BOM dogrulandi: $yol ($len bayt)"
        }
    } else {
        Write-Uyari "Dosya eksik: $yol"
    }
}

# 4. Arac betiklerinin varligi ve syntax kontrolu
$AracBetikleri = @(
    "atlas_sahte_oyun.ps1",
    "atlas_izleyici.ps1",
    "atlas_model_testi.ps1",
    "atlas_kur.ps1"
)

foreach ($scriptName in $AracBetikleri) {
    $scriptPath = Join-Path $AraclarDir $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Uyari "Arac betigi eksik: $scriptPath"
        continue
    }

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        Write-Hata "Syntax hatasi ($scriptName): $($errors[0].Message)"
    } else {
        $bomOk = Test-HasUtf8Bom -Path $scriptPath
        if ($bomOk) {
            Write-OK "Betik gecerli ve UTF-8 BOM: $scriptName"
        } else {
            Write-Uyari "Betik gecerli ancak UTF-8 BOM degil: $scriptName"
        }
    }
}

# 5. Ollama servis kontrolu
try {
    $tagsUri = ($OllamaUrl.TrimEnd("/")) + "/api/tags"
    $resp = Invoke-RestMethod -Uri $tagsUri -Method Get -TimeoutSec 5 -ErrorAction Stop
    $modelSayisi = if ($resp.models) { @($resp.models).Count } else { 0 }
    Write-OK "Ollama erisilebilir ($OllamaUrl) | Yuklu model sayisi: $modelSayisi"
} catch {
    Write-Uyari "Ollama servisine ulasilamadi ($OllamaUrl): $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Ozet: $HataSayisi Hata | $UyariSayisi Uyari ===" -ForegroundColor Cyan