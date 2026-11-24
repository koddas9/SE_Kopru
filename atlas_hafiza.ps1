# ============================================================
# ATLAS - KISA SURELI HAFIZA, GUNLUK BELLEK VE ANI KUTUPHANESI
# Konum: C:\SE_Kopru\atlas_hafiza.ps1
# ============================================================

if (-not $Script:Kok) { $Script:Kok = 'C:\SE_Kopru' }
if (-not $Script:Utf8) { $Script:Utf8 = New-Object System.Text.UTF8Encoding($false) }

$Script:BellekKlasoru         = Join-Path $Script:Kok 'bellek'
$Script:AniKutuphanesiYolu    = Join-Path $Script:Kok 'ani_kutuphanesi.json'
$Script:AnilarYolu            = Join-Path $Script:Kok 'atlas_anilar.json'
$Script:KonsolideDurumYolu    = Join-Path $Script:Kok 'bellek_durum.json'

if (-not (Test-Path -LiteralPath $Script:BellekKlasoru)) {
    New-Item -ItemType Directory -Path $Script:BellekKlasoru -Force | Out-Null
}

$Script:SonHedef              = $null
$Script:BekleyenSecim         = $null
$Script:SonOyuncuIstekMs      = Get-NowMs
$Script:BosKalmaEsigiMs       = 120000
$Script:SonKonsolideKontrolMs = 0L

$Script:KonsolideDurum = [pscustomobject]@{
    son_konsolide_ms = [int64]0
    gun_imlecleri     = @{}
}

function Ensure-KonsolideDurum {
    if (-not $Script:KonsolideDurum) {
        $Script:KonsolideDurum = [pscustomobject]@{
            son_konsolide_ms = [int64]0
            gun_imlecleri     = @{}
        }
    }
    if (-not ($Script:KonsolideDurum.gun_imlecleri -is [hashtable])) {
        $yeniMap = @{}
        if ($Script:KonsolideDurum.gun_imlecleri) {
            foreach ($prop in @($Script:KonsolideDurum.gun_imlecleri.PSObject.Properties)) {
                if ($prop -and $prop.Name) {
                    $val = [int64]0
                    [void][int64]::TryParse([string]$prop.Value, [ref]$val)
                    $yeniMap[[string]$prop.Name] = $val
                }
            }
        }
        $Script:KonsolideDurum.gun_imlecleri = $yeniMap
    }
}

function Load-KonsolideDurum {
    Ensure-KonsolideDurum
    if (-not (Test-Path -LiteralPath $Script:KonsolideDurumYolu)) { return }
    try {
        $ham = [System.IO.File]::ReadAllText($Script:KonsolideDurumYolu, $Script:Utf8).Trim()
        if (-not $ham) { return }
        $d = $ham | ConvertFrom-Json
        if (-not $d) { return }
        $map = @{}
        if ($d.gun_imlecleri) {
            foreach ($prop in @($d.gun_imlecleri.PSObject.Properties)) {
                if ($prop -and $prop.Name) {
                    $val = [int64]0
                    [void][int64]::TryParse([string]$prop.Value, [ref]$val)
                    $map[[string]$prop.Name] = $val
                }
            }
        }
        $ms = [int64]0
        if ($d.son_konsolide_ms) { [void][int64]::TryParse([string]$d.son_konsolide_ms, [ref]$ms) }
        $Script:KonsolideDurum = [pscustomobject]@{
            son_konsolide_ms = $ms
            gun_imlecleri     = $map
        }
    } catch {
        Write-AtlasLog 'WARN' "bellek_durum okunamadi: $($_.Exception.Message)"
        Ensure-KonsolideDurum
    }
}

function Save-KonsolideDurum {
    Ensure-KonsolideDurum
    try {
        $json = ConvertTo-Json -InputObject $Script:KonsolideDurum -Depth 5
        Write-AtomicFile $Script:KonsolideDurumYolu $json
    } catch {
        Write-AtlasLog 'WARN' "bellek_durum yazilamadi: $($_.Exception.Message)"
    }
}

Load-KonsolideDurum

function Get-GunlukBellekYolu([datetime]$Tarih = (Get-Date)) {
    $gunAdi = $Tarih.ToString('yyyy-MM-dd') + '.jsonl'
    return (Join-Path $Script:BellekKlasoru $gunAdi)
}

function Register-OyuncuIstegi {
    $Script:SonOyuncuIstekMs = Get-NowMs
}

function Write-GunlukBellek([string]$Tur, [string]$Metin, [hashtable]$Ek = $null) {
    $temiz = ($Metin -replace '[\r\n]+', ' ').Trim()
    if (-not $temiz) { return }
    $simdi = Get-Date
    $yol = Get-GunlukBellekYolu $simdi
    $kayit = [ordered]@{
        ts    = (Get-NowMs)
        zaman = $simdi.ToString('yyyy-MM-dd HH:mm:ss')
        tur   = $Tur
        metin = $temiz
    }
    if ($Ek) {
        foreach ($k in $Ek.Keys) { $kayit[$k] = $Ek[$k] }
    }
    $satir = ($kayit | ConvertTo-Json -Compress -Depth 4) + "`r`n"
    try {
        [System.IO.File]::AppendAllText($yol, $satir, $Script:Utf8)
    } catch {
        Write-AtlasLog 'WARN' "gunluk bellek yazilamadi: $($_.Exception.Message)"
    }
}

function Read-GunlukBellekSatirlari([string]$Yol, [int]$BaslangicSatir = 0) {
    if ([string]::IsNullOrWhiteSpace($Yol) -or -not (Test-Path -LiteralPath $Yol)) { return @() }
    try {
        $tumSatirlar = @([System.IO.File]::ReadAllLines($Yol, $Script:Utf8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($BaslangicSatir -ge $tumSatirlar.Count) { return @() }
        $sonuclar = @()
        for ($i = [Math]::Max(0, $BaslangicSatir); $i -lt $tumSatirlar.Count; $i++) {
            try {
                $obj = $tumSatirlar[$i] | ConvertFrom-Json
                if ($null -ne $obj) {
                    $sonuclar += [pscustomobject]@{
                        SatirNo = ($i + 1)
                        Kayit   = $obj
                    }
                }
            } catch { }
        }
        return $sonuclar
    } catch {
        Write-AtlasLog 'WARN' "gunluk bellek okunamadi ($Yol): $($_.Exception.Message)"
        return @()
    }
}

function Get-AniKutuphanesi {
    $dizi = @()
    if (Test-Path -LiteralPath $Script:AniKutuphanesiYolu) {
        try {
            $ham = [System.IO.File]::ReadAllText($Script:AniKutuphanesiYolu, $Script:Utf8).Trim()
            if ($ham) {
                $parsed = $ham | ConvertFrom-Json
                foreach ($item in @($parsed)) {
                    if ($null -ne $item) { $dizi += $item }
                }
            }
        } catch {
            Write-AtlasLog 'WARN' "ani kutuphanesi okunamadi: $($_.Exception.Message)"
        }
    }
    return $dizi
}

function Get-KaliciAnilar {
    return @(Get-AniKutuphanesi)
}

function Format-AniEtiketliMetin([string]$Metin) {
    $t = ($Metin -replace '[\r\n|]+', ' ').Trim()
    if ($t -match '(?i)^benim\s+ad[ıi]m\s+(.+)$') {
        $ad = $Matches[1].Trim(' .!')
        if ($ad -and ($ad -notmatch '(?i)^atlas$')) {
            return "Oyuncu/Kaptan adinin '$ad' oldugu bilgisi"
        }
    }
    return $t
}

function Get-KaptanAdi {
    $anilar = @(Get-KaliciAnilar)
    for ($i = $anilar.Count - 1; $i -ge 0; $i--) {
        $a = $anilar[$i]
        if (-not $a) { continue }
        $m = [string]($(if ($a.icerik) { $a.icerik } else { $a.not }))
        if ($m -match "(?i)oyuncu/kaptan\s+adinin\s+'([^']+)'") {
            $ad = $Matches[1].Trim()
            if ($ad -and ($ad -notmatch '(?i)^atlas$')) { return $ad }
        }
        if ($m -match '(?i)^benim\s+ad[ıi]m\s+([a-zA-ZçğıöşüÇĞİÖŞÜİ]+)') {
            $ad = $Matches[1].Trim()
            if ($ad -and ($ad -notmatch '(?i)^atlas$')) { return $ad }
        }
    }
    return ''
}

function Add-AniKutuphanesine([string]$Metin, [string]$Kategori = 'genel', [string]$KaynakGun = '') {
    $temiz = Format-AniEtiketliMetin $Metin
    if (-not $temiz) { return $false }

    $liste = @(Get-AniKutuphanesi)
    $normYeni = ConvertTo-Norm $temiz

    foreach ($mevcut in $liste) {
        if (-not $mevcut) { continue }
        $eskiMetin = Format-AniEtiketliMetin ([string]($(if ($mevcut.icerik) { $mevcut.icerik } else { $mevcut.not })))
        if ((ConvertTo-Norm $eskiMetin) -eq $normYeni) {
            return $false
        }
    }

    $gun = if ($KaynakGun) { $KaynakGun } else { (Get-Date).ToString('yyyy-MM-dd') }
    $yeniKayit = [pscustomobject]@{
        id        = (New-KomutId)
        tarih     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        gun       = $gun
        kategori  = $Kategori
        icerik    = $temiz
        not       = $temiz
    }
    $liste = @($liste) + @($yeniKayit)

    $json = ConvertTo-Json -InputObject @($liste) -Depth 5
    Write-AtomicFile $Script:AniKutuphanesiYolu $json
    Write-AtlasLog 'ANI' "Kutuphaneye eklendi [$Kategori]: $temiz"
    return $true
}

function Save-KaliciAni([string]$Metin) {
    return (Add-AniKutuphanesine -Metin $Metin -Kategori 'kaptan_notu' -KaynakGun (Get-Date).ToString('yyyy-MM-dd'))
}

function Clear-KaliciAnilar {
    Write-AtlasLog 'INFO' 'Ani kutuphanesi silme talebi atlandi (ilk etapta silinme kapali).'
}

function Test-OnemliBellekKaydi($Kayit) {
    if (-not $Kayit) { return $null }
    $tur = ([string]$Kayit.tur).ToUpperInvariant().Trim()
    $metin = ([string]$Kayit.metin).Trim()
    if (-not $metin) { return $null }

    $norm = ConvertTo-Norm $metin
    $norm = $norm.Replace('ş','s').Replace('ğ','g').Replace('ü','u').Replace('ö','o').Replace('ç','c').Replace('ı','i')

    $kelimeler = @($norm -split '\s+' | Where-Object { $_ })
    if ($tur -notin @('ANI_NOT','ONAY','HATA') -and $kelimeler.Count -le 2) {
        if ($norm -match '^(selam|merhaba|tamam|evet|hayir|hayır|neyse|bosver|sagol|saol|eyvallah|anladim|peki|kapat|ac|geri ac)$') {
            return $null
        }
    }

    switch ($tur) {
        'ANI_NOT' {
            if ($metin.Length -lt 3) { return $null }
            return @{ Kategori = 'kaptan_notu'; Icerik = $metin }
        }
        'ONAY' {
            return @{ Kategori = 'riskli_islem'; Icerik = "Onayli islem: $metin" }
        }
        'HATA' {
            if ($norm -match '(\bhata\b|\bfail\b|kritik|hasar|basarisiz|istisna|zaman_asimi|zaman asimi)') {
                return @{ Kategori = 'olay'; Icerik = "Sistem olayi: $metin" }
            }
            return $null
        }
        'KOMUT' {
            if ($norm -match '^durum\b|\bdurum\s+0\b') { return $null }
            if ($norm -match '\b(ac|kapat|baglanti_kes)\b') {
                return @{ Kategori = 'komut'; Icerik = "Islem kaydi: $metin" }
            }
            return $null
        }
        'GIRDI' {
            if ($norm -match '\b(unutma|unutturma|hatirla|kaydet|not al|tercih|kural|hedef|gorev|plan|isim|adim|benim)\b' -and $kelimeler.Count -ge 2) {
                return @{ Kategori = 'kaptan_notu'; Icerik = $metin }
            }
            if ($norm -match '\b(baglanti.*kes|konnektor.*kes|reaktor|oksijen|hidrojen)\b' -and $norm -match '\b(kes|kapat|ac)\b') {
                return @{ Kategori = 'kritik_talep'; Icerik = "Kritik talep: $metin" }
            }
            return $null
        }
        default { return $null }
    }
}

function Invoke-BellekKonsolidasyon([bool]$Zorla = $false) {
    Ensure-KonsolideDurum
    $simdi = Get-NowMs
    if (-not $Zorla) {
        if (($simdi - $Script:SonOyuncuIstekMs) -lt $Script:BosKalmaEsigiMs) { return 0 }
        if (($simdi - $Script:SonKonsolideKontrolMs) -lt 30000) { return 0 }
    }
    $Script:SonKonsolideKontrolMs = $simdi

    if (-not (Test-Path -LiteralPath $Script:BellekKlasoru)) { return 0 }

    $dosyalar = @(Get-ChildItem -LiteralPath $Script:BellekKlasoru -Filter '*.jsonl' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($dosyalar.Count -eq 0) { return 0 }

    $eklenenSayisi = 0
    $durumDegisti = $false

    foreach ($dosya in $dosyalar) {
        if (-not $dosya) { continue }
        $gunAnahtar = [string]$dosya.BaseName
        $oncekiSatir = 0
        if ($Script:KonsolideDurum.gun_imlecleri -and $Script:KonsolideDurum.gun_imlecleri.ContainsKey($gunAnahtar)) {
            $oncekiSatir = [int]$Script:KonsolideDurum.gun_imlecleri[$gunAnahtar]
        }

        $yeniSatirlar = @(Read-GunlukBellekSatirlari -Yol $dosya.FullName -BaslangicSatir $oncekiSatir)
        if ($yeniSatirlar.Count -eq 0) { continue }

        foreach ($s in $yeniSatirlar) {
            if (-not $s) { continue }
            $onem = Test-OnemliBellekKaydi $s.Kayit
            if ($onem) {
                $ok = Add-AniKutuphanesine -Metin ([string]$onem.Icerik) -Kategori ([string]$onem.Kategori) -KaynakGun $gunAnahtar
                if ($ok) { $eklenenSayisi++ }
            }
            $Script:KonsolideDurum.gun_imlecleri[$gunAnahtar] = [int64]$s.SatirNo
            $durumDegisti = $true
        }
    }

    if ($durumDegisti) {
        $Script:KonsolideDurum.son_konsolide_ms = [int64]$simdi
        Save-KonsolideDurum
    }

    if ($eklenenSayisi -gt 0) {
        Write-AtlasLog 'INFO' "Bellek konsolidasyonu: $eklenenSayisi yeni ani kutuphaneye aktarildi."
    }
    return $eklenenSayisi
}

function Search-GunlukBellek([string]$Soru, [datetime]$Gun = (Get-Date), [int]$Limit = 8) {
    $yol = Get-GunlukBellekYolu $Gun
    $satirlar = @(Read-GunlukBellekSatirlari -Yol $yol -BaslangicSatir 0)
    if ($satirlar.Count -eq 0) { return @() }

    $jetonlar = @(Get-Jetonlar $Soru | Select-Object -Unique)
    if ($jetonlar.Count -eq 0) {
        return @($satirlar | Select-Object -Last $Limit | ForEach-Object { $_.Kayit })
    }

    $eslesen = @()
    foreach ($s in $satirlar) {
        if (-not $s -or -not $s.Kayit) { continue }
        $mNorm = ConvertTo-Norm ([string]$s.Kayit.metin)
        $p = 0
        foreach ($j in $jetonlar) {
            if ($mNorm.Contains($j)) { $p++ }
        }
        if ($p -gt 0) {
            $eslesen += [pscustomobject]@{ Skor = $p; Kayit = $s.Kayit }
        }
    }

    if ($eslesen.Count -eq 0) {
        return @($satirlar | Select-Object -Last $Limit | ForEach-Object { $_.Kayit })
    }

    return @($eslesen | Sort-Object Skor -Descending | Select-Object -First $Limit | ForEach-Object { $_.Kayit })
}

function Get-AnilarPromptMetni([string]$Soru = '') {
    $anilar = @(Get-KaliciAnilar)
    $satirlar = @()
    $kaptanAd = Get-KaptanAdi
    if ($kaptanAd) {
        $satirlar += "KIMLIK OZETI: Senin adin Atlas; karsindaki oyuncu/kaptanin adi '$kaptanAd'."
    }
    if ($anilar.Count -gt 0) {
        $sonlar = @($anilar | Select-Object -Last 12)
        $satirlar += 'ANI KUTUPHANESI (silinmeyen kalici anilar - KULLANICI/KAPTAN ile ilgili notlar sana ait degil):'
        foreach ($a in $sonlar) {
            if (-not $a) { continue }
            $kat = if ($a.kategori) { $a.kategori } else { 'ani' }
            $met = Format-AniEtiketliMetin ([string]($(if ($a.icerik) { $a.icerik } else { $a.not })))
            $satirlar += "- [$($a.tarih) | $kat] $met"
        }
    }
    if ($Script:SonHedef -and (((Get-NowMs) - $Script:SonHedef.Zaman) -lt 300000)) {
        $satirlar += "KISA SURELI HAFIZA: Az once '$($Script:SonHedef.Ad)' bloguna $($Script:SonHedef.Aksiyon) islemi yapildi."
    }
    if ($Soru -and ($Soru -match '(?i)\b(dun|dün|bugun|bugün|onceki|önceki|gecen|geçen|saat|kayit|kayıt|gun|gün)\b')) {
        $hedefGun = if ($Soru -match '(?i)\b(dun|dün)\b') { (Get-Date).AddDays(-1) } else { (Get-Date) }
        $gunKayitlari = @(Search-GunlukBellek -Soru $Soru -Gun $hedefGun -Limit 5)
        if ($gunKayitlari.Count -gt 0) {
            $satirlar += 'GUNLUK BELLEK ESLESMELERI (secili kayitlar):'
            foreach ($gk in $gunKayitlari) {
                if (-not $gk) { continue }
                $satirlar += "- [$($gk.zaman) | $($gk.tur)] $($gk.metin)"
            }
        }
    }
    if ($satirlar.Count -eq 0) { return '' }
    return (($satirlar -join "`n") + "`n`n")
}

function Test-AniKomutu([string]$Soru) {
    $n = ConvertTo-Norm $Soru
    $n = $n.Replace('ş','s').Replace('ğ','g').Replace('ü','u').Replace('ö','o').Replace('ç','c').Replace('ı','i')

    if ($n -match '^(benim adim ne|benim adim neydi|adim ne|adim neydi|ben kimim|ben kimim peki|beni taniyor musun|senin adin ne benim adim ne)$') {
        $kaptanAd = Get-KaptanAdi
        if ($kaptanAd) {
            Send-Cevap "Senin adın $kaptanAd; benim adım ise Atlas."
        } else {
            Send-Cevap "Adın anı kütüphanesinde henüz kayıtlı değil; istersen söyleyebilirsin."
        }
        return $true
    }

    if ($n -match '^(hafizayi derle|anilarimi derle|anilara derle|anilarin derlemesi|belleği derle|bellegi derle|derle)$') {
        $eklenen = Invoke-BellekKonsolidasyon -Zorla $true
        $toplam = @(Get-KaliciAnilar).Count
        Send-Cevap "Hafıza derlemesi tamamlandı: $eklenen yeni anı kütüphaneye eklendi (toplam $toplam kayıt)."
        return $true
    }
    if ($n -match '^(anilari sil|anilarini sil|hafizayi sil|her seyi unut)$') {
        Send-Cevap 'İlk etapta anı kütüphanesinde silme işlemi kapalı, kayıtların güvende.'
        return $true
    }
    if ($n -match '(anilarin ne|neleri hatirliyorsun|hafizanda ne var|kayitli notlar|ani kutuphanesi)') {
        $anilar = @(Get-KaliciAnilar)
        if ($anilar.Count -eq 0) {
            Send-Cevap 'Anı kütüphanesinde henüz kayıtlı anı yok. İstersen önemli şeyleri söyleyebilirsin ya da boşta kaldığımda günlük bellekten seçip arşivlerim.'
            return $true
        }
        $ozet = ($anilar | Select-Object -Last 5 | ForEach-Object { Format-AniEtiketliMetin ([string]($(if ($_.icerik) { $_.icerik } else { $_.not }))) }) -join '; '
        Send-Cevap "Anı kütüphanesinde $($anilar.Count) kayıt var. Son anılar: $ozet"
        return $true
    }
    if ($Soru -match '(?i)^(unutma|hatırla|hatirla|kaydet|not al)\s*[:,-]?\s*(.+)$') {
        $icerik = Format-AniEtiketliMetin $Matches[2].Trim()
        Write-GunlukBellek -Tur 'ANI_NOT' -Metin $icerik
        if (Add-AniKutuphanesine -Metin $icerik -Kategori 'kaptan_notu' -KaynakGun (Get-Date).ToString('yyyy-MM-dd')) {
            Send-Cevap "Anlaşıldı, bunu anı kütüphanesine kalıcı olarak ekledim: $icerik"
        } else {
            Send-Cevap 'Bu bilgi zaten anı kütüphanesinde kayıtlı.'
        }
        return $true
    }
    return $false
}

function Test-SecimCevabi([string]$Soru, $Tel) {
    if (-not $Script:BekleyenSecim) { return $false }
    $sec = $Script:BekleyenSecim
    if (((Get-NowMs) - $sec.Zaman) -gt 45000) {
        $Script:BekleyenSecim = $null
        return $false
    }
    $n = ConvertTo-Norm $Soru
    $nClean = $n.Replace('ş','s').Replace('ğ','g').Replace('ü','u').Replace('ö','o').Replace('ç','c').Replace('ı','i')

    if ($nClean -match '\b(durum|rapor|iptal|vazgec)\b') {
        $Script:BekleyenSecim = $null
        if ($nClean -match '\b(iptal|vazgec)\b') {
            Send-Cevap 'Seçim iptal edildi.'
            return $true
        }
        return $false
    }

    if ($nClean -match '^(ikisi de|ikiside|ikisinide|ikisini de|hepsi|hepsini|tumu|tumunu)$') {
        $Script:BekleyenSecim = $null
        for ($i = 0; $i -lt $sec.AdayIdler.Count; $i++) {
            $hedefId = [string]$sec.AdayIdler[$i]
            Write-AtlasLog 'HAFIZA' "Coklu secim tamamlandi: $($sec.Aksiyon) $hedefId"
            $jk = [pscustomobject]@{ niyet = 'komut'; aksiyon = $sec.Aksiyon; hedef_id = $hedefId; yanit = '' }
            Invoke-Karar $jk $Tel
        }
        return $true
    }

    $q = @(Get-Jetonlar $Soru | Select-Object -Unique)
    $eslesenIdler = @()
    for ($i = 0; $i -lt $sec.AdayIdler.Count; $i++) {
        $adayAd = [string]$sec.AdayAdlar[$i]
        $adayClean = (ConvertTo-Norm $adayAd).Replace('ş','s').Replace('ğ','g').Replace('ü','u').Replace('ö','o').Replace('ç','c').Replace('ı','i')
        $eslesti = $false
        if ($adayClean -and ($nClean.Contains($adayClean) -or $adayClean.Contains($nClean))) {
            $eslesti = $true
        } elseif ($q.Count -gt 0) {
            $aJeton = @(Get-Jetonlar $adayAd)
            foreach ($t in $q) { if ($aJeton -contains $t) { $eslesti = $true; break } }
        }
        if ($eslesti) { $eslesenIdler += [string]$sec.AdayIdler[$i] }
    }

    $eslesenIdler = @($eslesenIdler | Select-Object -Unique)
    if ($eslesenIdler.Count -eq 1) {
        $Script:BekleyenSecim = $null
        $hedefId = [string]$eslesenIdler[0]
        Write-AtlasLog 'HAFIZA' "Belirsiz secim tamamlandi: $($sec.Aksiyon) $hedefId"
        $jk = [pscustomobject]@{ niyet = 'komut'; aksiyon = $sec.Aksiyon; hedef_id = $hedefId; yanit = '' }
        Invoke-Karar $jk $Tel
        return $true
    }
    return $false
}