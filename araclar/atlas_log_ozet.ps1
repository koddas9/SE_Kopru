<#
.SYNOPSIS
    atlas.log dosyasini okuyup kisa sorun giderme ozeti uretir.
.EXAMPLE
    .\atlas_log_ozet.ps1 -SonDakika 60
#>
param(
    [int]$SonDakika = 0
)

$BaseDir = "C:\SE_Kopru"
$LogPath = Join-Path $BaseDir "atlas.log"
$OzetPath = Join-Path $BaseDir "log_ozet.txt"

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Error "atlas.log bulunamadi: $LogPath"
    exit 1
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$tumSatirlar = @([System.IO.File]::ReadAllLines($LogPath, $Utf8NoBom))

$filtreliSatirlar = New-Object System.Collections.Generic.List[string]
$sinirZaman = if ($SonDakika -gt 0) { (Get-Date).AddMinutes(-$SonDakika) } else { [DateTime]::MinValue }

foreach ($satir in $tumSatirlar) {
    if ([string]::IsNullOrWhiteSpace($satir)) {
        continue
    }
    if ($SonDakika -gt 0) {
        if ($satir -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            $dt = [DateTime]::MinValue
            $parsedOk = [DateTime]::TryParseExact(
                $matches[1],
                "yyyy-MM-dd HH:mm:ss",
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$dt
            )
            if ($parsedOk -and $dt -ge $sinirZaman) {
                $filtreliSatirlar.Add($satir)
            }
        }
    } else {
        $filtreliSatirlar.Add($satir)
    }
}

$etiketler = @("GIRDI", "CEVAP", "KOMUT", "DOGRULA", "RED", "WARN", "ERR")
$sayac = @{}
foreach ($e in $etiketler) {
    $sayac[$e] = 0
}

$ilkZaman = "-"
$sonZaman = "-"
$dogrulaToplam = 0
$dogrulaBasarili = 0
$sonGirdiZaman = $null
$girdiCevapSureleri = New-Object System.Collections.Generic.List[double]
$errWarnSatirlar = New-Object System.Collections.Generic.List[string]

foreach ($s in $filtreliSatirlar) {
    $satirZaman = $null
    if ($s -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        $zStr = $matches[1]
        if ($ilkZaman -eq "-") {
            $ilkZaman = $zStr
        }
        $sonZaman = $zStr
        $parsed = [DateTime]::MinValue
        $zOk = [DateTime]::TryParseExact(
            $zStr,
            "yyyy-MM-dd HH:mm:ss",
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed
        )
        if ($zOk) {
            $satirZaman = $parsed
        }
    }

    if ($s -match '\[(GIRDI|CEVAP|KOMUT|DOGRULA|RED|WARN|ERR|INFO|OGREN)\]') {
        $et = $matches[1].ToUpperInvariant()
        if ($sayac.ContainsKey($et)) {
            $sayac[$et]++
        }

        if ($et -eq "GIRDI" -and $null -ne $satirZaman) {
            $sonGirdiZaman = $satirZaman
        } elseif ($et -eq "CEVAP" -and $null -ne $sonGirdiZaman -and $null -ne $satirZaman) {
            $fark = ($satirZaman - $sonGirdiZaman).TotalSeconds
            if ($fark -ge 0) {
                $girdiCevapSureleri.Add([Math]::Round($fark, 2))
            }
            $sonGirdiZaman = $null
        } elseif ($et -eq "DOGRULA") {
            $dogrulaToplam++
            if ($s -match '\bOK\b' -and $s -notmatch 'HATA:') {
                $dogrulaBasarili++
            }
        } elseif ($et -eq "ERR" -or $et -eq "WARN") {
            $errWarnSatirlar.Add($s)
        }
    }
}

$basariOraniStr = if ($dogrulaToplam -gt 0) {
    $yuzde = [Math]::Round(($dogrulaBasarili * 100.0) / $dogrulaToplam, 1)
    "${yuzde}% ($dogrulaBasarili/$dogrulaToplam)"
} else {
    "veri yok"
}

$ortCevapStr = if ($girdiCevapSureleri.Count -gt 0) {
    $sum = 0.0
    foreach ($v in $girdiCevapSureleri) {
        $sum += $v
    }
    $ort = [Math]::Round($sum / $girdiCevapSureleri.Count, 2)
    "${ort}s"
} else {
    "veri yok"
}

$enUzun3 = @($girdiCevapSureleri | Sort-Object -Descending | Select-Object -First 3)
$enUzun3Str = if ($enUzun3.Count -gt 0) {
    ($enUzun3 | ForEach-Object { "${_}s" }) -join ", "
} else {
    "-"
}

$son10ErrWarn = @($errWarnSatirlar | Select-Object -Last 10)
$grupluErrWarn = @{}
foreach ($ew in $son10ErrWarn) {
    $temiz = ($ew -replace '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s*', '').Trim()
    if (-not $grupluErrWarn.ContainsKey($temiz)) {
        $grupluErrWarn[$temiz] = 0
    }
    $grupluErrWarn[$temiz]++
}

$son15Ham = @($filtreliSatirlar | Select-Object -Last 15)

$out = New-Object System.Collections.Generic.List[string]
$out.Add("Satir: $($filtreliSatirlar.Count) | Ilk: $ilkZaman | Son: $sonZaman")
$out.Add("Etiket: GIRDI=$($sayac['GIRDI']) CEVAP=$($sayac['CEVAP']) KOMUT=$($sayac['KOMUT']) DOGRULA=$($sayac['DOGRULA']) RED=$($sayac['RED']) WARN=$($sayac['WARN']) ERR=$($sayac['ERR'])")
$out.Add("Dogrulama basari: $basariOraniStr | Cevap sure ort: $ortCevapStr | En uzun 3: $enUzun3Str")

if ($grupluErrWarn.Count -gt 0) {
    $out.Add("Son ERR/WARN:")
    foreach ($k in $grupluErrWarn.Keys) {
        $out.Add("  [$($grupluErrWarn[$k])x] $k")
    }
}

$out.Add("--- Son 15 Satir ---")
foreach ($h in $son15Ham) {
    $out.Add($h)
}

$ozetMetin = ($out -join "`n") + "`n"
[System.IO.File]::WriteAllText($OzetPath, $ozetMetin, $Utf8NoBom)
Write-Output $ozetMetin.TrimEnd("`n")