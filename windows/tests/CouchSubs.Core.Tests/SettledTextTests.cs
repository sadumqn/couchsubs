// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;

namespace CouchSubs.Core.Tests;

/// <summary>
/// PS5'in Türkçe ana ekranı (beta.89, Mac): Türkçe harfleri düz okunan menü satırı çevrilmez ve paketle eşleşmez, bozuk
/// okunmuş parçası ("One [Ikan Ipufl") altyazı sayılmaz, değişmeyen ekranda aynı satır yeniden işlenmez. Ortak deneme
/// dosyası core/Tests/CouchSubsCoreTests/Fixtures/settled-text.json (Mac SettledTextTests.swift ve Android
/// SettledTextTest.kt aynı dosyayı okur).
/// </summary>
public class SettledTextTests
{
    private static JsonElement Vectors(string name)
    {
        using var fixture = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("settled-text.json")));
        return fixture.RootElement.GetProperty(name).Clone();
    }

    private static TextBox? Box(JsonElement element) =>
        element.ValueKind != JsonValueKind.Array ? null
            : new TextBox(element[0].GetDouble(), element[1].GetDouble(), element[2].GetDouble(), element[3].GetDouble());

    [Fact]
    public void TurkishMenuLines()
    {
        foreach (var vector in Vectors("turkish").EnumerateArray())
        {
            var text = vector.GetProperty("text").GetString()!;
            Assert.True(TurkishText.LooksTurkish(text) == vector.GetProperty("turkish").GetBoolean(), text);
        }
    }

    [Fact]
    public void BracketGarbledReadings()
    {
        foreach (var vector in Vectors("bracket").EnumerateArray())
        {
            var text = vector.GetProperty("text").GetString()!;
            Assert.True(OcrNoise.LooksBracketGarbled(text) == vector.GetProperty("garbled").GetBoolean(), text);
        }
    }

    [Fact]
    public void FragmentsOfTargetLanguageBlock()
    {
        foreach (var vector in Vectors("fragment").EnumerateArray())
        {
            var settled = new SettledText();
            settled.Settle(vector.GetProperty("target").GetString()!, Box(vector.GetProperty("box")), target: true, shown: false, 0);
            foreach (var item in vector.GetProperty("cases").EnumerateArray())
            {
                var text = item.GetProperty("text").GetString()!;
                Assert.True(settled.IsTargetFragment(text, Box(item.GetProperty("box"))) == item.GetProperty("fragment").GetBoolean(), text);
            }
        }
    }

    [Fact]
    public void SettledLinesStayQuietWhileOnScreen()
    {
        foreach (var vector in Vectors("settle").EnumerateArray())
        {
            var name = vector.GetProperty("name").GetString()!;
            var settled = new SettledText();
            foreach (var step in vector.GetProperty("steps").EnumerateArray())
            {
                var time = step.GetProperty("time").GetInt64();
                if (step.TryGetProperty("observe", out var lines))
                    settled.Observe(lines.EnumerateArray().Select(line => line.GetString()!), time);
                if (step.TryGetProperty("settle", out var source))
                    settled.Settle(source.GetString()!, null, step.GetProperty("target").GetBoolean(), step.GetProperty("shown").GetBoolean(), time,
                        step.GetProperty("loose").GetBoolean());
                if (step.TryGetProperty("ask", out var asked))
                    Assert.True(settled.IsSettled(asked.GetString()!) == step.GetProperty("settled").GetBoolean(), $"{name}: {asked.GetString()}");
            }
        }
    }

    /// <summary>Karenin izi satırla değişir (kararlayıcı aynı izli boş okumayı "satır duruyor" sayar).</summary>
    private static Frame Image(string text) =>
        new(Enumerable.Repeat((byte)(text.Length % 7 * 36), 64 * 64 * 4).ToArray(), 64, 64, 256);

    /// <summary>
    /// Mac altyazi.log'undaki döngü: menü satırları sırayla seçilir, hiçbiri çevirmene ya da TV'ye gitmez, paketteki bozuk
    /// parça gösterilmez, her satır günlüğe en çok bir kez düşer.
    /// </summary>
    [Fact]
    public async Task TurkishMenuLoopStaysQuiet()
    {
        var vector = Vectors("pipeline");
        var pack = vector.GetProperty("pack").GetString()!;
        var packText = vector.GetProperty("packText").GetString()!;
        var shown = vector.GetProperty("frames").EnumerateArray()
            .Select(frame => (Text: frame.GetProperty("text").GetString()!, Count: frame.GetProperty("count").GetInt32())).ToList();
        var frames = new List<string>();
        for (var cycle = 0; cycle < vector.GetProperty("cycles").GetInt32(); cycle++)
            foreach (var (text, count) in shown) frames.AddRange(Enumerable.Repeat(text, count));
        long clock = 0;
        var sender = new FakeSender();
        var translator = new FakeTranslator();
        var log = new List<string>();
        var pipeline = new SubtitlePipeline(new FakeReader([.. frames]), translator, sender, clock: () => clock)
        {
            PackLookup = text => text == pack ? new PackMatch(packText, []) : null,
            Log = log.Add,
        };
        foreach (var frame in frames)
        {
            await pipeline.ProcessAsync(Image(frame), new CropRegion());
            await pipeline.WaitForTranslationsAsync();
            clock += 100;
        }
        Assert.Empty(translator.Requested);
        Assert.Empty(sender.Sent);
        Assert.DoesNotContain(log, line => line.Contains("→ paket"));
        foreach (var (text, _) in shown)
        {
            var excerpt = SubtitleLog.Excerpt(text);
            Assert.True(log.Count(line => line.Contains(excerpt) && line.Contains("çevrilmedi")) <= 1, text + "\n" + string.Join("\n", log));
        }
    }
}
