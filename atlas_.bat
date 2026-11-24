@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

set "KOK_YOL=C:\SE_Kopru"
set "SAHTE_OYUN=%KOK_YOL%\araclar\atlas_sahte_oyun.ps1"
set "IZLEYICI=%KOK_YOL%\atlas_izleyici.ps1"

if /I "%~1"=="restart" goto :YENIDEN_BASLAT
if /I "%~1"=="yeniden" goto :YENIDEN_BASLAT
if /I "%~1"=="stop"    goto :DURDUR

:MENU
cls
echo ============================================================
echo  ATLAS - SAHTE OYUN VE IZLEYICI YONETICISI
echo ============================================================
echo  [1] Ikisini de Baslat
echo  [2] Ikisini de Yeniden Baslat
echo  [3] Ikisini de Durdur
echo  [4] Cikis
echo ============================================================
choice /C 1234 /N /M "Seciminiz [1-4]: "

if errorlevel 4 goto :SON
if errorlevel 3 goto :DURDUR
if errorlevel 2 goto :YENIDEN_BASLAT
if errorlevel 1 goto :BASLAT

:BASLAT
call :DURDUR_SESSIZ

if not exist "%SAHTE_OYUN%" (
    echo [HATA] Bulunamadi: %SAHTE_OYUN%
    pause
    goto :MENU
)
if not exist "%IZLEYICI%" (
    echo [HATA] Bulunamadi: %IZLEYICI%
    pause
    goto :MENU
)

echo [INFO] Sahte oyun simulatoru baslatiliyor...
start "ATLAS - Sahte Oyun" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SAHTE_OYUN%"

timeout /t 1 /nobreak >nul

echo [INFO] Atlas izleyici baslatiliyor...
start "ATLAS - Izleyici" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%IZLEYICI%"

echo [OK] Her iki servis baslatildi.
timeout /t 2 /nobreak >nul
goto :MENU

:YENIDEN_BASLAT
echo [INFO] Servisler yeniden baslatiliyor...
call :DURDUR_SESSIZ
timeout /t 1 /nobreak >nul
goto :BASLAT

:DURDUR
call :DURDUR_SESSIZ
echo [OK] Sahte oyun ve Atlas izleyici durduruldu.
timeout /t 2 /nobreak >nul
goto :MENU

:DURDUR_SESSIZ
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$targets = @('atlas_sahte_oyun.ps1', 'atlas_izleyici.ps1');" ^
  "$procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^powershell(\.exe)?$|^pwsh(\.exe)?$' -and $_.CommandLine };" ^
  "foreach ($p in $procs) {" ^
  "  foreach ($t in $targets) {" ^
  "    if ($p.CommandLine -match [regex]::Escape($t)) {" ^
  "      Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue" ^
  "    }" ^
  "  }" ^
  "}" >nul 2>&1
exit /b 0

:SON
endlocal
exit /b 0