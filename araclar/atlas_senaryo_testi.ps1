# ============================================================
# ATLAS - SENARYO TESTI (atlas_senaryo_testi.ps1)
# Konum: C:\SE_Kopru\araclar\atlas_senaryo_testi.ps1
# On kosul: SAHTE OYUN + IZLEYICI calisiyor olmali, gercek oyun KAPALI olmali.
# Calistir: powershell -NoProfile -ExecutionPolicy Bypass -File C:\SE_Kopru\araclar\atlas_senaryo_testi.ps1
# senaryolar.csv:  cumle;beklenen   (beklenen: regex; " && " ile coklu; basina ! koyarsan "eslesmemeli")
# ============================================================
[CmdletBinding()]
param(
    [string]$Senaryo = 'C:\SE_Kopru\araclar\senaryolar.csv',
    [int]$ZamanAsimiSn = 60
)

$Kok   = 'C:\SE_Kopru'
$Log   = Join-Path $Kok 'atlas.log'
$Sohbet = Join-Path $Kok 'sohbet.txt'
$Tel   = Join-Path $Kok 'telemetri.txt'
$Utf8  = New-Object System.Text.UTF8Encoding($false)

function Get-NowMs { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Read-LogSatirlari {
    try {
        $fs = [System.IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
        try {
            $sr = New-Object System.IO.StreamReader($fs, $Utf8)
            $t = $sr.ReadToEnd()
        } finally { $fs.Dispose() }
        return @($t -split "`r?`n" | Where-Object { $_ })
    } catch { return @() }
}

# Sahte oyun kontrolu
try {
    $t = [System.IO.File]::ReadAllText($Tel, $Utf8)
    if ($t -notmatch 'grid_adi=Atlas_MK1') { Write-Host 'HATA: telemetri sahte oyundan gelmiyor (grid_adi=Atlas_MK1 degil). Gercek oyunu kapat, sahte oyunu ac.' -ForegroundColor Red; exit 1 }
    if ($t -match 'zaman_ms=(\d+)') { if ((Get-NowMs) - [int64]$Matches[1] -gt 5000) { Write-Host 'HATA: telemetri bayat, sahte oyun calismiyor.' -ForegroundColor Red; exit 1 } }
} catch { Write-Host 'HATA: telemetri.txt okunamadi.' -ForegroundColor Red; exit 1 }

if (-not (Test-Path -LiteralPath $Senaryo)) { Write-Host "HATA: $Senaryo yok." -ForegroundColor Red; exit 1 }
$satirlar = @(Import-Csv -LiteralPath $Senaryo -Delimiter ';' -Encoding UTF8)
$sonuclar = @()
$gec = 0; $kal = 0; $n = 0

foreach ($s in $satirlar) {
    $n++
    $cumle = [string]$s.cumle
    if (-not $cumle) { continue }
    $once = (Read-LogSatirlari).Count
    $ms = Get-NowMs
    $id = '{0}-{1}' -f $ms, (Get-Random -Minimum 100 -Maximum 9999)
    [System.IO.File]::AppendAllText($Sohbet, ('{0}|{1}|{2}' -f $id, $ms, $cumle) + "`r`n", $Utf8)

    $basla = Get-NowMs; $cevapGordu = $false; $sonBuyume = Get-NowMs; $sonSay = $once
    $blok = @()
    while (((Get-NowMs) - $basla) -lt ($ZamanAsimiSn * 1000)) {
        Start-Sleep -Milliseconds 500
        $tum = Read-LogSatirlari
        if ($tum.Count -gt $sonSay) { $sonSay = $tum.Count; $sonBuyume = Get-NowMs }
        $yeni = @($tum | Select-Object -Skip $once)
        $gi = -1
        for ($i = 0; $i -lt $yeni.Count; $i++) { if ($yeni[$i] -match '\[GIRDI\]') { $gi = $i; break } }
        if ($gi -ge 0) {
            $blok = @($yeni | Select-Object -Skip $gi)
            if (@($blok | Where-Object { $_ -match '\[CEVAP\]' }).Count -gt 0) {
                $cevapGordu = $true
                if (((Get-NowMs) - $sonBuyume) -gt 2500) { break }
            }
        } elseif (((Get-NowMs) - $basla) -gt 8000 -and $s.beklenen -match '^!') {
            break    # girdi hic islenmedi; yalniz "olmamali" beklentileri icin yeterli
        }
    }
    $metin = ($blok -join "`n")
    $ok = $true; $neden = ''
    foreach ($b in ([string]$s.beklenen -split ' && ')) {
        $b = $b.Trim(); if (-not $b) { continue }
        if ($b.StartsWith('!')) {
            if ($metin -match $b.Substring(1)) { $ok = $false; $neden += "olmamaliydi: $($b.Substring(1)); " }
        } else {
            if ($metin -notmatch $b) { $ok = $false; $neden += "yok: $b; " }
        }
    }
    if (-not $cevapGordu -and -not ([string]$s.beklenen -match '^!')) { $ok = $false; $neden += 'zaman asimi; ' }
    if ($ok) { $gec++; Write-Host ("[GECTI] {0,2}. {1}" -f $n, $cumle) -ForegroundColor Green }
    else {
        $kal++; Write-Host ("[KALDI] {0,2}. {1}  -> {2}" -f $n, $cumle, $neden) -ForegroundColor Red
        $ozet = (($blok | Where-Object { $_ -match '\[(CEVAP|KOMUT|KURAL|RED)\]' } | Select-Object -First 3) -join ' / ')
        if ($ozet) { Write-Host "         log: $($ozet.Substring(0, [Math]::Min(220, $ozet.Length)))" -ForegroundColor DarkGray }
    }
    $sonuclar += [pscustomobject]@{ no = $n; cumle = $cumle; beklenen = $s.beklenen; sonuc = $(if ($ok) { 'GECTI' } else { 'KALDI' }); neden = $neden }
}

Write-Host ''
Write-Host ("SONUC: {0} gecti, {1} kaldi (toplam {2})" -f $gec, $kal, ($gec + $kal)) -ForegroundColor Cyan
$cikti = Join-Path $Kok ('araclar\senaryo_sonuc_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$sonuclar | Export-Csv -LiteralPath $cikti -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host "Sonuc dosyasi: $cikti"
