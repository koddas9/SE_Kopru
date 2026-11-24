# ============================================================
# ATLAS - SAHTE OYUN / TELEMETRI SIMULATORU (atlas_sahte_oyun.ps1)
# Konum: C:\SE_Kopru\araclar\atlas_sahte_oyun.ps1
# Calistir: powershell -NoProfile -ExecutionPolicy Bypass -File C:\SE_Kopru\araclar\atlas_sahte_oyun.ps1
# ============================================================

[CmdletBinding()]
param(
    [int]$AralikMs = 500
)

$KokYol = 'C:\SE_Kopru'
$AracYol = Join-Path $KokYol 'araclar'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($dir in @($KokYol, $AracYol)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$TelemetriPath = Join-Path $KokYol 'telemetri.txt'
$KomutPath     = Join-Path $KokYol 'komut.txt'
$DogrulaPath   = Join-Path $KokYol 'dogrula.txt'
$SohbetPath    = Join-Path $KokYol 'sohbet.txt'
$CevapPath     = Join-Path $KokYol 'cevap.txt'

function Get-NowMs {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function New-MesajId {
    return ('{0}-{1}' -f (Get-NowMs), (Get-Random -Minimum 100 -Maximum 9999))
}

function Write-SafeAtomicFile {
    param(
        [Parameter(Mandatory = $true)][string]$HedefYol,
        [Parameter(Mandatory = $true)][string]$Icerik,
        [int]$MaxDeneme = 8,
        [int]$BeklemeMs = 25
    )

    $klasor = Split-Path -Parent $HedefYol
    if ($klasor -and -not (Test-Path -LiteralPath $klasor)) {
        New-Item -ItemType Directory -Path $klasor -Force | Out-Null
    }

    $benzersiz = '{0}-{1}-{2}.tmp' -f ([System.IO.Path]::GetFileName($HedefYol)), $PID, ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $geciciYol = Join-Path $(if ($klasor) { $klasor } else { '.' }) $benzersiz

    try {
        [System.IO.File]::WriteAllText($geciciYol, $Icerik, $Utf8NoBom)

        for ($deneme = 1; $deneme -le $MaxDeneme; $deneme++) {
            try {
                if (Test-Path -LiteralPath $HedefYol) {
                    try {
                        [System.IO.File]::Replace($geciciYol, $HedefYol, $null, $true)
                        return
                    } catch {
                        Move-Item -LiteralPath $geciciYol -Destination $HedefYol -Force -ErrorAction Stop
                        return
                    }
                } else {
                    Move-Item -LiteralPath $geciciYol -Destination $HedefYol -Force -ErrorAction Stop
                    return
                }
            } catch {
                try {
                    Copy-Item -LiteralPath $geciciYol -Destination $HedefYol -Force -ErrorAction Stop
                    Remove-Item -LiteralPath $geciciYol -Force -ErrorAction SilentlyContinue
                    return
                } catch {
                    if ($deneme -eq $MaxDeneme) {
                        throw
                    }
                    Start-Sleep -Milliseconds ($BeklemeMs * $deneme)
                }
            }
        }
    } finally {
        if (Test-Path -LiteralPath $geciciYol) {
            Remove-Item -LiteralPath $geciciYol -Force -ErrorAction SilentlyContinue
        }
    }
}

$Bloklar = [ordered]@{
    '20563486' = @{ Ad = 'Ana Reaktor';     Tur = 'Reactor';            Durum = 'acik' }
    '27702543' = @{ Ad = 'Yedek Batarya';  Tur = 'BatteryBlock';       Durum = 'acik' }
    '45611759' = @{ Ad = 'Hidrojen Tanki'; Tur = 'GasTank';            Durum = 'acik' }
    '64996460' = @{ Ad = 'Hangar Kapisi';  Tur = 'AirtightHangarDoor'; Durum = 'kapali' }
    '99515278' = @{ Ad = 'Ana Konnektor';  Tur = 'ShipConnector';      Durum = 'acik' }
    '22546901' = @{ Ad = 'Ana Batarya';    Tur = 'BatteryBlock';       Durum = 'acik' }
    '5152898'  = @{ Ad = 'Jiroskop 1';     Tur = 'Gyro';               Durum = 'acik' }
    '81148140' = @{ Ad = 'On Isik';        Tur = 'InteriorLight';      Durum = 'acik' }
    '9046204'  = @{ Ad = 'Oksijen Tanki';  Tur = 'GasTank';            Durum = 'acik' }
}

$BataryaModlari = @{ '27702543' = 'Auto'; '22546901' = 'Auto' }
$HasarListe = @(
    @{ Ad = 'Hangar Kapisi'; Yuzde = 35 },
    @{ Ad = 'Jiroskop 1';    Yuzde = 12 },
    @{ Ad = 'On Isik';       Yuzde = 4 }
)
$SonSonuc = ''
$GucMw         = 142.5
$OksijenYuzde  = 94
$BataryaYuzde  = 88
$HidrojenYuzde = 76
$SonKomutId    = ''
$CevapOfset    = [long]0
if (Test-Path -LiteralPath $CevapPath) {
    $CevapOfset = (Get-Item -LiteralPath $CevapPath).Length
}

function Send-SahteSohbetGirdisi([string]$Mesaj) {
    $temiz = ($Mesaj -replace '[\r\n|]+', ' ').Trim()
    if (-not $temiz) { return }
    $satir = '{0}|{1}|{2}' -f (New-MesajId), (Get-NowMs), $temiz
    [System.IO.File]::AppendAllText($SohbetPath, $satir + "`r`n", $Utf8NoBom)
    Write-Host ("{0} [OYUNCU] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $temiz)
}

function Build-TelemetriMetni {
    $acikSay = @($Bloklar.Values | Where-Object { $_.Durum -eq 'acik' }).Count
    $guncelMw = if ($Bloklar['20563486'].Durum -eq 'acik') { $GucMw } else { 18.4 }
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add("zaman_ms=$(Get-NowMs)")
    $satirlar.Add("son_komut_id=$Script:SonKomutId")
    $satirlar.Add("son_komut_sonuc=$Script:SonSonuc")
    $satirlar.Add("grid_adi=Atlas_MK1")
    $satirlar.Add("guc_mw=$guncelMw")
    $satirlar.Add("alt_grid_sayisi=1")
    $satirlar.Add("oksijen_yuzde=$OksijenYuzde")
    $satirlar.Add("batarya_yuzde=$BataryaYuzde")
    $satirlar.Add("hidrojen_yuzde=$HidrojenYuzde")
    $satirlar.Add("hasarli_sayisi=$($HasarListe.Count)")
    if ($HasarListe.Count -gt 0) {
        $satirlar.Add("en_hasar_yuzde=$($HasarListe[0].Yuzde)")
        $satirlar.Add("en_hasar_adi=$($HasarListe[0].Ad)")
        for ($i = 0; $i -lt $HasarListe.Count; $i++) { $satirlar.Add("hasar.$($i+1)=$($HasarListe[$i].Ad)|$($HasarListe[$i].Yuzde)") }
    }
    foreach ($bid in $BataryaModlari.Keys) { $satirlar.Add("bmod.$bid=$($BataryaModlari[$bid])") }
    $satirlar.Add("calismayan_blok=0")
    $satirlar.Add("blok_sayisi=$($Bloklar.Count)")
    $satirlar.Add("acik_blok_sayisi=$acikSay")

    foreach ($id in $Bloklar.Keys) {
        $b = $Bloklar[$id]
        $satirlar.Add("blok.$id=$($b.Ad)|$($b.Tur)|$($b.Durum)")
    }
    return (($satirlar -join "`r`n") + "`r`n")
}

function Process-KomutDosyasi {
    if (-not (Test-Path -LiteralPath $KomutPath)) { return }
    try {
        $ham = [System.IO.File]::ReadAllText($KomutPath, $Utf8NoBom).Trim()
        if ([string]::IsNullOrWhiteSpace($ham)) { return }
        $parca = $ham -split '\|', 4
        if ($parca.Count -lt 4) { return }

        $kId  = $parca[0].Trim()
        $aks  = $parca[2].Trim().ToUpperInvariant()
        $hed  = $parca[3].Trim()

        if ($kId -eq $Script:SonKomutId) { return }
        $Script:SonKomutId = $kId

        $sonucMesaj = "OK $aks $hed"
        if ($aks -eq 'AC' -and $Bloklar.Contains($hed)) {
            $Bloklar[$hed].Durum = 'acik'
            $sonucMesaj = "OK $aks $hed"
        } elseif ($aks -eq 'KAPAT' -and $Bloklar.Contains($hed)) {
            $Bloklar[$hed].Durum = 'kapali'
            $sonucMesaj = "OK $aks $hed"
        } elseif ($aks -eq 'BATARYA_MOD') {
            $hp = $hed -split ':'
            $say = 0
            foreach ($bid in @($BataryaModlari.Keys)) {
                if ($hp[0] -eq '0' -or $hp[0] -eq $bid) { $BataryaModlari[$bid] = $hp[1]; $say++ }
            }
            $sonucMesaj = if ($say -gt 0) { "OK $aks $hed" } else { "HATA:batarya bulunamadi" }
        } elseif ($aks -eq 'BAGLANTI_KES') {
            $Bloklar['99515278'].Durum = 'kapali'
            $sonucMesaj = "OK $aks 0"
        }

        $Script:SonSonuc = if ($sonucMesaj -like 'HATA*') { $sonucMesaj } else { 'OK' }
        $dogrulaSatir = '{0}|{1}|{2}' -f $kId, (Get-NowMs), $sonucMesaj
        Write-SafeAtomicFile -HedefYol $DogrulaPath -Icerik ($dogrulaSatir + "`r`n")
        Write-Host ("{0} [DOGRULA] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $dogrulaSatir)
    } catch {
        Write-Warning "Komut isleme hatasi: $($_.Exception.Message)"
    }
}

function Read-YeniCevaplar {
    if (-not (Test-Path -LiteralPath $CevapPath)) { return }
    try {
        $fs = [System.IO.File]::Open($CevapPath, 'Open', 'Read', 'ReadWrite')
        try {
            $len = $fs.Length
            if ($len -lt $Script:CevapOfset) { $Script:CevapOfset = 0 }
            if ($len -eq $Script:CevapOfset) { return }
            $fs.Position = $Script:CevapOfset
            $buf = New-Object byte[] ($len - $Script:CevapOfset)
            $n = $fs.Read($buf, 0, $buf.Length)
            $son = [Array]::LastIndexOf($buf, [byte]10, $n - 1)
            if ($son -lt 0) { return }
            $Script:CevapOfset += ($son + 1)
            $metin = $Utf8NoBom.GetString($buf, 0, $son + 1)
            foreach ($satir in ($metin -split "`r?`n" | Where-Object { $_ })) {
                Write-Host ("{0} [SOHBET] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $satir)
            }
        } finally {
            $fs.Dispose()
        }
    } catch { }
}

$Script:YazmaModu = $false
$Script:YazmaTampon = New-Object System.Text.StringBuilder

# Telemetri durmasin diye engellemeyen (non-blocking) mesaj girisi: m = yazmaya basla, Enter = gonder, Esc = vazgec
function Check-TusGirdisi {
    try {
        while ([Console]::KeyAvailable) {
            $tus = [Console]::ReadKey($true)
            if (-not $Script:YazmaModu) {
                if ($tus.KeyChar -eq 'm' -or $tus.KeyChar -eq 'M') {
                    $Script:YazmaModu = $true
                    $Script:YazmaTampon.Clear() | Out-Null
                    Write-Host ''
                    Write-Host -NoNewline 'Mesaj (Enter gonder, Esc iptal): '
                }
                continue
            }
            if ($tus.Key -eq 'Enter') {
                $Script:YazmaModu = $false
                Write-Host ''
                $girdi = $Script:YazmaTampon.ToString()
                $Script:YazmaTampon.Clear() | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($girdi)) { Send-SahteSohbetGirdisi $girdi }
            } elseif ($tus.Key -eq 'Escape') {
                $Script:YazmaModu = $false
                $Script:YazmaTampon.Clear() | Out-Null
                Write-Host ' (iptal)'
            } elseif ($tus.Key -eq 'Backspace') {
                if ($Script:YazmaTampon.Length -gt 0) {
                    $Script:YazmaTampon.Length = $Script:YazmaTampon.Length - 1
                    Write-Host -NoNewline "`b `b"
                }
            } elseif ($tus.KeyChar -ne [char]0) {
                [void]$Script:YazmaTampon.Append($tus.KeyChar)
                Write-Host -NoNewline $tus.KeyChar
            }
        }
    } catch { }
}

Write-Host ("{0} [INFO] Sahte oyun simulatoru basladi (Aralik: {1} ms) | [m] Mesaj yaz" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $AralikMs)

while ($true) {
    try {
        $telIcerik = Build-TelemetriMetni
        Write-SafeAtomicFile -HedefYol $TelemetriPath -Icerik $telIcerik
        Process-KomutDosyasi
        Read-YeniCevaplar
        Check-TusGirdisi
    } catch {
        Write-Host ("{0} [ERR] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
    }
    Start-Sleep -Milliseconds $AralikMs
}