// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Bağlantı kopunca kullanıcı uygulamayı kapatıp açıyordu: "Yeniden bağlan" düğmesi bırakılan oturumda hemen, süren
/// denemelerde 45 sn sonra görünür (core ReconnectOfferTests.swift ve Android ReconnectOfferTest ile aynı durumlar).
/// </summary>
public sealed class ReconnectOfferTests
{
    private static readonly DateTime Start = DateTime.UnixEpoch.AddSeconds(1000);

    [Fact]
    public void HiddenWhileStreaming()
    {
        var offer = new ReconnectOffer();
        offer.Update(live: true, Start);
        Assert.False(offer.Shows(gaveUp: false, Start.AddSeconds(600)));
    }

    [Fact]
    public void ShowsAfterLongReconnecting()
    {
        var offer = new ReconnectOffer();
        offer.Update(live: false, Start);
        // Ara durumlar (bağlanıyor ↔ koptu) süreyi baştan başlatmaz.
        offer.Update(live: false, Start.AddSeconds(20));
        Assert.False(offer.Shows(gaveUp: false, Start.AddSeconds(44)));
        Assert.True(offer.Shows(gaveUp: false, Start + ReconnectOffer.After));
        offer.Update(live: true, Start.AddSeconds(50));
        Assert.False(offer.Shows(gaveUp: false, Start.AddSeconds(60)));
    }

    [Fact]
    public void ShowsAtOnceWhenTheSessionGaveUp()
    {
        var offer = new ReconnectOffer();
        offer.Update(live: false, Start);
        Assert.True(offer.Shows(gaveUp: true, Start));
    }

    [Fact]
    public void ResetRestartsTheClock()
    {
        var offer = new ReconnectOffer();
        offer.Update(live: false, Start);
        offer.Reset(Start.AddSeconds(100));
        Assert.False(offer.Shows(gaveUp: false, Start.AddSeconds(120)));
        Assert.True(offer.Shows(gaveUp: false, Start.AddSeconds(145)));
        offer.Reset();
        Assert.False(offer.Shows(gaveUp: false, Start.AddSeconds(1000)));
    }
}
