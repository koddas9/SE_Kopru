// ============================================================
// ATLAS - PARCA 4: PULSAR EKLENTISI (Atlas.cs)
// Konum: C:\SE_Kopru\AtlasPlugin\Atlas.cs   (klasorde BASKA .cs dosyasi olmasin!)
//
// Gorevleri:
//   1) Oyuncunun sohbetinde "atlas ..." ile baslayan satirlari sohbet.txt'ye yazar
//   2) cevap.txt'ye eklenen satirlari oyun sohbetinde gosterir
//   3) komut.txt'deki komutu (id|ms|AKSIYON|hedef) uygulayip sonucu telemetriye yazar
//   4) Her ~2 sn telemetri.txt yazar (protokol: atlas_dogrulama.ps1 basligi)
// Guvenlik: yalnizca DURUM, AC, KAPAT, BAGLANTI_KES; yalnizca oyuncunun gemisindeki bloklar.
// ============================================================
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Sandbox.ModAPI;
using VRage.Game.ModAPI;
using VRage.ModAPI;
using VRage.Plugins;
using VRageMath;
using Ingame = Sandbox.ModAPI.Ingame;

namespace AtlasKopru
{
    public class AtlasPlugin : IPlugin
    {
        const string Kok = @"C:\SE_Kopru\";
        const string SohbetDosya = Kok + "sohbet.txt";
        const string CevapDosya = Kok + "cevap.txt";
        const string KomutDosya = Kok + "komut.txt";
        const string TelDosya = Kok + "telemetri.txt";
        const string HataLog = Kok + "atlas_eklenti.log";
        const string OzetDosya = Kok + "pb_ozet.txt";

        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        bool baglandi;
        long cevapOfset = -1;
        string sonKomutId = "";
        string sonSonuc = "";
        int sonKomutTick, sonTelTick, sonHataTick;
        IMyCubeGrid sonGrid;
        int sonGridTick;
        bool telZorla;
        string sonOzet = "";
        bool ozetIlk = true;

        static long NowMs() { return (long)(DateTime.UtcNow - Epoch).TotalMilliseconds; }
        static int Tick() { return Environment.TickCount; }

        public void Init(object gameInstance) { }

        public void Dispose()
        {
            try
            {
                if (baglandi && MyAPIGateway.Utilities != null)
                    MyAPIGateway.Utilities.MessageEntered -= OnMesaj;
            }
            catch (Exception) { }
            baglandi = false;
        }

        public void Update()
        {
            try
            {
                if (MyAPIGateway.Session == null || MyAPIGateway.Utilities == null) { baglandi = false; return; }
                if (!baglandi)
                {
                    MyAPIGateway.Utilities.MessageEntered += OnMesaj;
                    baglandi = true;
                    cevapOfset = -1;     // eski cevaplari gostermemek icin ofseti yeniden al
                    sonGrid = null;
                    ozetIlk = true;
                }
                int t = Tick();
                if (t - sonKomutTick > 250) { sonKomutTick = t; CevapOku(); KomutIsle(); PbIlet(); }
                if (telZorla || t - sonTelTick > 2000) { sonTelTick = t; telZorla = false; TelemetriYaz(); }
            }
            catch (Exception e) { HataYaz(e); }
        }

        // ---------------- 1) Sohbet yakalama ----------------
        void OnMesaj(string metin, ref bool baskasinaGonder)
        {
            try
            {
                if (string.IsNullOrEmpty(metin)) return;
                string m = metin.Trim();
                if (m.StartsWith("[ATLAS]", StringComparison.OrdinalIgnoreCase)) return;
                // Turkce I/i farki icin normalize: yalnizca "atlas" ile baslayanlar
                string n = m.Replace('\u0130', 'i').Replace('\u0131', 'i').ToLowerInvariant();
                if (!n.StartsWith("atlas")) return;
                m = m.Replace("\r", " ").Replace("\n", " ");
                string satir = NowMs().ToString() + "-" + (Environment.TickCount & 0xFFFF).ToString()
                               + "|" + NowMs().ToString() + "|" + m + "\r\n";
                Ekle(SohbetDosya, satir);
            }
            catch (Exception e) { HataYaz(e); }
        }

        // ---------------- 2) Cevap gosterme ----------------
        void CevapOku()
        {
            if (!File.Exists(CevapDosya)) { cevapOfset = 0; return; }
            using (var fs = new FileStream(CevapDosya, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                long len = fs.Length;
                if (cevapOfset < 0) { cevapOfset = len; return; }   // ilk acilis: eskileri atla
                if (len < cevapOfset) cevapOfset = 0;               // dosya sifirlandi
                if (len == cevapOfset) return;
                fs.Position = cevapOfset;
                byte[] buf = new byte[len - cevapOfset];
                int n = fs.Read(buf, 0, buf.Length);
                int son = Array.LastIndexOf(buf, (byte)10, n - 1);
                if (son < 0) return;                                 // tam satir yok
                cevapOfset += son + 1;
                string metin = Utf8.GetString(buf, 0, son + 1);
                foreach (string satir in metin.Split('\n'))
                {
                    string s = satir.Trim();
                    int bar = s.IndexOf('|');
                    if (bar < 0) continue;
                    string msj = s.Substring(bar + 1);
                    if (msj.StartsWith("[ATLAS] ")) msj = msj.Substring(8);
                    if (msj.Length > 0) MyAPIGateway.Utilities.ShowMessage("Atlas", msj);
                }
            }
        }

        // ---------------- 3) Komut isleme ----------------
        void KomutIsle()
        {
            if (!File.Exists(KomutDosya)) return;
            string ham = OkuGuvenli(KomutDosya);
            if (string.IsNullOrWhiteSpace(ham)) return;
            string[] p = ham.Trim().Split('|');
            if (p.Length < 4) return;
            string id = p[0].Trim();
            if (id == sonKomutId) return;
            long ms;
            if (!long.TryParse(p[1], out ms)) return;
            if (NowMs() - ms > 60000) { sonKomutId = id; return; }   // bayat komut
            string aksiyon = p[2].Trim().ToUpperInvariant();
            string hedef = p[3].Trim();

            string sonuc;
            try { sonuc = Uygula(aksiyon, hedef); }
            catch (Exception e) { sonuc = "HATA:istisna"; HataYaz(e); }

            sonKomutId = id;
            sonSonuc = sonuc;
            telZorla = true;
        }

        string Uygula(string aksiyon, string hedef)
        {
            List<IMyCubeGrid> gridler = GridleriBul();
            if (gridler.Count == 0) return "HATA:gemi bulunamadi";
            switch (aksiyon)
            {
                case "DURUM":
                    return "OK";
                case "AC":
                case "KAPAT":
                    {
                        long eid;
                        if (!long.TryParse(hedef, out eid)) return "HATA:gecersiz hedef";
                        IMyEntity ent;
                        if (!MyAPIGateway.Entities.TryGetEntityById(eid, out ent) || ent == null) return "HATA:blok yok";
                        var cb = ent as IMyCubeBlock;
                        if (cb == null || !gridler.Contains(cb.CubeGrid)) return "HATA:blok bu gemide degil";
                        var fb = ent as Ingame.IMyFunctionalBlock;
                        if (fb == null) return "HATA:acilip kapanamaz";
                        fb.Enabled = (aksiyon == "AC");
                        return "OK";
                    }
                case "BAGLANTI_KES":
                    {
                        int adet = 0;
                        foreach (var fat in FatBloklar(gridler))
                        {
                            var c = fat as Ingame.IMyShipConnector;
                            if (c != null && c.Status == Ingame.MyShipConnectorStatus.Connected) { c.Disconnect(); adet++; }
                        }
                        return adet > 0 ? "OK" : "HATA:bagli konnektor yok";
                    }
                default:
                    return "HATA:izinsiz aksiyon";
            }
        }

        // ---------------- 3b) PB'ye ozet iletme ----------------
        // pb_ozet.txt degisince "Atlas" adli Programmable Block'u "ozet <metin>" argumaniyla calistirir.
        void PbIlet()
        {
            if (!File.Exists(OzetDosya)) return;
            string ham = OkuGuvenli(OzetDosya);
            if (string.IsNullOrWhiteSpace(ham)) return;
            ham = ham.Trim();
            string anahtar = ham + "@" + File.GetLastWriteTimeUtc(OzetDosya).Ticks;
            if (ozetIlk) { ozetIlk = false; sonOzet = anahtar; return; }    // eski ozeti tekrar gonderme
            if (anahtar == sonOzet) return;
            List<IMyCubeGrid> gridler = GridleriBul();
            if (gridler.Count == 0) return;
            foreach (var fat in FatBloklar(gridler))
            {
                var pb = fat as Ingame.IMyProgrammableBlock;
                var tb = fat as Ingame.IMyTerminalBlock;
                if (pb != null && tb != null && tb.CustomName.IndexOf("Atlas", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    pb.TryRun(ham);
                    break;
                }
            }
            sonOzet = anahtar;
        }

        // ---------------- 4) Telemetri ----------------
        void TelemetriYaz()
        {
            List<IMyCubeGrid> gridler = GridleriBul();
            IMyCubeGrid grid = gridler.Count > 0 ? gridler[0] : null;
            var sb = new StringBuilder();
            sb.Append("zaman_ms=").Append(NowMs()).Append("\r\n");
            sb.Append("son_komut_id=").Append(sonKomutId).Append("\r\n");
            sb.Append("son_komut_sonuc=").Append(sonSonuc).Append("\r\n");
            if (grid == null)
            {
                sb.Append("grid_adi=yok\r\n");
            }
            else
            {
                double depo = 0, maks = 0, guc = 0, h2 = 0, o2 = 0;
                int h2n = 0, o2n = 0, toplam = 0, listelenen = 0;
                var bloklar = new StringBuilder();
                foreach (var fat in FatBloklar(gridler))
                {
                    toplam++;
                    var bat = fat as Ingame.IMyBatteryBlock;
                    if (bat != null) { depo += bat.CurrentStoredPower; maks += bat.MaxStoredPower; }
                    var pp = fat as Ingame.IMyPowerProducer;
                    if (pp != null) guc += pp.CurrentOutput;
                    var tank = fat as Ingame.IMyGasTank;
                    if (tank != null)
                    {
                        string alt = ((IMyCubeBlock)fat).BlockDefinition.SubtypeName ?? "";
                        if (alt.IndexOf("Hydrogen", StringComparison.OrdinalIgnoreCase) >= 0) { h2 += tank.FilledRatio; h2n++; }
                        else { o2 += tank.FilledRatio; o2n++; }
                    }
                    var fb = fat as Ingame.IMyFunctionalBlock;
                    var tb = fat as Ingame.IMyTerminalBlock;
                    if (fb != null && tb != null && listelenen < 300)
                    {
                        listelenen++;
                        string ad = Temiz(tb.CustomName);
                        string tip = Temiz(((IMyCubeBlock)fat).BlockDefinition.TypeIdString.Replace("MyObjectBuilder_", ""));
                        bloklar.Append("blok.").Append(tb.EntityId).Append('=')
                               .Append(ad).Append('|').Append(tip).Append('|')
                               .Append(fb.Enabled ? "acik" : "kapali").Append("\r\n");
                    }
                }
                sb.Append("grid_adi=").Append(Temiz(grid.DisplayName)).Append("\r\n");
                sb.Append("blok_sayisi=").Append(toplam).Append("\r\n");
                sb.Append("alt_grid_sayisi=").Append(gridler.Count - 1).Append("\r\n");
                sb.Append(HasarMetni(gridler));
                if (maks > 0) sb.Append("batarya_yuzde=").Append((int)Math.Round(100.0 * depo / maks)).Append("\r\n");
                sb.Append("guc_mw=").Append(Math.Round(guc, 2).ToString(System.Globalization.CultureInfo.InvariantCulture)).Append("\r\n");
                if (h2n > 0) sb.Append("hidrojen_yuzde=").Append((int)Math.Round(100.0 * h2 / h2n)).Append("\r\n");
                if (o2n > 0) sb.Append("oksijen_yuzde=").Append((int)Math.Round(100.0 * o2 / o2n)).Append("\r\n");
                sb.Append(bloklar.ToString());
            }
            AtomikYaz(TelDosya, sb.ToString());
        }

        // ---------------- Yardimcilar ----------------
        static string Temiz(string s)
        {
            if (s == null) return "";
            return s.Replace(";", ",").Replace("|", "/").Replace("\r", " ").Replace("\n", " ").Trim();
        }

        IEnumerable<IMyCubeBlock> FatBloklar(IMyCubeGrid grid)
        {
            var liste = new List<IMySlimBlock>();
            grid.GetBlocks(liste);
            foreach (var sb in liste)
                if (sb.FatBlock != null) yield return sb.FatBlock;
        }

        // Ana gemi + mekanik bagli alt gemiler (piston/rotor/suspansiyon)
        List<IMyCubeGrid> GridleriBul()
        {
            var liste = new List<IMyCubeGrid>();
            IMyCubeGrid ana = GridBul();
            if (ana == null) return liste;
            liste.Add(ana);
            try
            {
                IMyGridGroupData grup = MyAPIGateway.GridGroups.GetGridGroup(GridLinkTypeEnum.Mechanical, ana);
                if (grup != null)
                {
                    var tum = new List<IMyCubeGrid>();
                    grup.GetGrids(tum);
                    foreach (var g in tum)
                        if (g != null && !liste.Contains(g)) liste.Add(g);
                }
            }
            catch (Exception) { }
            return liste;
        }

        IEnumerable<IMyCubeBlock> FatBloklar(List<IMyCubeGrid> gridler)
        {
            foreach (var g in gridler)
                foreach (var fat in FatBloklar(g))
                    yield return fat;
        }

        // Hasar taramasi (5 sn onbellekli): hasarli blok sayisi, calismayan blok, en kotu blok
        string hasarOnbellek = "";
        int hasarTick = -100000;
        string HasarMetni(List<IMyCubeGrid> gridler)
        {
            int t = Tick();
            if (t - hasarTick < 5000) return hasarOnbellek;
            hasarTick = t;
            int hasarli = 0, calismayan = 0;
            float enKotu = 0f;
            string enKotuAd = "";
            var liste = new List<IMySlimBlock>();
            foreach (var g in gridler)
            {
                liste.Clear();
                g.GetBlocks(liste);
                foreach (var blok in liste)
                {
                    if (blok == null) continue;
                    float mx = blok.MaxIntegrity;
                    if (mx <= 0f) continue;
                    float oran = blok.CurrentDamage / mx;
                    var fat = blok.FatBlock;
                    if (fat != null && !fat.IsFunctional) calismayan++;
                    if (oran > 0.05f)
                    {
                        hasarli++;
                        if (oran > enKotu)
                        {
                            enKotu = oran;
                            var tb = fat as Ingame.IMyTerminalBlock;
                            enKotuAd = tb != null ? Temiz(tb.CustomName) : "Zirh blogu";
                        }
                    }
                }
            }
            var b = new StringBuilder();
            b.Append("hasarli_sayisi=").Append(hasarli).Append("\r\n");
            b.Append("calismayan_blok=").Append(calismayan).Append("\r\n");
            if (hasarli > 0)
            {
                b.Append("en_hasar_yuzde=").Append((int)Math.Round(enKotu * 100f)).Append("\r\n");
                b.Append("en_hasar_adi=").Append(enKotuAd).Append("\r\n");
            }
            hasarOnbellek = b.ToString();
            return hasarOnbellek;
        }

        // Oyuncu oturuyorsa o gemi; degilse oyuncuya en yakin, oyuncunun sahip oldugu gemi.
        IMyCubeGrid GridBul()
        {
            var oyun = MyAPIGateway.Session;
            if (oyun == null || oyun.Player == null) return sonGrid;

            var koltuk = oyun.ControlledObject as IMyCubeBlock;
            if (koltuk != null && koltuk.CubeGrid != null)
            {
                sonGrid = koltuk.CubeGrid;
                sonGridTick = Tick();
                return sonGrid;
            }
            if (sonGrid != null && !sonGrid.MarkedForClose && Tick() - sonGridTick < 10000) return sonGrid;

            var karakter = oyun.Player.Character;
            if (karakter == null) return sonGrid;
            Vector3D konum = karakter.GetPosition();
            long kimlik = oyun.Player.IdentityId;

            var kume = new HashSet<IMyEntity>();
            MyAPIGateway.Entities.GetEntities(kume, e => e is IMyCubeGrid);
            IMyCubeGrid enIyi = null;
            double enKisa = double.MaxValue;
            foreach (var e in kume)
            {
                var g = e as IMyCubeGrid;
                if (g == null || g.MarkedForClose) continue;
                if (!g.BigOwners.Contains(kimlik)) continue;
                double d = Vector3D.DistanceSquared(konum, g.GetPosition());
                if (d < enKisa) { enKisa = d; enIyi = g; }
            }
            sonGrid = enIyi;
            sonGridTick = Tick();
            return sonGrid;
        }

        static string OkuGuvenli(string yol)
        {
            try
            {
                using (var fs = new FileStream(yol, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var sr = new StreamReader(fs, Utf8))
                    return sr.ReadToEnd();
            }
            catch (IOException) { return null; }
        }

        static void Ekle(string yol, string metin)
        {
            using (var fs = new FileStream(yol, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            {
                byte[] b = Utf8.GetBytes(metin);
                fs.Write(b, 0, b.Length);
            }
        }

        static void AtomikYaz(string yol, string icerik)
        {
            string tmp = yol + ".tmp";
            try
            {
                File.WriteAllText(tmp, icerik, Utf8);
                if (File.Exists(yol)) File.Replace(tmp, yol, null);
                else File.Move(tmp, yol);
            }
            catch (IOException) { /* okuyucu dosyayi tutuyor; sonraki turda tekrar */ }
        }

        void HataYaz(Exception e)
        {
            int t = Tick();
            if (t - sonHataTick < 5000) return;     // log spam korumasi
            sonHataTick = t;
            try { File.AppendAllText(HataLog, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + e + "\r\n", Utf8); }
            catch (Exception) { }
        }
    }
}
