// SPDX-License-Identifier: AGPL-3.0-only

using System.Net.Sockets;
using CouchSubs.Core.LgTv;
using Xunit;
using Tv = CouchSubs.Core.LgTv.LgTv;

namespace CouchSubs.Core.Tests;

/// <summary>Mac core TVReachTests ile aynı senaryolar.</summary>
public class TvReachTests
{
    private static readonly Tv Saved = new("LG TV", "192.168.1.238");

    private static Func<Task<IReadOnlyList<Tv>>> Found(params Tv[] tvs) => () => Task.FromResult<IReadOnlyList<Tv>>(tvs);

    /// <summary>beta.89: TV 192.168.1.238'den .156'ya geçmişti; eski adres sessiz, TV ağda yeni adreste bulunur.</summary>
    [Fact]
    public async Task SilentAddressFindsSameTvAtNewAddress()
    {
        var moved = new Tv("LG TV", "192.168.1.156");
        var (location, found) = await TvReach.LocateAsync(Saved, _ => Task.FromResult(false),
            Found(moved, new Tv("Salon", "192.168.1.40", TvBrand.Samsung)));
        Assert.Equal(TvLocation.Moved, location);
        Assert.Equal(moved, found);
    }

    [Fact]
    public async Task RespondingAddressIsNotSearched()
    {
        var searched = false;
        var (location, found) = await TvReach.LocateAsync(Saved, _ => Task.FromResult(true),
            () => { searched = true; return Task.FromResult<IReadOnlyList<Tv>>([]); });
        Assert.Equal(TvLocation.Here, location);
        Assert.Null(found);
        Assert.False(searched);
    }

    [Fact]
    public async Task SilentAndNotFoundIsSilent()
    {
        var (location, found) = await TvReach.LocateAsync(Saved, _ => Task.FromResult(false), Found());
        Assert.Equal(TvLocation.Silent, location);
        Assert.Null(found);
    }

    /// <summary>Ağda iki tanınmayan LG varsa tahmin edilmez (başka odadaki TV'ye geçilmez).</summary>
    [Fact]
    public async Task DoesNotGuessBetweenTwoUnknownTvs()
    {
        var (location, _) = await TvReach.LocateAsync(Saved, _ => Task.FromResult(false),
            Found(new Tv("Yatak odası", "192.168.1.20"), new Tv("Mutfak", "192.168.1.21")));
        Assert.Equal(TvLocation.Silent, location);
    }

    [Fact]
    public void RefusedConnectionCountsAsAnswer()
    {
        Assert.True(TvReach.IsRefusal(SocketError.ConnectionRefused));
        Assert.True(TvReach.IsRefusal(SocketError.ConnectionReset));
        Assert.False(TvReach.IsRefusal(SocketError.TimedOut));
        Assert.False(TvReach.IsRefusal(SocketError.HostUnreachable));
        Assert.False(TvReach.IsRefusal(SocketError.NetworkUnreachable));
    }

    /// <summary>Yerel makinede kapalı kapı hemen reddeder: "yanıt veriyor" sayılır (TV açık ama o kapı kapalı).</summary>
    [Fact]
    public async Task LocalRefusalIsAnAnswer()
    {
        // Windows reddi SYN'i yeniden deneyerek ~2 sn'de bildirir; süre buna göre geniş.
        Assert.True(await TvReach.AnswersAsync("127.0.0.1", 9, TimeSpan.FromSeconds(6)));
    }

    [Fact]
    public void Texts()
    {
        Assert.Equal("TV bu adreste yanıt vermiyor (açık ve aynı ağda mı?)", TvReach.NotRespondingLine);
        Assert.Equal("TV'nin adresi değişmiş: 192.168.1.238 → 192.168.1.156", TvReach.MovedLine("192.168.1.238", "192.168.1.156"));
    }
}
