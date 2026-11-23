// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// Metinler Mac uygulamasının Localizable.xcstrings dosyasından gelir; iki uygulama aynı çevirileri kullanır.
public class LocalizerTests
{
    [Fact]
    public void TurkishTextComesFromSharedCatalog()
    {
        var tr = Localizer.ForLanguage("tr");
        Assert.Equal("Çeviriyi başlat", tr["Start translating"]);
        Assert.Equal("Start translating", Localizer.ForLanguage("en")["Start translating"]);
    }

    [Fact]
    public void UnknownLanguageFallsBackToEnglish() =>
        Assert.Equal("Start translating", Localizer.ForLanguage("de")["Start translating"]);

    [Fact]
    public void MissingKeyShowsTheKey() =>
        Assert.Equal("No such text", Localizer.ForLanguage("tr")["No such text"]);

    [Fact]
    public void PositionalFormatArgumentsAreFilled()
    {
        var tr = Localizer.ForLanguage("tr");
        Assert.Equal("Adım 2 / 6", tr.Format("Step %lld of %lld", 2, 6));
        Assert.Contains("İngilizce", tr.Format("The %@–%@ language pack is not downloaded yet.", "İngilizce", "Türkçe"));
    }

    /// Görüntü modu ipucu (SettingsView.xaml ile aynı anahtar): uygulama içinde oyun modu ya da HDR kaybolursa
    /// Katman önerilir (Sony Bravia, LG). Anahtar XAML'da değişip katalogda kalmazsa ipucu İngilizce görünürdü.
    [Fact]
    public void PictureModeHintSuggestsOverlayForLostGameModeAndHdr()
    {
        const string key = "Automatic uses Overlay whenever the TV app allows it: the TV shows the PS5 on its own HDMI input and the subtitles appear on top. On some TVs the picture stays black inside the CouchSubs TV app. To show the PS5 inside the CouchSubs TV app instead, choose Inside the app; if no picture arrives there, the TV app switches to Overlay by itself. With Overlay the TV also keeps its picture mode, Game mode and HDR: inside the app the TV handles the PS5 picture as an app, not as its HDMI input.";
        var tr = Localizer.ForLanguage("tr")[key];
        Assert.NotEqual(key, tr);
        Assert.Contains("oyun modu ya da HDR", tr);
        var xaml = File.ReadAllText(Path.Combine(RepoRoot(), "windows", "src", "CouchSubs.App", "Views", "SettingsView.xaml"));
        Assert.Contains(key, xaml);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !Directory.Exists(Path.Combine(dir.FullName, "mac", "CouchSubs"))) dir = dir.Parent;
        return dir?.FullName ?? throw new DirectoryNotFoundException("depo kökü bulunamadı");
    }

    [Fact]
    public void EveryEntryHasTurkish()
    {
        var missing = Localizer.MissingTranslations("tr");
        Assert.True(missing.Count == 0, string.Join(", ", missing));
    }
}
