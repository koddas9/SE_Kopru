<#
.SYNOPSIS
    Farkli Ollama modellerini sorular.csv uzerinden test eder ve CSV raporu uretir.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\SE_Kopru\araclar\atlas_model_testi.ps1" -Model "gemma3:4b"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Model
)

$BaseDir = "C:\SE_Kopru"
$AraclarDir = Join-Path $BaseDir "araclar"
$SorularPath = Join-Path $AraclarDir "sorular.csv"
$SohbetPath = Join-Path $BaseDir "sohbet.txt"
$CevapPath = Join-Path $BaseDir "cevap.txt"

if (-not (Test-Path -LiteralPath $SorularPath)) {
    Write-Error "sorular.csv bulunamadi: $SorularPath"
    exit 1
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $SohbetPath)) {
    [System.IO.File]::WriteAllText($SohbetPath, "", $Utf8NoBom)
}
if (-not (Test-Path -LiteralPath $CevapPath)) {
    [System.IO.File]::WriteAllText($CevapPath, "", $Utf8NoBom)
}

function Get-UnixMs {
    $epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    return [long]([DateTime]::UtcNow - $epoch).TotalMilliseconds
}

$guvenliModel = ($Model -replace '[^a-zA-Z0-9_-]', '_')
$tarihDamgasi = Get-Date -Format "yyyyMMdd_HHmmss"
$CiktiCsv = Join-Path $AraclarDir "model_sonuc_${guvenliModel}_${tarihDamgasi}.csv"

$sorular = @(Import-Csv -LiteralPath $SorularPath -Delimiter ";" -Encoding UTF8)
$sonuclar = New-Object System.Collections.Generic.List[PSObject]

Write-Host "Model testi basliyor -> Model: $Model | Soru sayisi: $($sorular.Count)" -ForegroundColor Cyan

$sira = 0
foreach ($row in $sorular) {
    $sira++
    $soruMetni = if ($null -ne $row.soru) { $row.soru.Trim() } else { "" }
    $turMetni = if ($null -ne $row.tur) { $row.tur.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($soruMetni)) {
        continue
    }

    $oncekiSatirlar = @([System.IO.File]::ReadAllLines($CevapPath, $Utf8NoBom))
    $baslangicSatirSayisi = $oncekiSatirlar.Count

    $msgId = (Get-UnixMs).ToString() + "-" + $sira.ToString()
    $nowMs = Get-UnixMs
    $gonderilen = "atlas $soruMetni"
    $satir = "$msgId|$nowMs|$gonderilen`n"

    $fs = New-Object System.IO.FileStream($SohbetPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        $bytes = $Utf8NoBom.GetBytes($satir)
        $fs.Write($bytes, 0, $bytes.Length)
    } finally {
        $fs.Close()
    }

    $t0 = Get-Date
    $bulunanCevap = ""
    $zamanAsimi = $true

    while (((Get-Date) - $t0).TotalSeconds -lt 40) {
        $guncelSatirlar = @([System.IO.File]::ReadAllLines($CevapPath, $Utf8NoBom))
        if ($guncelSatirlar.Count -gt $baslangicSatirSayisi) {
            for ($i = $baslangicSatirSayisi; $i -lt $guncelSatirlar.Count; $i++) {
                $cand = $guncelSatirlar[$i]
                if ($cand -like "*[ATLAS]*") {
                    $bulunanCevap = $cand
                    $zamanAsimi = $false
                    break
                }
            }
            if (-not $zamanAsimi) {
                break
            }
        }
        Start-Sleep -Milliseconds 200
    }

    $gecenSn = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
    if ($zamanAsimi) {
        $bulunanCevap = "[ZAMAN_ASIMI_40SN]"
    }

    $obj = [PSCustomObject]@{
        soru    = $soruMetni
        tur     = $turMetni
        cevap   = $bulunanCevap
        sure_sn = $gecenSn
    }
    $sonuclar.Add($obj)

    $renk = if ($zamanAsimi) { "Red" } else { "Green" }
    Write-Host "[$sira/$($sorular.Count)] (${gecenSn}s) $soruMetni" -ForegroundColor $renk
}

$sonuclar | Export-Csv -LiteralPath $CiktiCsv -Delimiter ";" -NoTypeInformation -Encoding UTF8

$toplamSure = 0.0
$asanSayisi = 0
foreach ($s in $sonuclar) {
    $toplamSure += [double]$s.sure_sn
    if ([double]$s.sure_sn -ge 40.0 -or $s.cevap -eq "[ZAMAN_ASIMI_40SN]") {
        $asanSayisi++
    }
}
$ortSure = if ($sonuclar.Count -gt 0) { [Math]::Round($toplamSure / $sonuclar.Count, 2) } else { 0 }

Write-Host ""
Write-Host "=== OZET ($Model) ===" -ForegroundColor Yellow
Write-Host "Ortalama sure : $ortSure sn"
Write-Host "40 sn asan    : $asanSayisi / $($sonuclar.Count)"
Write-Host "Cikti dosyasi : $CiktiCsv"