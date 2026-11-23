// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Aynı mesajın OCR'la bir iki harfi farklı okunuşu yeni mesaj sayılmaz: bilinen çevirisi kullanılır, çeviri gidip gelmez.
/// Sayı ya da olumsuzluk değiştiren okuma ve kısa satır aynı mesaj sayılmaz (Mac GamePhoneStabilityTests ve Android
/// PhoneSteadyTest ile aynı deneme).
/// </summary>
public class PhoneSteadyTests
{
    private static readonly Dictionary<string, string> Known = new()
    {
        ["Did you hear back from the guy at the marina?"] = "Marinadaki adamdan haber aldın mı?",
        ["Meet me at 5 by the docks"] = "Benimle 5'te rıhtımda buluş",
        ["I can do that tonight"] = "Bunu bu gece yapabilirim",
        ["Ok"] = "Tamam",
    };

    [Fact]
    public void SameMessageReadSlightlyDifferentlyKeepsItsTranslation()
    {
        Assert.Equal("Marinadaki adamdan haber aldın mı?", PhoneSteady.Translation("Did you hear back from the guy at the rnarina?", Known));
        Assert.Equal("Marinadaki adamdan haber aldın mı?", PhoneSteady.Translation("Did you hear back frorn the guy at the marina", Known));
        Assert.Null(PhoneSteady.Translation("Meet me at 6 by the docks", Known));
        Assert.Null(PhoneSteady.Translation("I can't do that tonight", Known));
        Assert.Null(PhoneSteady.Translation("On", Known));
        Assert.Null(PhoneSteady.Translation("Where are you going tonight?", Known));
        Assert.Equal("Tamam", PhoneSteady.Translation("Ok", Known));
    }
}
