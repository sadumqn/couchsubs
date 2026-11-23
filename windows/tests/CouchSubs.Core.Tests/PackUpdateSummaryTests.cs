// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;

namespace CouchSubs.Core.Tests;

/// <summary>
/// "Paketleri şimdi güncelle" sonucunun özeti: eklenen, güncellenen paketler ve gelen satırlar. Vektörler
/// core/Tests/CouchSubsCoreTests/PackUpdateSummaryTests.swift ile aynı.
/// </summary>
public sealed class PackUpdateSummaryTests
{
    private static PackUpdateSummary.Downloaded Pack(string id, string title, int lines) => new(id, title, lines);

    [Fact]
    public void NothingDownloadedIsEmpty()
    {
        var summary = new PackUpdateSummary([("gta-6", 74_673)], []);
        Assert.True(summary.IsEmpty);
        Assert.Equal(0, summary.NewLines);
    }

    [Fact]
    public void UpdatedAndAddedPacks()
    {
        var summary = new PackUpdateSummary(
            [("gta-6", 74_673), ("rdr-2", 20_000), ("elden-ring", 37_951)],
            [Pack("gta-6", "Grand Theft Auto VI", 86_973), Pack("rdr-2", "Red Dead Redemption 2", 20_800),
             Pack("death-stranding-2", "Death Stranding 2", 23_132)]);
        Assert.Equal(["gta-6", "rdr-2"], summary.Updated.Select(change => change.Id));
        Assert.Equal([12_300, 800], summary.Updated.Select(change => change.LineDelta));
        Assert.Equal(["death-stranding-2"], summary.Added.Select(change => change.Id));
        Assert.Equal(23_132, summary.Added[0].LineDelta);
        Assert.Equal(12_300 + 800 + 23_132, summary.NewLines);
    }

    /// <summary>Satırı azalan (temizlenen) paket güncellenmiş sayılır ama toplam yeni satırdan düşülmez.</summary>
    [Fact]
    public void ShrinkingPackDoesNotReduceNewLines()
    {
        var summary = new PackUpdateSummary([("a", 1000), ("b", 500)], [Pack("a", "A", 900), Pack("b", "B", 700)]);
        Assert.Equal([-100, 200], summary.Updated.Select(change => change.LineDelta));
        Assert.Equal(200, summary.NewLines);
    }

    /// <summary>Aynı kimlik kitaplıkta iki kez: son gelen geçerli; inen paket bir kez sayılır.</summary>
    [Fact]
    public void DuplicatesUseLastAndCountOnce()
    {
        var summary = new PackUpdateSummary([("gta-6", 60_000), ("gta-6", 74_673)],
            [Pack("gta-6", "GTA VI", 86_973), Pack("gta-6", "GTA VI", 86_973)]);
        Assert.Single(summary.Changes);
        Assert.Equal(12_300, summary.Changes[0].LineDelta);
    }

    /// <summary>Sonuç iletisi telefonlardakiyle aynı metin (ortak katalogdan).</summary>
    [Fact]
    public void MessageMatchesThePhones()
    {
        var culture = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
        try
        {
            var tr = Localizer.ForLanguage("tr");
            var summary = new PackUpdateSummary(
                [("gta-6", 74_673), ("rdr-2", 20_000), ("a", 10), ("b", 10)],
                [Pack("gta-6", "Grand Theft Auto VI", 86_973), Pack("rdr-2", "Red Dead Redemption 2", 19_900),
                 Pack("a", "A", 10), Pack("yeni", "Yeni Oyun", 1_500)]);
            Assert.Equal(
                "3 paket güncellendi: Grand Theft Auto VI (+12.300 satır), Red Dead Redemption 2 (100 satır azaldı), A (çeviriler düzeltildi).\n"
                + "1 paket eklendi: Yeni Oyun (1.500 satır).\nToplam 13.800 yeni satır.",
                summary.Describe(tr));

            var upToDate = new PackUpdateOutcome(PackUpdateOutcome.Kind.UpToDate, new PackUpdateSummary([], []));
            Assert.Equal("Paketler güncel", upToDate.Title(tr));
            Assert.Equal("Paketler zaten güncel.", upToDate.Message(tr));

            var failed = new PackUpdateOutcome(PackUpdateOutcome.Kind.Failed, new PackUpdateSummary([], []), "Neden.");
            Assert.Equal("Paketler güncellenemedi", failed.Title(tr));
            Assert.Equal("Neden.\n\nBu bilgisayardaki paketler kullanılmaya devam ediyor.", failed.Message(tr));
        }
        finally
        {
            CultureInfo.CurrentCulture = culture;
        }
    }
}
