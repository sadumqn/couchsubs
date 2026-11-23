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
        const string key = "Automatic uses Overlay whenever the TV app allows it: the TV shows the PS5 on its own HDMI input and the subtitles appear on top. On some TVs the picture stays black inside the CouchSubs TV app. To show the PS5 inside the CouchSubs TV app instead, choose Inside the app; the TV app then never switches to Overlay by itself: if no picture arrives, it reopens the HDMI input and lists the inputs, and you can choose Overlay there. With Overlay the TV also keeps its picture mode, Game mode and HDR. The TV app from Google Play has no Overlay mode: there Automatic stays inside the app, and the TV says so on screen if Overlay is chosen.";
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
