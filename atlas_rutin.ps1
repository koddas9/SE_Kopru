# ============================================================
# ATLAS - PARCA 6: RUTINLER + HAFIZA + OGRENME (atlas_rutin.ps1)
# Konum: C:\SE_Kopru\atlas_rutin.ps1  (izleyici otomatik yukler)
#
# 1) Rutinler : telemetriye bakip esik asilinca uyarir (histerezisli, hiz sinirli, sessiz mod).
#               VARSAYILAN OLARAK SADECE UYARIR, kendi basina aksiyon almaz.
# 2) Hafiza   : her DOGRULANMIS komutu atlas_hafiza.log'a yazar (boyut sinirli).
# 3) Ogrenme  : hafizadan KURAL ONERISI uretir (atlas_kurallar_oneri.txt).
#               Oneriler sen "atlas kurallari onayla" diyene kadar AKTIF OLMAZ.
#               Aktif kurallar atlas_kurallar.txt'tedir, onaydan once .bak yedegi alinir.
# Hizli komutlar: "atlas sus", "atlas konus", "atlas kurallari onayla",
#                 "atlas kurallari reddet", "atlas kural durumu"
# ============================================================

$Script:Cfg.Hafiza   = Join-Path $Script:Kok 'atlas_hafiza.log'
$Script:Cfg.Kurallar = Join-Path $Script:Kok 'atlas_kurallar.txt'
$Script:Cfg.Oneri    = Join-Path $Script:Kok 'atlas_kurallar_oneri.txt'
$Script:HafizaMaxMB  = 1
$Script:KuralMaxSatir = 50
$Script:OneriMaxSatir = 30

$Script:Sessiz = $false
$Script:SonSoru = ''
$Script:SonOzet = ''
$Script:RutinDurum = @{}
$Script:SonRutinMesajMs = 0
$Script:SonRutinKontrol = 0
$Script:SonTelGorMs = 0
$Script:TelGordu = $false
$Script:TelKayipUyarildi = $false

# Esikler: Tetik'te uyarir, Birak'ta sifirlanir (histerezis: 20'de uyar, 30'da sifirla)
$Script:Rutinler = @(
    @{ Ad='batarya';  Anahtar='batarya_yuzde';  Tetik={ param($v) $v -lt 20 }; Birak={ param($v) $v -gt 30 }; Ton='KRİTİK'; Mesaj='Batarya %{0}. Şarj kaynağı gerekiyor.' },
    @{ Ad='hidrojen'; Anahtar='hidrojen_yuzde'; Tetik={ param($v) $v -lt 15 }; Birak={ param($v) $v -gt 25 }; Ton='UYARI';  Mesaj='Hidrojen %{0}.' },
    @{ Ad='oksijen';  Anahtar='oksijen_yuzde';  Tetik={ param($v) $v -lt 20 }; Birak={ param($v) $v -gt 30 }; Ton='KRİTİK'; Mesaj='Oksijen %{0}.' },
    # Hasar: en kotu blok %30'u asinca uyarir, %10'un altina inince (tamirle) sifirlanir. Anahtar yoksa hasar yok demektir.
    @{ Ad='hasar';    Anahtar='en_hasar_yuzde'; Tetik={ param($v) $v -ge 30 }; Birak={ param($v) $v -lt 10 }; Ton='UYARI'; Mesaj='Hasar tespit edildi: [EK] %{0}.'; EkAnahtar='en_hasar_adi'; YoksaSifir=$true }
)

# ---------------- Rutinler ----------------
function Send-RutinMesaj([string]$Ton, [string]$Metin) {
    if ($Script:Sessiz) { return $false }
    $simdi = Get-NowMs
    if (($simdi - $Script:SonRutinMesajMs) -lt 10000) { return $false }   # genel hiz siniri
    $Script:SonRutinMesajMs = $simdi
    Send-Cevap "[$Ton] $Metin"
    if (Get-Command Send-PbOzet -ErrorAction SilentlyContinue) { Send-PbOzet "${Ton}: $Metin" }
    return $true
}

function Get-RutinMetni($r, $Tel) {
    $m = $r.Mesaj -f $Tel[$r.Anahtar]
    $ek = ''
    if ($r.EkAnahtar -and $Tel.ContainsKey($r.EkAnahtar)) { $ek = $Tel[$r.EkAnahtar] }
    return $m.Replace('[EK]', $ek)
}

function Invoke-Rutinler {
    $simdi = Get-NowMs
    if (($simdi - $Script:SonRutinKontrol) -lt 2000) { return }
    $Script:SonRutinKontrol = $simdi
    $tel = Get-Telemetri
    if (-not (Test-TelemetriTaze $tel)) {
        # oyun duraklatilmis olabilir: 20 sn tolerans, sonra bir kez uyar
        if ($Script:TelGordu -and -not $Script:TelKayipUyarildi -and (($simdi - $Script:SonTelGorMs) -gt 20000)) {
            if (Send-RutinMesaj 'UYARI' 'Oyundan telemetri gelmiyor (duraklatma ya da eklenti sorunu olabilir).') { $Script:TelKayipUyarildi = $true }
        }
        return                                  # bayat veriyle rutin calistirma
    }
    $Script:TelGordu = $true; $Script:SonTelGorMs = $simdi; $Script:TelKayipUyarildi = $false

    foreach ($r in $Script:Rutinler) {
        if (-not $Script:RutinDurum.ContainsKey($r.Ad)) { $Script:RutinDurum[$r.Ad] = @{ Aktif = $false; SonMs = 0 } }
        $d = $Script:RutinDurum[$r.Ad]
        $v = 0.0
        if ($Tel.ContainsKey($r.Anahtar)) { try { $v = [double]$Tel[$r.Anahtar] } catch { continue } }
        elseif (-not $r.YoksaSifir) { continue }
        if (-not $d.Aktif) {
            if (& $r.Tetik $v) {
                if (Send-RutinMesaj $r.Ton (Get-RutinMetni $r $Tel)) { $d.Aktif = $true; $d.SonMs = $simdi }
            }
        } else {
            if (& $r.Birak $v) { $d.Aktif = $false }
            elseif (($simdi - $d.SonMs) -gt 300000) {                    # hatirlatma: 5 dk'da bir
                if (Send-RutinMesaj $r.Ton (Get-RutinMetni $r $Tel)) { $d.SonMs = $simdi }
            }
        }
    }
}

# ---------------- Hafiza ----------------
function Add-Hafiza([string]$Soru, [string]$Aksiyon, [string]$Hedef, [string]$Sonuc) {
    try {
        $ok = if ($Sonuc -like 'OK*') { 'OK' } else { 'HATA' }
        $soruT = ConvertTo-Norm (($Soru -replace '[\r\n|]', ' '))
        $satir = '{0}|{1}|{2}|{3}|{4}' -f (Get-NowMs), $ok, $Aksiyon, $Hedef, $soruT
        $f = $Script:Cfg.Hafiza
        [System.IO.File]::AppendAllText($f, $satir + "`r`n", $Script:Utf8)
        if ((Get-Item -LiteralPath $f).Length -gt ($Script:HafizaMaxMB * 1MB)) {
            $s = @((Read-SafeFile $f) -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 1000)
            Write-AtomicFile $f ($s -join "`r`n")
        }
        Update-Ogrenme
    } catch { Write-AtlasLog 'WARN' "hafiza: $($_.Exception.Message)" }
}

# ---------------- Ogrenme (yalnizca oneri uretir) ----------------
function Get-SatirListesi([string]$Yol) {
    $t = Read-SafeFile $Yol
    if (-not $t) { return @() }
    return @($t -split "`r?`n" | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Add-Oneri([string]$Satir) {
    $Satir = $Satir -replace '[^\p{L}\p{N} |_\-\.]', ''          # injection / bozuk karakter temizligi
    if (-not $Satir) { return }
    $var = @(Get-SatirListesi $Script:Cfg.Kurallar) + @(Get-SatirListesi $Script:Cfg.Oneri)
    if ($var -contains $Satir) { return }
    $oneri = @(Get-SatirListesi $Script:Cfg.Oneri)
    if ($oneri.Count -ge $Script:OneriMaxSatir) { return }
    [System.IO.File]::AppendAllText($Script:Cfg.Oneri, $Satir + "`r`n", $Script:Utf8)
    Write-AtlasLog 'OGREN' "kural onerisi: $Satir"
}

function Update-Ogrenme {
    $satirlar = @(Get-SatirListesi $Script:Cfg.Hafiza | Select-Object -Last 200)
    $kayit = @(foreach ($s in $satirlar) {
        $p = $s -split '\|', 5
        if ($p.Count -eq 5) { [pscustomobject]@{ Ok = $p[1]; Aks = $p[2]; Hedef = $p[3]; Soru = $p[4] } }
    })
    # ALIAS: ayni soru ifadesi ayni bloga 3+ kez DOGRULANMIS sekilde gittiyse
    $alias = $kayit | Where-Object { $_.Ok -eq 'OK' -and $_.Aks -in @('AC','KAPAT') -and $_.Hedef -ne '0' -and $_.Soru } |
             Group-Object { '{0}|{1}|{2}' -f $_.Soru, $_.Aks, $_.Hedef } | Where-Object { $_.Count -ge 3 }
    foreach ($g in $alias) { Add-Oneri ('ALIAS|' + $g.Name) }
    # UYARI: ayni aksiyon+hedef son 20 kayitta 3+ kez basarisizsa
    $son = @($kayit | Select-Object -Last 20)
    $hata = $son | Where-Object { $_.Ok -eq 'HATA' -and $_.Hedef -ne '0' } |
            Group-Object { '{0}|{1}' -f $_.Aks, $_.Hedef } | Where-Object { $_.Count -ge 3 }
    foreach ($g in $hata) { Add-Oneri ('UYARI|' + $g.Name + '|sik basarisiz oluyor, once durumunu kontrol et') }
}

function Get-AktifKurallar {
    try {
        $f = $Script:Cfg.Kurallar
        if (Test-Path -LiteralPath $f) {
            if ((Get-Item -LiteralPath $f).Length -gt 20KB) {                # fabrika ayari / yedege don
                Write-AtlasLog 'WARN' 'kural dosyasi sismis, yedege donuluyor'
                if (Test-Path -LiteralPath ($f + '.bak')) { Copy-Item -LiteralPath ($f + '.bak') -Destination $f -Force }
                else { Remove-Item -LiteralPath $f -Force }
            }
        }
        $k = @(Get-SatirListesi $f | Select-Object -Last 20)
        if ($k.Count -eq 0) { return '' }
        return ($k -join "`n")
    } catch { return '' }
}

# ---------------- Hizli komutlar (LLM'e gitmeden) ----------------
function Invoke-HizliKomut([string]$Soru) {
    $n = ConvertTo-Norm $Soru
    $n = $n.Replace('ş','s').Replace('ğ','g').Replace('ü','u').Replace('ö','o').Replace('ç','c')
    switch -Regex ($n) {
        '^(sus|sessiz|sessiz ol)$' {
            $Script:Sessiz = $true; Send-Cevap 'Sessiz moddayım, rutin uyarılar kapalı. Açmak için "atlas konuş" de.'; return $true }
        '^(konus|ses ver|sessizligi kaldir)$' {
            $Script:Sessiz = $false; Send-Cevap 'Rutin uyarılar açık.'; return $true }
        '^kural(lari)? durumu?$' {
            $a = @(Get-SatirListesi $Script:Cfg.Kurallar).Count; $o = @(Get-SatirListesi $Script:Cfg.Oneri).Count
            Send-Cevap "Aktif kural: $a, onay bekleyen öneri: $o."; return $true }
        '^kurallari (onayla|kabul et)$' {
            $oneri = @(Get-SatirListesi $Script:Cfg.Oneri)
            if ($oneri.Count -eq 0) { Send-Cevap 'Onay bekleyen kural yok.'; return $true }
            $f = $Script:Cfg.Kurallar
            if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination ($f + '.bak') -Force }   # yedek
            $mevcut = @(Get-SatirListesi $f)
            $yeni = @($mevcut + $oneri | Select-Object -Unique | Select-Object -Last $Script:KuralMaxSatir)
            Write-AtomicFile $f (("# atlas kurallari - " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) + "`r`n" + ($yeni -join "`r`n"))
            Remove-Item -LiteralPath $Script:Cfg.Oneri -Force -ErrorAction SilentlyContinue
            Write-AtlasLog 'OGREN' "kurallar onaylandi: $($oneri.Count) yeni"
            Send-Cevap "$($oneri.Count) kural onaylandı ve aktif."; return $true }
        '^kurallari reddet$' {
            Remove-Item -LiteralPath $Script:Cfg.Oneri -Force -ErrorAction SilentlyContinue
            Send-Cevap 'Kural önerileri silindi.'; return $true }
    }
    return $false
}
