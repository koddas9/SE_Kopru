# ============================================================
# ATLAS - PARCA 3: TELEMETRI DOGRULAMA + PB OZET (atlas_dogrulama.ps1)
# Konum: C:\SE_Kopru\atlas_dogrulama.ps1
# atlas_izleyici.ps1 bu dosyayi otomatik yukler; ayrica calistirilmaz.
#
# TELEMETRI PROTOKOLU (Parca 4 eklentisi bunu yazacak)
#   zaman_ms=<unix_ms>              her yazimda guncel zaman
#   son_komut_id=<id>               eklentinin en son isledigi komut
#   son_komut_sonuc=OK | HATA:<neden>
#   blok.<entityId>=<ad>|<tip>|<acik|kapali>
#   batarya_yuzde, guc_mw, hidrojen_yuzde, oksijen_yuzde, blok_sayisi  (opsiyonel)
#
# PB OZET PROTOKOLU
#   pb_ozet.txt : "ozet <kisa metin>"  (en fazla ~120 karakter, PB Echo'da gosterir)
# ============================================================

$Script:DogrulamaBeklemeMs = 6000
$Script:DogrulamaDeneme    = 2          # ilk deneme + 1 tekrar

function Send-PbOzet([string]$Metin) {
    $m = ($Metin -replace '[\r\n]+', ' ').Trim()
    if ($m.Length -gt 120) { $m = $m.Substring(0, 117) + '...' }
    $Script:SonOzet = $m
    try { Write-AtomicFile $Script:Cfg.Ozet ('ozet ' + $m) }
    catch { Write-AtlasLog 'WARN' "pb_ozet yazilamadi: $($_.Exception.Message)" }
}

function Get-DurumOzeti($Tel) {
    $etiket = [ordered]@{
        batarya_yuzde  = 'Batarya %{0}'
        guc_mw         = 'Güç {0} MW'
        hidrojen_yuzde = 'Hidrojen %{0}'
        oksijen_yuzde  = 'Oksijen %{0}'
        blok_sayisi    = '{0} blok'
        alt_grid_sayisi = '{0} alt gemi'
        hasarli_sayisi = '{0} hasarlı blok'
    }
    $parca = @()
    foreach ($k in $etiket.Keys) {
        if ($Tel.ContainsKey($k) -and $Tel[$k] -and -not (($k -in @('alt_grid_sayisi','hasarli_sayisi')) -and $Tel[$k] -eq '0')) {
            $parca += ($etiket[$k] -f $Tel[$k])
        }
    }
    if ($parca.Count -eq 0) { return 'Telemetri geldi ama durum alanı yok.' }
    return ($parca -join ', ') + '.'
}

# Komut sonrasi telemetriyi bekler, etkiyi dogrular, sonucu oyuna ve PB'ye bildirir.
function Wait-Dogrulama([string]$Id, [string]$Aksiyon, [string]$Hedef) {
    for ($deneme = 1; $deneme -le $Script:DogrulamaDeneme; $deneme++) {
        $bitis = (Get-NowMs) + $Script:DogrulamaBeklemeMs
        $tel = $null
        while ((Get-NowMs) -lt $bitis) {
            $t = Get-Telemetri
            if ((Test-TelemetriTaze $t) -and $t['son_komut_id'] -eq $Id) { $tel = $t; break }
            Start-Sleep -Milliseconds 300
        }

        if (-not $tel) {
            Write-AtlasLog 'DOGRULA' "$Id FAIL telemetri gelmedi (deneme $deneme)"
            if ($deneme -lt $Script:DogrulamaDeneme) { Start-Sleep -Milliseconds 500; continue }
            Send-Cevap 'Komutu gönderdim ama oyundan yanıt gelmedi. Eklenti çalışıyor mu?'
            Send-PbOzet "HATA: $Aksiyon yanitsiz"
            return
        }

        $sonuc = [string]$tel['son_komut_sonuc']
        if ($sonuc -like 'HATA*') {
            Write-AtlasLog 'DOGRULA' "$Id FAIL $sonuc"
            Send-Cevap "İşlem başarısız oldu: $($sonuc.Substring([Math]::Min(5,$sonuc.Length)))"
            Send-PbOzet "HATA: $Aksiyon $sonuc"
            return                       # eklenti acikca hata verdiyse tekrar deneme
        }

        # Etki dogrulamasi
        switch ($Aksiyon) {
            'DURUM' {
                $o = Get-DurumOzeti $tel
                Write-AtlasLog 'DOGRULA' "$Id OK DURUM"
                Send-Cevap $o; Send-PbOzet $o; return
            }
            { $_ -in @('AC','KAPAT') } {
                $durum = ((Get-BlokAdi $tel $Hedef) -split '\|')[-1].Trim().ToLowerInvariant()
                $beklenen = if ($Aksiyon -eq 'AC') { 'acik' } else { 'kapali' }
                $ad = ((Get-BlokAdi $tel $Hedef) -split '\|')[0]
                if ($durum -eq $beklenen) {
                    $m = if ($Aksiyon -eq 'AC') { "$ad açıldı." } else { "$ad kapatıldı." }
                    Write-AtlasLog 'DOGRULA' "$Id OK $Aksiyon $Hedef"
                    Send-Cevap "Doğrulandı: $m"; Send-PbOzet "OK: $m"; return
                }
                Write-AtlasLog 'DOGRULA' "$Id FAIL beklenen=$beklenen gercek=$durum (deneme $deneme)"
                if ($deneme -lt $Script:DogrulamaDeneme) {
                    # Self-healing: bir kez yeni ID ile tekrar gonder
                    $Id = New-KomutId
                    Write-AtomicFile $Script:Cfg.Komut ('{0}|{1}|{2}|{3}' -f $Id, (Get-NowMs), $Aksiyon, $Hedef)
                    Write-AtlasLog 'KOMUT' "tekrar $Id $Aksiyon $Hedef"
                    continue
                }
                Send-Cevap "$ad istediğim duruma gelmedi (şu an: $durum). Başka bir sistem engelliyor olabilir."
                Send-PbOzet "HATA: $ad $durum"
                return
            }
            'BATARYA_MOD' {
                $hp = $Hedef -split ':'
                $say = 0; $uyan = 0
                foreach ($k in $tel.Keys) {
                    if ($k -notlike 'bmod.*') { continue }
                    if ($hp[0] -ne '0' -and $k -ne "bmod.$($hp[0])") { continue }
                    $say++; if ($tel[$k] -eq $hp[1]) { $uyan++ }
                }
                $modTr = switch ($hp[1]) { 'Auto' { 'otomatik' } 'Recharge' { 'şarj' } 'Discharge' { 'deşarj' } default { $hp[1] } }
                if ($say -gt 0 -and $uyan -eq $say) {
                    Write-AtlasLog 'DOGRULA' "$Id OK BATARYA_MOD $Hedef"
                    Send-Cevap "Doğrulandı: $say batarya $modTr moduna alındı."; Send-PbOzet "OK: $say batarya $modTr"; return
                }
                Write-AtlasLog 'DOGRULA' "$Id FAIL BATARYA_MOD $Hedef uyan=$uyan/$say"
                Send-Cevap "Batarya modu tam değişmedi ($uyan/$say $modTr modunda)."; Send-PbOzet "HATA: batarya mod $uyan/$say"; return
            }
            default {
                Write-AtlasLog 'DOGRULA' "$Id GONDERILDI $Aksiyon (etki dogrulanamadi)"
                Send-Cevap 'Komutu gönderdim, eklenti hata bildirmedi. Etkisini telemetriden doğrulayamıyorum.'; Send-PbOzet "GONDERILDI: $Aksiyon"; return
            }
        }
    }
}
