// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// "Ekranı çevir": fiyatlar, sayılar ve tuş çubukları. Fiyat kuralları ortak deneme dosyasından
/// (core/Tests/CouchSubsCoreTests/Fixtures/price-text.json; Mac PriceTextTests.swift ve Android PriceTextTest.kt aynı dosyayı okur).
/// </summary>
public class PriceTextTests
{
    [Fact]
    public void SharedVectors()
    {
        using var fixture = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("price-text.json")));
        var root = fixture.RootElement;
        foreach (var pair in root.GetProperty("repair").EnumerateArray())
            Assert.Equal(pair[1].GetString(), PriceText.Repair(pair[0].GetString()!));
        foreach (var pair in root.GetProperty("money").EnumerateArray())
            Assert.True(pair[1].GetBoolean() == PriceText.IsMoney(pair[0].GetString()!), pair[0].GetString());
        foreach (var vector in root.GetProperty("protect").EnumerateArray())
        {
            var text = vector.GetProperty("text").GetString()!;
            var result = PriceText.Protect(text);
            string Fill(string template) =>
                result.Values.Select((value, i) => (value, i)).Aggregate(template, (all, entry) => all.Replace("{" + entry.i + "}", entry.value.Name));
            Assert.Equal(Fill(vector.GetProperty("sent").GetString()!), result.Text);
            Assert.Equal(vector.GetProperty("result").GetString(), PriceText.Restore(Fill(vector.GetProperty("reply").GetString()!), result.Values));
        }
    }

    private static TextLine Line(string text, double left, double top, double right, params (string Text, double Left, double Right)[] words) =>
        new(text, new TextBox(left, top, right, top + 0.03), Words: words.Length == 0 ? null
            : [.. words.Select(word => new TextWord(word.Text, new TextBox(word.Left, top, word.Right, top + 0.03)))]);

    /// <summary>
    /// Sağ alttaki tuş çubuğu: "SCROLL R3 SEND ✕ BACK ○" atılmıyor; tuşlar çeviriye girmeden yerinde kalıyor, her etiket
    /// kendi kutusunda sözlükten çevriliyor (çeviriler üst üste binmiyor).
    /// </summary>
    [Fact]
    public async Task PromptBarLabelsAreTranslatedOneByOneAndButtonsStay()
    {
        var bar = Line("SCROLL R3 SEND ✕ BACK ○", 0.70, 0.92, 0.98,
            ("SCROLL", 0.70, 0.76), ("R3", 0.77, 0.79), ("SEND", 0.81, 0.85), ("✕", 0.86, 0.87), ("BACK", 0.89, 0.93), ("○", 0.94, 0.95));
        var translator = new Recorder();
        var items = await ScreenTranslation.TranslateAsync(new Reading([bar]), translator);
        Assert.Empty(translator.Asked);
        Assert.Equal(["KAYDIR", "GÖNDER", "GERİ"], items.Select(item => item.Translation));
        Assert.Equal([0.70, 0.81, 0.89], items.Select(item => item.Box.Left));
        Assert.Equal([0.76, 0.85, 0.93], items.Select(item => item.Box.Right));
    }

    /// <summary>Bar menüsü: aynı satıra düşmüş seçenekler geniş boşluktan ayrılır; fiyat çeviriye girmez ve bozulmaz.</summary>
    [Fact]
    public async Task OptionsOnOneRowBecomeSeparateBoxesAndPricesStay()
    {
        var row = Line("TIP S10 ORDER BARTENDER", 0.30, 0.80, 0.80, ("TIP", 0.30, 0.34), ("S10", 0.35, 0.39), ("ORDER", 0.50, 0.57), ("BARTENDER", 0.68, 0.80));
        var items = await ScreenTranslation.TranslateAsync(new Reading([row]), new Recorder());
        Assert.Equal(["BAHŞİŞ VER", "SİPARİŞ VER", "BARMEN"], items.Select(item => item.Translation));
        Assert.Equal(0.34, items[0].Box.Right);
    }

    /// <summary>Dükkân: "SSSS" (yazı tanımanın okuduğu "$$$$") artık yazı sayılıp çevrilmiyor; cümledeki fiyat korunuyor.</summary>
    [Fact]
    public async Task MisreadPricesAreNotTranslatedAndPricesInSentencesSurvive()
    {
        var translator = new Recorder(text => text.Replace("Buy the jacket for ", "Ceketi şu fiyata al: "));
        var items = await ScreenTranslation.TranslateAsync(new Reading([Line("SSSS", 0.10, 0.10, 0.16), Line("Buy the jacket for S200", 0.10, 0.50, 0.50)]), translator);
        var asked = Assert.Single(translator.Asked);
        Assert.DoesNotContain("$", asked);
        Assert.DoesNotContain("S200", asked);
        Assert.Equal(["Ceketi şu fiyata al: $200"], items.Select(item => item.Translation));
    }

    private sealed class Recorder(Func<string, string>? answer = null) : ITextTranslator
    {
        public List<string> Asked { get; } = [];

        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            Asked.Add(text);
            return Task.FromResult(answer?.Invoke(text) ?? text);
        }
    }
}
