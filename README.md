# Atlas — Space Engineers Yapay Zeka Yardımcısı

Atlas, Space Engineers oyunundaki sohbet ve gemi telemetrisini yerel Ollama modeliyle (`127.0.0.1:11434`) buluşturan bir köprü ve yardımcı sistemdir. Oyuncunun yazdığı `atlas ...` mesajlarını okuyup yanıt üretir ve gerekli durumlarda gemi bloklarına yönelik komutlar oluşturur. Windows 11 ve Windows PowerShell 5.1 üzerinde `C:\SE_Kopru\` klasöründeki metin dosyaları üzerinden haberleşir.

## Mimari Şeması

```text
[Space Engineers / Eklenti]
       |  (sohbet.txt, telemetri.txt, pb_ozet.txt)
       v
[C:\SE_Kopru\ Dosya Protokolu] <----> [PowerShell Betikleri (5.1)]
       ^                                       |
       |  (cevap.txt, komut.txt, atlas.log)    v
       +------------------------------ [Ollama (127.0.0.1:11434)]