// ============================================================
// ATLAS - PARCA 4: PULSAR EKLENTISI (Atlas.cs)
// Konum: C:\SE_Kopru\AtlasPlugin\Atlas.cs
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
                    cevapOfset = -1;
                    sonGrid = null;
                    ozetIlk = true;
                }
                int t = Tick();
                if (t - sonKomutTick > 250) { sonKomutTick = t; CevapOku(); KomutIsle(); PbIlet(); }
                if (telZorla || t - sonTelTick > 2000) { sonTelTick = t; telZorla = false; TelemetriYaz(); }
            }
            catch (Exception e) { HataYaz(e); }
        }

        // ---------------- 1) Sohbet yakalama (tum oyuncu mesajlari) ----------------
        void OnMesaj(string metin, ref bool baskasinaGonder)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(metin)) return;
                string m = metin.Trim();
                if (m.StartsWith("[ATLAS]", StringComparison.OrdinalIgnoreCase)) return;
                if (m.StartsWith("/")) return; // oyun ici slash komutlarini atla
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
                if (cevapOfset < 0) { cevapOfset = len; return; }
                if (len < cevapOfset) cevapOfset = 0;
                if (len == cevapOfset) return;
                fs.Position = cevapOfset;
                byte[] buf = new byte[len - cevapOfset];
                int n = fs.Read(buf, 0, buf.Length);
                int son = Array.LastIndexOf(buf, (byte)10, n - 1);
                if (son < 0) return;
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
            if (NowMs() - ms > 60000) { sonKomutId = id; return; }
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
            IMyCubeGrid grid = GridBul();
            if (grid == null) return "HATA:gemi bulunamadi";
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
                        if (cb == null || cb.CubeGrid != grid) return "HATA:blok bu gemide degil";
                        var fb = ent as Ingame.IMyFunctionalBlock;
                        if (fb == null) return "HATA:acilip kapanamaz";
                        fb.Enabled = (aksiyon == "AC");
                        return "OK";
                    }
                case "BATARYA_MOD":
                    {
                        string[] h = hedef.Split(':');
                        if (h.Length != 2) return "HATA:gecersiz hedef";
                        string mod = h[1];
                        if (mod != "Auto" && mod != "Recharge" && mod != "Discharge") return "HATA:gecersiz mod";
                        long bid;
                        if (!long.TryParse(h[0], out bid)) return "HATA:gecersiz hedef";
                        int say = 0;
                        foreach (var f in FatBloklar(grid))
                        {
                            var b = f as Ingame.IMyBatteryBlock;
                            if (b == null) continue;
                            if (bid != 0 && f.EntityId != bid) continue;
                            if (BataryaModuAyarla(b, mod)) say++;
                        }
                        return say > 0 ? "OK" : "HATA:batarya bulunamadi";
                    }
                case "BAGLANTI_KES":
                    {
                        int adet = 0;
                        foreach (var fat in FatBloklar(grid))
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
        void PbIlet()
        {
            if (!File.Exists(OzetDosya)) return;
            string ham = OkuGuvenli(OzetDosya);
            if (string.IsNullOrWhiteSpace(ham)) return;
            ham = ham.Trim();
            string anahtar = ham + "@" + File.GetLastWriteTimeUtc(OzetDosya).Ticks;
            if (ozetIlk) { ozetIlk = false; sonOzet = anahtar; return; }
            if (anahtar == sonOzet) return;
            IMyCubeGrid grid = GridBul();
            if (grid == null) return;
            foreach (var fat in FatBloklar(grid))
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
            IMyCubeGrid grid = GridBul();
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
                int h2n = 0, o2n = 0, toplam = 0, listelenen = 0, hasarli = 0;
                var bloklar = new StringBuilder();
                var bmodlar = new StringBuilder();
                var hasarListe = new List<KeyValuePair<float, string>>();
                var slimListe = new List<IMySlimBlock>();
                grid.GetBlocks(slimListe);
                foreach (var sbItem in slimListe)
                {
                    if (sbItem == null) continue;
                    toplam++;
                    var fat = sbItem.FatBlock;
                    if (sbItem.CurrentDamage > 0f || !sbItem.IsFullIntegrity)
                    {
                        hasarli++;
                        float mx = sbItem.MaxIntegrity;
                        float yuz = mx > 0f ? (float)Math.Round(100.0 * sbItem.CurrentDamage / mx, 0) : 0f;
                        if (yuz < 1f) yuz = 1f;
                        string hAd;
                        var htb = fat as Ingame.IMyTerminalBlock;
                        if (htb != null) hAd = Temiz(htb.CustomName);
                        else hAd = Temiz(sbItem.BlockDefinition.Id.SubtypeName);
                        hasarListe.Add(new KeyValuePair<float, string>(yuz, hAd));
                    }
                    if (fat == null) continue;

                    var bat = fat as Ingame.IMyBatteryBlock;
                    if (bat != null)
                    {
                        depo += bat.CurrentStoredPower; maks += bat.MaxStoredPower;
                        bmodlar.Append("bmod.").Append(bat.EntityId).Append('=').Append(BataryaModu(bat)).Append("\r\n");
                    }
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
                sb.Append("hasarli_sayisi=").Append(hasarli).Append("\r\n");
                if (maks > 0) sb.Append("batarya_yuzde=").Append((int)Math.Round(100.0 * depo / maks)).Append("\r\n");
                sb.Append("guc_mw=").Append(Math.Round(guc, 2).ToString(System.Globalization.CultureInfo.InvariantCulture)).Append("\r\n");
                if (h2n > 0) sb.Append("hidrojen_yuzde=").Append((int)Math.Round(100.0 * h2 / h2n)).Append("\r\n");
                if (o2n > 0) sb.Append("oksijen_yuzde=").Append((int)Math.Round(100.0 * o2 / o2n)).Append("\r\n");
                if (hasarListe.Count > 0)
                {
                    hasarListe.Sort((x, y) => y.Key.CompareTo(x.Key));
                    sb.Append("en_hasar_yuzde=").Append((int)hasarListe[0].Key).Append("\r\n");
                    sb.Append("en_hasar_adi=").Append(hasarListe[0].Value).Append("\r\n");
                    for (int i = 0; i < hasarListe.Count && i < 8; i++)
                        sb.Append("hasar.").Append(i + 1).Append('=').Append(hasarListe[i].Value).Append('|').Append((int)hasarListe[i].Key).Append("\r\n");
                }
                sb.Append(bmodlar.ToString());
                sb.Append(bloklar.ToString());
            }
            AtomikYaz(TelDosya, sb.ToString());
        }

        // ---------------- Yardimcilar ----------------
        static readonly System.Reflection.PropertyInfo ChargeModeOzellik = typeof(Ingame.IMyBatteryBlock).GetProperty("ChargeMode");

        static string BataryaModu(Ingame.IMyBatteryBlock b)
        {
            try { return ChargeModeOzellik == null ? "?" : Convert.ToString(ChargeModeOzellik.GetValue(b, null)); }
            catch (Exception) { return "?"; }
        }

        static bool BataryaModuAyarla(Ingame.IMyBatteryBlock b, string mod)
        {
            try
            {
                if (ChargeModeOzellik == null) return false;
                ChargeModeOzellik.SetValue(b, Enum.Parse(ChargeModeOzellik.PropertyType, mod), null);
                return true;
            }
            catch (Exception) { return false; }
        }

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

        IMyCubeGrid GridBul()
        {
            var oyun = MyAPIGateway.Session;
            if (oyun == null || oyun.Player == null) return sonGrid;

            var koltuk = oyun.ControlledObject as IMyCubeBlock;
            if (koltuk != null && koltuk.CubeGrid != null && !koltuk.CubeGrid.MarkedForClose)
            {
                sonGrid = koltuk.CubeGrid;
                sonGridTick = Tick();
                return sonGrid;
            }
            if (sonGrid != null && !sonGrid.MarkedForClose && Tick() - sonGridTick < 3000) return sonGrid;

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
            catch (IOException) { }
        }

        void HataYaz(Exception e)
        {
            int t = Tick();
            if (t - sonHataTick < 5000) return;
            sonHataTick = t;
            try { File.AppendAllText(HataLog, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + e + "\r\n", Utf8); }
            catch (Exception) { }
        }
    }
}