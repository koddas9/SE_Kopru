# Depoyu temizler: .gitignore'a uyan dosyalari izlemeden cikarir ve
# gecmisi TEK temiz commit'e indirir (Pulsar ~48 MB gecmisten de silinir).
# Calistir: C:\SE_Kopru icinde, Windows PowerShell'de:  .\temizle.ps1
# Yerel dosyalarin SILINMEZ; yalnizca git'ten cikar.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path .gitignore)) { throw '.gitignore yok, once onu ekle.' }

git checkout --orphan temiz
git rm -r --cached . -q
git add .
git status --short | Select-Object -First 40
Write-Host "`nYukaridaki liste yeni commit'e girecek. Devam icin Enter, iptal icin Ctrl+C"
Read-Host | Out-Null

git commit -m "Depo temizligi: Pulsar, loglar ve calisma verisi cikarildi"
git branch -M main
git push --force origin main
Write-Host 'Bitti. Eski gecmis kaldirildi.'
