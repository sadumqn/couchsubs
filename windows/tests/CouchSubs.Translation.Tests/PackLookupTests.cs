// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Core.Dubbing;

namespace CouchSubs.Translation.Tests;

/// <summary>Mac'teki PackLookupTests ile aynı durumlar.</summary>
public class PackLookupTests
{
    private static readonly Dictionary<string, string> Pack = new()
    {
        [PackKey.Key("Get Down!")!] = "Yere yat!",
        [PackKey.Key("Who is that?")!] = "O da kim?",
        [PackKey.Key("Don Torrisi wants you.")!] = "Don Torrisi seni istiyor.",
        [PackKey.Key("Get back!")!] = "Geri çekil!",
    };

    private static PackMatch? Match(string text) =>
        PackLookup.Match(text, line => PackKey.Key(line) is { } key ? Pack.GetValueOrDefault(key) : null);

    [Fact]
    public void WholeLineIgnoresCaseSpacingAndPunctuation()
    {
        Assert.Equal("Yere yat!", Match("GET DOWN!!")?.Text);
        Assert.Equal("O da kim?", Match("  Who   is\nthat?  ")?.Text);
        Assert.Null(Match("Get out!"));
        Assert.Null(Match(""));
    }

    [Fact]
    public void SpeakerLabelIsKeptAndVoiced()
    {
        var found = Match("ENZO: Don Torrisi wants you.");
        Assert.Equal("ENZO: Don Torrisi seni istiyor.", found?.Text);
        Assert.Equal([new SpokenLine("Don Torrisi wants you.", "Don Torrisi seni istiyor.", "ENZO")], found!.Spoken);
        Assert.Equal("Cesare: Yere yat!", Match("Cesare: Get down!")?.Text);
        Assert.Null(Match("ENZO: Get out!"));
    }

    [Fact]
    public void EachLineIsLookedUpWhenTheWholeIsMissing()
    {
        Assert.Equal("ENZO: Yere yat!\nMARIA: O da kim?", Match("ENZO: Get down!\nMARIA: Who is that?")?.Text);
        Assert.Equal("- Yere yat!\n- O da kim?", Match("- Get down!\n- Who is that?")?.Text);
        // Bir satır bile eksikse paket kullanılmaz.
        Assert.Null(Match("Get down!\nWho are you?"));
    }

    [Fact]
    public void EachSentenceIsLookedUpWhenTheLineIsMissing()
    {
        var found = Match("ENZO: Get down! Who is that?");
        Assert.Equal("ENZO: Yere yat! O da kim?", found?.Text);
        Assert.Equal(["ENZO", "ENZO"], found!.Spoken.Select(line => line.Speaker));
        Assert.Equal("Yere yat! Geri çekil!", Match("Get down! Get back!")?.Text);
        Assert.Null(Match("Get down! Who are you?"));
    }

    [Fact]
    public void WholeLineWinsOverParts()
    {
        var custom = new Dictionary<string, string> { [PackKey.Key("Get down! Get back!")!] = "Eğil ve geri çekil!", [PackKey.Key("Get Down!")!] = "Yere yat!" };
        var found = PackLookup.Match("Get down! Get back!", line => PackKey.Key(line) is { } key ? custom.GetValueOrDefault(key) : null);
        Assert.Equal("Eğil ve geri çekil!", found?.Text);
    }

    /// <summary>OCR'ın bozduğu etiket ("-GAETANO:", "M]:", "li LUCA:") da atılıp aranır; ekranda olduğu gibi kalır.</summary>
    [Fact]
    public void GarbledSpeakerLabelIsStripped()
    {
        Assert.Equal("- GAETANO: Don Torrisi seni istiyor.", Match("-GAETANO: Don Torrisi wants you.")?.Text);
        Assert.Equal("- GAETANO: Don Torrisi seni istiyor.", Match("- GAETANO: Don Torrisi wants you.")?.Text);
        Assert.Equal("M]: Yere yat!", Match("M]: Get down!")?.Text);
        Assert.Equal("li LUCA: O da kim?", Match("li LUCA: Who is that?")?.Text);
        Assert.Equal("SEBASTIAN O da kim?", Match("SEBASTIAN Who is that?")?.Text);
        Assert.Null(Match("I told you: get out!"));
    }

    /// <summary>Paket betiğiyle aynı gevşek etiket kuralı (Fixtures/fuzzy-vectors.json).</summary>
    [Fact]
    public void LooseLabelVectors()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Fixture("fuzzy-vectors.json")));
        foreach (var vector in document.RootElement.GetProperty("looseLabels").EnumerateArray())
        {
            var input = vector.GetProperty("input").GetString()!;
            var found = PackLookup.LooseLabel(input);
            Assert.Equal(vector.GetProperty("label").GetString(), found?.Label);
            Assert.Equal(vector.GetProperty("body").GetString(), found?.Body);
        }
    }

    /// <summary>Tam anahtar tutmazsa her parça önce tam, sonra bulanık aranır; tam satır her zaman önce gelir.</summary>
    [Fact]
    public void NearestIsTriedOnlyAfterExactParts()
    {
        var asked = new List<string>();
        string? Nearest(string line)
        {
            asked.Add(line);
            return line == "Who iz that?" ? "O da kim?" : null;
        }
        string? Find(string line) => PackKey.Key(line) is { } key ? Pack.GetValueOrDefault(key) : null;
        Assert.Equal("ENZO: Yere yat! O da kim?", PackLookup.Match("ENZO: Get down! Who iz that?", Find, Nearest)?.Text);
        Assert.Equal("Yere yat!", PackLookup.Match("GET DOWN!!", Find, _ => "x")?.Text);
        Assert.DoesNotContain("Get down!", asked);
    }

    /// <summary>
    /// Kullanıcılardan gelen gerçek ıskalamalar (Mafia: The Old Country, OCR hatalı, parça parça ve etiketi bozuk
    /// satırlar): paket betiğinin Python karşılığıyla ve Mac'le aynı Türkçe ya da hiç eşleşme (başka oyunların satırları).
    /// </summary>
    [Fact]
    public void RealOcrMissesMatchLikeThePackScript()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Fixture("pack-matches.json")));
        var cases = document.RootElement.GetProperty("cases").EnumerateArray().ToList();
        Assert.True(cases.Count >= 50);
        var library = new GamePackLibrary(
            () => GamePackLibrary.EmbeddedPacks().Where(pack => pack.Name == "mafia-the-old-country.json.gz"), null);
        Assert.NotNull(PackLookup.Match(library, document.RootElement.GetProperty("warmUp").GetString()!));
        Assert.Equal("mafia-the-old-country", library.SearchScope);
        var watch = System.Diagnostics.Stopwatch.StartNew();
        foreach (var item in cases)
        {
            var screen = item.GetProperty("screen").GetString()!;
            var expected = item.GetProperty("turkish").ValueKind == JsonValueKind.Null ? null : item.GetProperty("turkish").GetString();
            Assert.True(expected == PackLookup.Match(library, screen)?.Text, $"{screen} => {PackLookup.Match(library, screen)?.Text} (beklenen {expected})");
        }
        Console.WriteLine($"Mafia bulanık arama: satır başına {watch.Elapsed.TotalMilliseconds / cases.Count:F2} ms");
    }

    /// <summary>En büyük pakette (GTA V) bulanık arama da hızlı.</summary>
    [Fact]
    public void FuzzySearchIsFastInTheLargestPack()
    {
        var library = new GamePackLibrary(() => GamePackLibrary.EmbeddedPacks().Where(pack => pack.Name == "gta-v.json.gz"), null);
        Assert.NotNull(PackLookup.Match(library, "Are you listening to me?"));
        string[] lines = ["Wh4t the fück are y0u doing here, man? Get öut of my house!", "Mich ael, I tbink we need to tälk about this",
            "Yöu know what, Franklin? You're a good kid, but you gotta lısten", "Lâmar, get in the c ar, we're late!"];
        var watch = System.Diagnostics.Stopwatch.StartNew();
        for (var round = 0; round < 25; round++)
            foreach (var line in lines) PackLookup.Match(library, line);
        var each = watch.Elapsed.TotalMilliseconds / 100;
        Console.WriteLine($"GTA V bulanık arama: satır başına {each:F2} ms");
        Assert.True(each < 50, $"{each} ms");
    }

    private static string Fixture(string name, [System.Runtime.CompilerServices.CallerFilePath] string source = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(source)!, "..", "..", "..", "core", "Tests", "CouchSubsCoreTests", "Fixtures", name));

    /// <summary>Uygulamayla gelen Mafia paketinde konuşmacılı ve iki satırlı arama.</summary>
    [Fact]
    public void BundledPackIsSearched()
    {
        // Yalnız Mafia paketi: ortak satırlarda ("Get Down!") birleşik kitaplıkta sonraki oyunun çevirisi kazanır.
        var library = new GamePackLibrary(
            () => GamePackLibrary.EmbeddedPacks().Where(pack => pack.Name == "mafia-the-old-country.json.gz"), null);
        Assert.Equal("MARIA: Yere yat!", PackLookup.Match(library, "MARIA: Get Down!")?.Text);
        Assert.Equal("Yere yat!\nMinchia! Sana at sürmeyi yasaklamak lazım!",
            PackLookup.Match(library, "Get Down!\nMinchia! You shouldn't be allowed to ride!")?.Text);
    }
}
