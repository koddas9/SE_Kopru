// ============================================================
// ATLAS - PARCA 5: PROGRAMMABLE BLOCK SCRIPTI (atlas_pb.cs)
// Kurulum:
//   1) Gemide bir Programmable Block yerlestir, adini "Atlas PB" yap.
//   2) Edit > bu dosyanin TUM icerigini yapistir > Check Code > Remember & Exit.
//   3) (Istege bagli) Ozetin gorunecegi LCD'lerin adina "[Atlas]" ekle.
// Calisma: Eklenti (Atlas.cs) pb_ozet.txt degisince bu bloga "ozet <metin>" argumaniyla TryRun yapar.
// PB dosya okuyamaz; veriyi yalnizca eklentiden bu sekilde alir. Turkce karakter kullanilmaz (LCD fontu).
// ============================================================
List<string> gecmis = new List<string>();

public Program()
{
    Runtime.UpdateFrequency = UpdateFrequency.None;
    if (!string.IsNullOrEmpty(Storage))
        gecmis = new List<string>(Storage.Split(new char[] { '\n' }, StringSplitOptions.RemoveEmptyEntries));
    Goster();
}

public void Save()
{
    Storage = string.Join("\n", gecmis.ToArray());
}

public void Main(string argument, UpdateType updateSource)
{
    if (argument != null && argument.StartsWith("ozet "))
    {
        string metin = argument.Substring(5).Trim();
        if (metin.Length > 120) metin = metin.Substring(0, 120);
        gecmis.Add(DateTime.Now.ToString("HH:mm") + " " + metin);
        while (gecmis.Count > 6) gecmis.RemoveAt(0);
        Goster();
    }
}

void Goster()
{
    string m = "ATLAS\n" + string.Join("\n", gecmis.ToArray());
    Echo(m);

    IMyTextSurface yuzey = Me.GetSurface(0);
    if (yuzey != null)
    {
        yuzey.ContentType = ContentType.TEXT_AND_IMAGE;
        yuzey.WriteText(m);
    }

    List<IMyTextPanel> lcdler = new List<IMyTextPanel>();
    GridTerminalSystem.GetBlocksOfType(lcdler, b => b.CustomName.Contains("[Atlas]") && b.IsSameConstructAs(Me));
    foreach (IMyTextPanel l in lcdler)
    {
        l.ContentType = ContentType.TEXT_AND_IMAGE;
        l.WriteText(m);
    }
}
