// SPDX-License-Identifier: AGPL-3.0-only
namespace CouchSubs.Core.Tests;

/// <summary>Sırayla farklı okumalar döndüren, satırları yerleriyle veren okuyucu.</summary>
internal sealed class SequenceReader(IEnumerable<Reading> readings) : ITextReader
{
    private readonly Queue<Reading> readings = new(readings);
    public string Read(Frame image) => ReadLines(image, false).Text;
    public Reading ReadLines(Frame image, bool deep)
    {
        lock (readings) return readings.Count == 0 ? Reading.Empty : readings.Dequeue();
    }
}

/// <summary>
/// Kullanıcı bildirimi (GTA 6): oyun altta "x yere git" gibi bir görev yazısı gösterirken o sırada gelen altyazıların hiçbiri
/// çevrilmiyordu. Görev satırı sabit dururken üstünde ya da altında değişen altyazıların hepsi çevrilmeli, görev hiçbir
/// altyazıya karışmamalı (Mac: ObjectiveWithDialogueTests.swift, Android: ObjectiveWithDialogueTest.kt).
/// </summary>
public class ObjectiveWithDialogueTests
{
    private const string Objective = "Go to the bank.";

    internal static readonly string[][] Dialogue =
    [
        ["We have to move before the cops show up."],
        ["I told you this was a bad idea,", "but you never listen to me."],
        ["Lucia: Just drive the car and stay calm."],
        ["Where did they take all the money?"],
        ["Nobody saw us leave the place.", "Keep your head down for a while."],
    ];

    /// <summary>Satır yüksekliği (alana oranla) ve satırların dikey yeri; altyazı ortada, görev ortalı.</summary>
    private const double Line = 0.08;

    private static TextLine Row(string text, double top, double width = 0.6) =>
        new(text, new TextBox(0.5 - width / 2, top, 0.5 + width / 2, top + Line), 0.95);

    /// <summary>
    /// Kareler: görev önce tek başına (<paramref name="objectiveFirstFrames"/> kare), sonra her altyazı 4 kare (2 sn) görevle
    /// birlikte. <paramref name="objectiveGap"/>: görev ile altyazı arasındaki boşluk (satır yüksekliğine oranla);
    /// <paramref name="below"/>: görev altyazının altında mı.
    /// </summary>
    internal static List<Reading> Frames(bool below, double objectiveGap, int objectiveFirstFrames, int framesEach = 4)
    {
        var frames = new List<Reading>();
        for (var i = 0; i < objectiveFirstFrames; i++) frames.Add(new Reading([Row(Objective, below ? 0.8 : 0.2, 0.3)]));
        foreach (var lines in Dialogue)
        {
            var height = lines.Length * Line;
            var rows = new List<TextLine>();
            double top;
            if (below)
            {
                // Görev 0.80'de; altyazı onun üstünde, aralarında objectiveGap satır boşluk.
                top = 0.8 - objectiveGap * Line - height;
                rows.AddRange(lines.Select((text, i) => Row(text, top + i * Line)));
                rows.Add(Row(Objective, 0.8, 0.3));
            }
            else
            {
                rows.Add(Row(Objective, 0.2, 0.3));
                top = 0.2 + Line + objectiveGap * Line;
                rows.AddRange(lines.Select((text, i) => Row(text, top + i * Line)));
            }
            for (var i = 0; i < framesEach; i++) frames.Add(new Reading(rows));
        }
        // Konuşma bitti, görev kaldı.
        for (var i = 0; i < 4; i++) frames.Add(new Reading([Row(Objective, below ? 0.8 : 0.2, 0.3)]));
        return frames;
    }

    [Theory]
    [InlineData(true, 0.1, 4)]   // görev altta, bitişik; altyazıdan 2 sn önce belirdi
    [InlineData(true, 1.5, 4)]   // görev altta, ayrı blok
    [InlineData(false, 0.1, 4)]  // görev üstte, bitişik
    [InlineData(false, 1.5, 4)]  // görev üstte, ayrı blok
    [InlineData(true, 0.1, 20)]  // görev 10 sn önceden ekranda
    [InlineData(true, 1.5, 20)]
    [InlineData(false, 0.1, 20)]
    [InlineData(true, 0.1, 0)]   // görev ilk altyazıyla aynı anda belirdi: ilki ayırt edilemez, sonrakiler çevrilir
    [InlineData(true, 1.5, 0)]
    public async Task EveryDialogueIsTranslatedWhileObjectiveStays(bool below, double gap, int objectiveFirst)
    {
        var frames = Frames(below, gap, objectiveFirst);
        long clock = 0;
        var translator = new FakeTranslator();
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new SequenceReader(frames), translator, sender, clock: () => clock)
        { PackWait = 0, CleanWait = 0 };
        for (var i = 0; i < frames.Count; i++)
        {
            await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion(0, 1, 0, 1));
            await pipeline.WaitForTranslationsAsync();
            clock += 500;
        }
        var requested = string.Join(" | ", translator.Requested);
        // Görev ilk altyazıyla aynı anda belirince de ilk altyazı çevrilir (kısa görev satırı altyazının altında; beta.69).
        var missing = Dialogue.SelectMany(lines => lines).Select(line => line.Replace("Lucia: ", ""))
            .Where(line => !translator.Requested.Any(text => text.Contains(line))).ToList();
        Assert.True(missing.Count == 0, $"çevrilmedi: {string.Join(" / ", missing)} — istekler: {requested}");
        // Görev satırı hiçbir altyazı isteğine karışmaz (yalnız görev tek başınayken kendisi çevrilebilir).
        var mixed = translator.Requested.Where(text => text.Contains(Objective.TrimEnd('.')) && text.Trim() != Objective)
            .Where(text => objectiveFirst != 0 || !text.Contains(Dialogue[0][0])).ToList();
        Assert.True(mixed.Count == 0, $"görev karıştı: {string.Join(" | ", mixed)}");
    }

    /// <summary>
    /// Kullanıcı bildirimi (X, beta.69, GTA 6): konuşma sürerken altta "Follow John" görevi belirdi, o konuşma çevrilmedi.
    /// Görev konuşmayla aynı anda ya da konuşma başladıktan 0,5–2 sn sonra gelir; görev altyazıdan ayrı blok ya da bitişik.
    /// Konuşma çevrilir, TV'de konuşma ekrandayken görev altyazının yerine geçmez, görev kendi yerinde gösterilir.
    /// </summary>
    [Theory]
    [InlineData(0, 1.5)]
    [InlineData(1, 1.5)]
    [InlineData(2, 1.5)]
    [InlineData(4, 1.5)]
    [InlineData(0, 0.1)]
    [InlineData(2, 0.1)]
    [InlineData(4, 0.1)]
    public async Task ObjectiveArrivingDuringDialogueDoesNotReplaceIt(int objectiveAfterFrames, double gap)
    {
        const string objective = "Follow John";
        string[] dialogue = ["I can't believe he's still alive after all that.", "We need to keep moving before they find us."];
        const double objectiveTop = 0.8;
        var dialogueTop = objectiveTop - gap * Line - Line;
        var frames = new List<Reading>();
        for (var i = 0; i < 8; i++)
            frames.Add(new Reading(i < objectiveAfterFrames ? [Row(dialogue[0], dialogueTop)]
                                                            : [Row(dialogue[0], dialogueTop), Row(objective, objectiveTop, 0.25)]));
        for (var i = 0; i < 8; i++) frames.Add(new Reading([Row(dialogue[1], dialogueTop), Row(objective, objectiveTop, 0.25)]));
        long clock = 0;
        var translator = new FakeTranslator();
        var sender = new FakeSender();
        var pipeline = new SubtitlePipeline(new SequenceReader(frames), translator, sender, clock: () => clock)
        { PackWait = 0, CleanWait = 0 };
        var regions = new List<CropRegion?>();
        pipeline.MissionChanged += regions.Add;
        foreach (var _ in frames)
        {
            await pipeline.ProcessAsync(Frame.Blank(64, 64), new CropRegion(0, 1, 0, 1));
            await pipeline.WaitForTranslationsAsync();
            clock += 500;
        }
        var requested = string.Join(" | ", translator.Requested);
        foreach (var line in dialogue)
            Assert.True(translator.Requested.Any(text => text.Contains(line)), $"çevrilmedi: {line} — istekler: {requested}");
        // Görev tek başına altyazı olarak çevrilmedi (konuşmanın yerine geçmedi).
        Assert.DoesNotContain(objective, translator.Requested.Select(text => text.Trim()));
        // Görev kendi yerinde.
        Assert.Contains(regions, region => region is not null && region.Top <= objectiveTop && region.Bottom >= objectiveTop + Line);
    }
}
