// SPDX-License-Identifier: AGPL-3.0-only

using System.Net.Sockets;

namespace CouchSubs.Core.LgTv;

/// <summary>Kayıtlı TV'nin yeri (<see cref="TvReach.LocateAsync"/>).</summary>
public enum TvLocation
{
    /// <summary>Kayıtlı adreste bir şey yanıt veriyor (kapı açık ya da bağlantıyı reddediyor).</summary>
    Here,
    /// <summary>Kayıtlı adres sessiz; aynı TV ağda yeni adreste bulundu.</summary>
    Moved,
    /// <summary>Kayıtlı adres sessiz ve TV ağda bulunamadı.</summary>
    Silent,
}

/// <summary>
/// Kayıtlı TV adresi yanıt veriyor mu, vermiyorsa TV ağda yeni bir adreste mi (Mac/iPhone <c>TVReach</c>, Android
/// <c>TvReach</c> ile aynı kural). beta.89 (Mac): modem LG TV'ye yeni adres vermişti (192.168.1.238 → .156); uygulama eski
/// adrese gidip "geliştirici modu kapalı" ve "Key Server kapalı" diyordu. Hiçbir kapı yanıt vermiyorsa (zaman aşımı, adreste
/// cihaz yok; "reddedildi" yanıt sayılır) TV ağda yeniden aranır, aynı TV bulunursa adres güncellenir.
/// </summary>
public static class TvReach
{
    public const string NotRespondingLine = "TV bu adreste yanıt vermiyor (açık ve aynı ağda mı?)";

    public static string MovedLine(string oldHost, string newHost) => $"TV'nin adresi değişmiş: {oldHost} → {newHost}";

    /// <summary>TV'nin açıkken her zaman dinlediği (ya da reddettiği) kapılar.</summary>
    public static IReadOnlyList<int> Ports(TvBrand brand) => brand switch
    {
        TvBrand.Lg => new[] { 3000, 3001, 9922, 9991, 1990 },
        TvBrand.Samsung => new[] { 8001, 8002, 26101, 9197 },
        _ => new[] { 5555, 6466, 6467, 8008, 8009 },
    };

    /// <summary>Kayıtlı adres yanıt vermiyorsa TV'yi ağda arar. Adresi olmayan kayıtta bir şey yapılmaz (Here).</summary>
    public static async Task<(TvLocation Location, LgTv? Moved)> LocateAsync(
        LgTv saved, Func<string, Task<bool>> responds, Func<Task<IReadOnlyList<LgTv>>> search)
    {
        if (string.IsNullOrEmpty(saved.Host) || await responds(saved.Host)) return (TvLocation.Here, null);
        var moved = Relocated(saved, await search());
        return moved is null ? (TvLocation.Silent, null) : (TvLocation.Moved, moved);
    }

    /// <summary>Bulunanlar içinde kayıtlı TV'nin yeni adresi; emin olunamazsa null (başka odadaki TV'ye geçilmez).</summary>
    public static LgTv? Relocated(LgTv saved, IReadOnlyList<LgTv> found) => TvLocator.Moved(saved, found);

    /// <summary>Kapılardan biri bağlantıyı kabul eder ya da reddederse TV yanıt veriyor sayılır.</summary>
    public static async Task<bool> RespondsAsync(string host, TvBrand brand, TimeSpan? timeout = null)
    {
        if (string.IsNullOrEmpty(host)) return false;
        // Windows reddedilen bağlantıyı (RST) ~2 sn yeniden dener; reddi "sessiz" saymamak için süre 3 sn.
        var limit = timeout ?? TimeSpan.FromSeconds(3);
        var tasks = Ports(brand).Select(port => AnswersAsync(host, port, limit)).ToList();
        while (tasks.Count > 0)
        {
            var done = await Task.WhenAny(tasks);
            if (await done) return true;
            tasks.Remove(done);
        }
        return false;
    }

    /// <summary>Kapı bağlantıyı kabul etti ya da reddetti mi (ikisi de adreste bir cihaz olduğunu gösterir).</summary>
    public static async Task<bool> AnswersAsync(string host, int port, TimeSpan timeout)
    {
        using var cancel = new CancellationTokenSource(timeout);
        using var client = new TcpClient();
        try
        {
            await client.ConnectAsync(host, port, cancel.Token);
            return true;
        }
        catch (SocketException error)
        {
            return IsRefusal(error.SocketErrorCode);
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>"Bağlantı reddedildi" ya da sıfırlandı: adreste cihaz var. Zaman aşımı, yol yok: sessiz.</summary>
    public static bool IsRefusal(SocketError code) => code is SocketError.ConnectionRefused or SocketError.ConnectionReset;
}
