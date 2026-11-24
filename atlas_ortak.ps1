# ============================================================
# ATLAS - PARCA 1: ORTAK MODUL (atlas_ortak.ps1)
# Konum: C:\SE_Kopru\atlas_ortak.ps1
# Kullanim (diger betiklerin basinda):  . "$PSScriptRoot\atlas_ortak.ps1"
#
# PROTOKOL (tum parcalar buna uyar)
#   komut.txt     : id|unix_ms|AKSIYON|hedef_id        (tek satir)
#   telemetri.txt : son_komut_id=...; zaman_ms=...; ... (anahtar=deger; satirlari)
#   pb_ozet.txt   : PB Echo ekranina gidecek kisa metin
#   islenen.log   : islenen komut ID'leri (tekrar korumasi)
#   Atlas'in sohbet ciktilari "[ATLAS]" ile baslar, girdi olarak yok sayilir.
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$Script:Kok   = 'C:\SE_Kopru'
$Script:Utf8  = New-Object System.Text.UTF8Encoding($false)   # BOM'suz
$Script:Cfg = @{
    Komut      = Join-Path $Script:Kok 'komut.txt'
    Telemetri  = Join-Path $Script:Kok 'telemetri.txt'
    Ozet       = Join-Path $Script:Kok 'pb_ozet.txt'
    Islenen    = Join-Path $Script:Kok 'islenen.log'
    Log        = Join-Path $Script:Kok 'atlas.log'
    LogMaxMB   = 5
    TelMaxYasMs= 5000      # bundan eski telemetri "bayat" sayilir
    KomutMaxYasMs = 60000  # bundan eski komut atilir
    OllamaUrl  = 'http://127.0.0.1:11434'
    Model      = 'gemma4:e2b'   # kendi modelinle degistir
}

function Get-NowMs { [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }

# --- Tek ornek korumasi: False donerse cik ---
function Enter-AtlasMutex {
    $Script:Mutex = New-Object System.Threading.Mutex($false, 'Global\AtlasIzleyici')
    return $Script:Mutex.WaitOne(0)
}

# --- Log (boyut rotasyonlu) ---
function Write-AtlasLog([string]$Seviye, [string]$Mesaj) {
    try {
        $f = $Script:Cfg.Log
        if ((Test-Path -LiteralPath $f) -and ((Get-Item -LiteralPath $f).Length -gt ($Script:Cfg.LogMaxMB * 1MB))) {
            Move-Item -LiteralPath $f -Destination ($f + '.old') -Force
        }
        $satir = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Seviye, $Mesaj
        [System.IO.File]::AppendAllText($f, $satir + "`r`n", $Script:Utf8)
    } catch { }   # log hatasi asla programi durdurmasin
}

# --- Guvenli okuma: oyun yazarken kilitlenmesin, 3 deneme ---
function Read-SafeFile([string]$Yol) {
    if (-not (Test-Path -LiteralPath $Yol)) { return $null }
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $fs = [System.IO.File]::Open($Yol, 'Open', 'Read', 'ReadWrite')
            try {
                $sr = New-Object System.IO.StreamReader($fs, $Script:Utf8)
                return $sr.ReadToEnd()
            } finally { $fs.Dispose() }
        } catch { Start-Sleep -Milliseconds 50 }
    }
    return $null
}

# --- Atomik yazma: gecici dosyaya yaz, sonra yer degistir ---
function Write-AtomicFile([string]$Yol, [string]$Icerik) {
    $tmp = $Yol + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $Icerik, $Script:Utf8)
    Move-Item -LiteralPath $tmp -Destination $Yol -Force
}

# --- Komut kimligi ---
function New-KomutId { '{0}-{1}' -f (Get-NowMs), (Get-Random -Maximum 9999) }

# --- Islenen komut kaydi (tekrar korumasi) ---
function Test-KomutIslendi([string]$Id) {
    $t = Read-SafeFile $Script:Cfg.Islenen
    if (-not $t) { return $false }
    return ($t -split "`r?`n") -contains $Id
}
function Add-KomutIslendi([string]$Id) {
    [System.IO.File]::AppendAllText($Script:Cfg.Islenen, $Id + "`r`n", $Script:Utf8)
    # son 500 kaydi tut
    $s = @((Read-SafeFile $Script:Cfg.Islenen) -split "`r?`n" | Where-Object { $_ })
    if ($s.Count -gt 500) { Write-AtomicFile $Script:Cfg.Islenen (($s | Select-Object -Last 300) -join "`r`n") }
}

# --- Telemetri: "anahtar=deger;" satirlarini hashtable'a cevirir ---
function Get-Telemetri {
    $t = Read-SafeFile $Script:Cfg.Telemetri
    if (-not $t) { return $null }
    $h = @{}
    foreach ($par in ($t -split "[;\r\n]+")) {
        $i = $par.IndexOf('=')
        if ($i -gt 0) { $h[$par.Substring(0,$i).Trim()] = $par.Substring($i+1).Trim() }
    }
    return $h
}
function Test-TelemetriTaze($Tel) {
    if (-not $Tel -or -not $Tel.ContainsKey('zaman_ms')) { return $false }
    $yas = (Get-NowMs) - [int64]$Tel['zaman_ms']
    return ($yas -ge 0 -and $yas -le $Script:Cfg.TelMaxYasMs)
}

# --- Sohbet metni normalizasyonu (Turkce I/i sorunu icin) ---
function ConvertTo-Norm([string]$s) {
    if (-not $s) { return '' }
    $s = $s.Replace([char]0x0130,'i').Replace([char]0x0131,'i')   # İ ı -> i
    return $s.ToLowerInvariant().Trim()
}

# --- Atlas'a hitap mi? "atlas", "atlas:", "atlas," ... ---
function Test-AtlasHitap([string]$Satir) {
    $n = ConvertTo-Norm $Satir
    if ($n.StartsWith('[atlas]')) { return $false }     # kendi ciktisi
    return ($n -match '^atlas\b[\s:,!\.]*')
}
function Remove-AtlasHitap([string]$Satir) {
    return ($Satir -replace '(?i)^\s*atlas\b[\s:,!\.]*', '').Trim()
}
