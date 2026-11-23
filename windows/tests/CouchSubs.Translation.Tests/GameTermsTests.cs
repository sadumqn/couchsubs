// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Translation.Tests;

/// <summary>
/// Oyun terimleri örnek seti (Mac/iPhone: GameTermsTests, Android: GameTermsTest; aynı satırlar). Kullanıcı şikâyetleri:
/// "Toss a smoke" → "sigara at", ünlem satırları ve büyük harfli satırlar sözcük sözcük çevriliyordu. Gerçek OPUS-MT
/// burada çağrılmaz: modele giden metin ve hazır satırlar sınanır.
/// </summary>
public class GameTermsTests
{
    private static string Translate(string sentence, Func<string, string> engine) =>
        FreeTranslation.Translate(sentence, null, Glossary.BuiltIn,
            text => SubtitleSegmenter.NormalizeCase(text, Glossary.BuiltIn.CapitalWords), engine);

    [Theory]
    [InlineData("Toss a smoke!", "Sis bombası at!")]
    [InlineData("Reloading!", "Şarjör değiştiriyorum!")]
    [InlineData("RELOADING!", "Şarjör değiştiriyorum!")]
    [InlineData("Frag out!", "Bomba atıyorum!")]
    [InlineData("Cover me, I’m reloading!", "Şarjör değiştiriyorum, koru beni!")]
    [InlineData("Man down!", "Yaralı var!")]
    [InlineData("Get down!", "Yere yat!")]
    [InlineData("Move up.", "İlerleyin.")]
    [InlineData("- Contact!", "Düşman var!")]
    public void CalloutsUseTheirTurkishLine(string english, string turkish)
    {
        var calls = new List<string>();
        Assert.Equal(turkish, Translate(english, text => { calls.Add(text); return "?"; }));
        Assert.Empty(calls);
    }

    [Theory]
    [InlineData("Toss a smoke and move up.", "Throw a Zarmon and move up.", "Bir Zarmon at ve ilerle.", "Bir sis bombası at ve ilerle.")]
    [InlineData("THROW A FLASHBANG IN THERE!", "Throw a Zarmon in there!", "Oraya bir Zarmon at!", "Oraya bir flaş bombası at!")]
    [InlineData("Pop smoke, we're leaving.", "Throw a Zarmon, we're leaving.", "Bir Zarmon at, gidiyoruz.", "Bir sis bombası at, gidiyoruz.")]
    [InlineData("Hostiles on the bridge.", "Enemies on the bridge.", "Köprüde düşmanlar.", "Köprüde düşmanlar.")]
    [InlineData("Grab the medkit before you go.", "Grab the Zarmon before you go.", "Gitmeden Zarmon'u al.", "Gitmeden ilk yardım çantasını al.")]
    public void SlangAndWeaponTermsInLongerLines(string english, string sent, string engineSays, string turkish)
    {
        var calls = new List<string>();
        var result = Translate(english, text => { calls.Add(text); return engineSays; });
        Assert.Equal(sent, calls[0]);
        Assert.Equal(turkish, result);
    }

    [Theory]
    [InlineData("I smell smoke.")]
    [InlineData("Turn on your flashlight.")]
    [InlineData("Where is the grenade launcher?")]
    [InlineData("I'm covering you.")]
    public void OrdinarySentencesAreUnchanged(string english)
    {
        var calls = new List<string>();
        Translate(english, text => { calls.Add(text); return text; });
        Assert.Equal([english], calls);
    }

    [Fact]
    public void UserGlossaryCanAddLinesAndPhrases()
    {
        var user = Glossary.Parse("""{ "phrases": { "nerf": "weaken" }, "lines": { "GG!": "İyi oyundu" } }""");
        var merged = Glossary.Merge([Glossary.BuiltIn, user]);
        Assert.Equal("İyi oyundu", merged.Line("gg"));
        Assert.Equal("Weaken the boss", merged.Plain("Nerf the boss"));
        Assert.NotEqual(Glossary.BuiltIn.Fingerprint, merged.Fingerprint);
        Assert.True(merged.Rewrites("They nerf it."));
        Assert.False(merged.Rewrites("Nerfed."));
        // Bozuk düzenli ifade alınmaz.
        Assert.Equal("( a", Glossary.Parse("""{ "phrases": { "(": "x" } }""").Plain("( a"));
    }

    [Fact]
    public void CacheKeyFollowsLinesAndPhrases()
    {
        var glossary = Glossary.BuiltIn;
        Assert.StartsWith(glossary.Fingerprint, FreeTranslation.CacheKey("Reloading!", null, glossary));
        Assert.StartsWith(glossary.Fingerprint, FreeTranslation.CacheKey("Toss a smoke and go.", null, glossary));
        Assert.Equal("I smell it.", FreeTranslation.CacheKey("I smell it.", null, glossary));
    }

    /// <summary>Mac/iPhone ve Android'le aynı iz: üç platformun önbellek anahtarları aynı kalır.</summary>
    [Fact]
    public void FingerprintMatchesTheOtherPlatforms() => Assert.Equal("g978a414e", Glossary.BuiltIn.Fingerprint);
}
