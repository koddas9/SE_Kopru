### `CHANGELOG.md`
```markdown
# Değişiklik Günlüğü (CHANGELOG)

## 0.1 temel köprü
- `C:\SE_Kopru\` üzerinden temel dosya tabanlı haberleşme protokolü oluşturuldu (`sohbet.txt`, `cevap.txt`, `komut.txt`, `telemetri.txt`).
- `atlas ...` ile başlayan sohbet girdilerini okuyup Ollama (`127.0.0.1:11434`) üzerinden yanıt üreten ilk köprü akışı kuruldu.
- `komut.txt` üzerinden `DURUM`, `AC`, `KAPAT` ve `BAGLANTI_KES` aksiyonlarının temel iletimi sağlandı.
- `telemetri.txt` için `.tmp` üzerinden atomik yazma yaklaşımı tanımlandı.

## 0.2 doğrulama ve rutinler
- Komut sonuçlarının `son_komut_id` ve `son_komut_sonuc` (`OK` / `HATA:<neden>`) alanlarıyla doğrulanması eklendi.
- `atlas.log` kaydı `GIRDI`, `CEVAP`, `KOMUT`, `DOGRULA`, `RED`, `WARN`, `ERR` etiketleriyle genişletildi.
- `pb_ozet.txt` (`ozet <metin>`) desteği ve periyodik/rutin kontrol adımları eklendi.
- Hatalı veya geçersiz durumlarda `RED` ve `HATA:` dönüşleriyle güvenli geri bildirim sağlandı.

## 0.3 sohbet/komut ayrımı ve kişilik
- Oyuncu girdilerinde sıradan sohbet ile gemi komutlarının ayrımı netleştirildi.
- Atlas'ın `[ATLAS]` önekiyle yanıt vermesi ve kendi mesajlarının tekrar girdi sayılmaması sağlandı.
- Türkçe metin işlemede `ToLowerInvariant()` uyumu ve sohbet üslubu iyileştirildi.
- `OGREN` log etiketiyle öğrenme/not kayıt akışı eklendi.

## 0.4 alt gemi ve hasar izleme
- Telemetri alanlarına `alt_grid_sayisi` eklenerek alt grid takibi getirildi.
- Hasar izleme için `hasarli_sayisi`, `en_hasar_yuzde` ve `en_hasar_adi` alanları eklendi.
- Çalışmayan blok sayacı (`calismayan_blok`) ve blok bazlı `blok.<entityId>=<ad>|<tip>|<acik veya kapali>` satırları genişletildi.
- Simülatör ve yardımcı araçlarla hasar ve telemetri senaryolarının test edilebilirliği artırıldı.