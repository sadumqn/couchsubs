// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// "Ekranı çevir" yerleşimi (<see cref="ScreenFit"/>): kutu simgeye taşmaz, eş öğeler aynı boyda, sütun/şerit hizası.
/// Ortak deneme dosyası core/Tests/CouchSubsCoreTests/Fixtures/screen-fit.json (Mac ScreenFitTests.swift ve Android
/// ScreenFitTest.kt aynı vakalar).
/// </summary>
public class ScreenFitTests
{
    private static Frame Synthetic(JsonElement fixture, JsonElement rects)
    {
        var width = fixture.GetProperty("width").GetInt32();
        var height = fixture.GetProperty("height").GetInt32();
        static byte[] Rgb(string hex)
        {
            var v = Convert.ToInt32(hex[1..], 16);
            return [(byte)((v >> 16) & 255), (byte)((v >> 8) & 255), (byte)(v & 255)];
        }
        var ground = Rgb(fixture.GetProperty("background").GetString()!);
        var ink = Rgb(fixture.GetProperty("ink").GetString()!);
        var frame = Frame.Blank(width, height);
        void Paint(int x, int y, byte[] c)
        {
            var p = (y * frame.Stride) + (x * 4);
            frame.Pixels[p] = c[2];
            frame.Pixels[p + 1] = c[1];
            frame.Pixels[p + 2] = c[0];
            frame.Pixels[p + 3] = 255;
        }
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++) Paint(x, y, ground);
        foreach (var rect in rects.EnumerateArray())
        {
            var r = rect.EnumerateArray().Select(v => v.GetDouble()).ToArray();
            int x0 = (int)Math.Round(r[0] * width, MidpointRounding.AwayFromZero), x1 = (int)Math.Round(r[2] * width, MidpointRounding.AwayFromZero);
            int y0 = (int)Math.Round(r[1] * height, MidpointRounding.AwayFromZero), y1 = (int)Math.Round(r[3] * height, MidpointRounding.AwayFromZero);
            for (var y = y0; y < y1; y++)
                for (var x = x0; x < x1; x++) Paint(x, y, ink);
        }
        return frame;
    }

    [Fact]
    public void SharedVectors()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("screen-fit.json")));
        var fixture = document.RootElement;
        var tolerance = fixture.GetProperty("tolerance").GetDouble();
        var background = fixture.GetProperty("background").GetString()!;
        var ink = fixture.GetProperty("ink").GetString()!;
        foreach (var vector in fixture.GetProperty("cases").EnumerateArray())
        {
            var frame = Synthetic(fixture, vector.GetProperty("rects"));
            var raw = vector.GetProperty("items").EnumerateArray().ToList();
            var items = raw.Select(entry =>
            {
                var b = entry.GetProperty("box").EnumerateArray().Select(v => v.GetDouble()).ToArray();
                var name = entry.GetProperty("name").GetString()!;
                return new ScreenTranslation.Item(name, name, new TextBox(b[0], b[1], b[2], b[3]), entry.GetProperty("line").GetDouble())
                {
                    Style = new PhoneTextStyle(background, ink),
                    Look = new TextLook(true, false, "left", true, true),
                };
            }).ToList();
            var fitted = ScreenFit.Fitted(items, frame);
            var expect = vector.GetProperty("expect").EnumerateArray().ToList();
            Assert.Equal(expect.Count, fitted.Count);
            for (var k = 0; k < expect.Count; k++)
            {
                var want = expect[k];
                var have = fitted[k];
                var name = $"{vector.GetProperty("id").GetString()} {raw[k].GetProperty("name").GetString()}";
                Assert.True(want.GetProperty("align").GetString() == have.Look!.Align, $"{name}: hiza {have.Look.Align}");
                Assert.True(Math.Abs(want.GetProperty("line").GetDouble() - have.LineHeight) <= tolerance, $"{name}: satır {have.LineHeight}");
                Close(name + " kutu", want.GetProperty("box"), have.Box);
                Assert.True(have.Room is not null, name + ": alan yok");
                Close(name + " alan", want.GetProperty("room"), have.Room!.Value);
            }
        }

        void Close(string name, JsonElement want, TextBox have)
        {
            var w = want.EnumerateArray().Select(v => v.GetDouble()).ToArray();
            double[] h = [have.Left, have.Top, have.Right, have.Bottom];
            for (var i = 0; i < 4; i++) Assert.True(Math.Abs(w[i] - h[i]) <= tolerance, $"{name}: {string.Join(", ", h)} ≠ {string.Join(", ", w)}");
        }
    }

    /// <summary>Yapay zekâ çevirmeni yerine: önbelleğinde olanı istek göndermeden verir; istek anında neyin çizildiğini kaydeder.</summary>
    private sealed class HeldTranslator(Dictionary<string, string> cache, Func<IReadOnlyList<ScreenTranslation.Item>> drawn) : ITextTranslator
    {
        public List<string> Asked { get; } = [];
        public IReadOnlyList<ScreenTranslation.Item> DrawnWhileAsking { get; private set; } = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => Task.FromResult("yeni gelen çeviri");
        public bool TranslatesTogether => true;
        public string? CachedTranslation(string text) => cache.TryGetValue(text, out var known) ? known : null;
        public Task<IReadOnlyList<string>> TranslateAllAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default)
        {
            Asked.AddRange(texts);
            DrawnWhileAsking = drawn();
            return Task.FromResult<IReadOnlyList<string>>([.. texts.Select(_ => "yeni gelen çeviri")]);
        }
    }

    /// <summary>
    /// Önbellekteki yazı anında: menü satırı önceki oturumdan önbellekte, görev açıklaması yeni. Önbellekteki grup çeviri
    /// isteği gitmeden çizilir; çevirmene yalnız yeni yazı gider (Mac ScreenFitTests, Android ScreenFitTest ile aynı).
    /// </summary>
    [Fact]
    public async Task CachedScreenTextIsDrawnBeforeTheRequest()
    {
        var reading = new Reading([
            new TextLine("ISLAND DREAMS", new TextBox(0.18, 0.19, 0.35, 0.24)),
            new TextLine("Keep an eye on the bachelor party while searching for treasure.", new TextBox(0.14, 0.27, 0.46, 0.31)),
        ]);
        IReadOnlyList<ScreenTranslation.Item> latest = [];
        var translator = new HeldTranslator(new() { ["ISLAND DREAMS"] = "ADA HAYALLERİ" }, () => latest);
        var final = await ScreenTranslation.TranslateAsync(reading, translator, items => latest = items);
        Assert.Contains(translator.DrawnWhileAsking, item => item.Translation == "ADA HAYALLERİ");
        Assert.DoesNotContain("ISLAND DREAMS", translator.Asked);
        Assert.Contains(final, item => item.Translation == "yeni gelen çeviri");
        Assert.Contains(final, item => item.Translation == "ADA HAYALLERİ");
    }

    /// <summary>Çizicilerin ortak satır yerleşimi (screen-fit.json → lines; Mac ve Android aynı vakalar).</summary>
    [Fact]
    public void SharedLineVectors()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("screen-fit.json")));
        foreach (var vector in document.RootElement.GetProperty("lines").EnumerateArray())
        {
            (double, double)? room = vector.GetProperty("room").ValueKind == JsonValueKind.Array
                ? (vector.GetProperty("room")[0].GetDouble(), vector.GetProperty("room")[1].GetDouble()) : null;
            var got = ScreenFit.Layout(vector.GetProperty("text").GetString()!, vector.GetProperty("left").GetDouble(),
                vector.GetProperty("width").GetDouble(), room, vector.GetProperty("rows").GetInt32(), vector.GetProperty("align").GetString()!,
                text => text.Length * 10.0);
            var want = vector.GetProperty("expect");
            var name = vector.GetProperty("id").GetString();
            Assert.Equal(want.GetProperty("lines").EnumerateArray().Select(line => line.GetString()!).ToList(), got.Rows);
            Assert.True(Math.Abs(want.GetProperty("squeeze").GetDouble() - got.Squeeze) <= 0.001, $"{name}: {got.Squeeze}");
            Assert.True(Math.Abs(want.GetProperty("left").GetDouble() - got.Left) <= 0.01, $"{name}: {got.Left}");
            Assert.True(Math.Abs(want.GetProperty("width").GetDouble() - got.Width) <= 0.01, $"{name}: {got.Width}");
        }
    }
}
