// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using CouchSubs.Core;

namespace CouchSubs.RemotePlay;

/// <summary>Yerel ağdaki PS5'leri bulur ve uyutulmuş olanı uyandırır.</summary>
public static class ConsoleDiscovery
{
    internal const string Broadcast = "255.255.255.255";

    /// <summary><paramref name="host"/> verilirse yalnız o adrese sorulur (genel yayın bazı ağlarda engellenebiliyor).
    /// İptal, beklemeyi bırakır; arka plandaki arama süresi dolunca kendiliğinden biter.</summary>
    public static Task<IReadOnlyList<ConsoleInfo>> DiscoverAsync(string? host = null, TimeSpan? timeout = null, CancellationToken ct = default)
    {
        var duration = timeout ?? TimeSpan.FromSeconds(3);
        // Arama süre boyunca uyuyarak bekler; iş havuzunu tutmamak için ayrı iş parçacığında çalışır.
        return Task.Factory.StartNew(() => Discover(host, duration), CancellationToken.None,
                                     TaskCreationOptions.LongRunning, TaskScheduler.Default).WaitAsync(ct);
    }

    /// <summary>Taramada bulunanlar arasından kayıtlı PS5'i seçer: adı (kayıtta PS5'in verdiği ad) tek eşleşen.
    /// Emin olunamıyorsa null (yanlış konsola bağlanmaya çalışmaktansa adres değiştirilmez). Eskiden ağda tek PS5 varsa
    /// adına bakılmadan o seçiliyordu; aynı evde iki PS5 varken uygulama diğerine geçiyordu (GitHub #425).</summary>
    internal static ConsoleInfo? PickMoved(IReadOnlyList<ConsoleInfo> found, string name)
    {
        var named = found.Where(c => c.Name == name).ToList();
        return named.Count == 1 ? named[0] : null;
    }

    /// <summary>Aramaya yanıt veren PS5 kayıtlı PS5 mi (ad eşleşmesi; kayıtta ad yoksa her yanıt kabul edilir).</summary>
    internal static bool IsRegistered(ConsoleInfo info, string name) => name.Length == 0 || info.Name == name;

    /// <summary>PS5'te o an çalışan oyun: yalnız bağlı PS5'in adresine sorulur (ortak havuz için; bkz. <see cref="RunningGame"/>).</summary>
    public static async Task<RunningGame?> RunningGameAsync(string host, CancellationToken ct = default)
    {
        var found = await DiscoverAsync(host, TimeSpan.FromSeconds(2), ct).ConfigureAwait(false);
        return found.Count == 0 ? null : RunningGame.Create(found[0].RunningAppTitleId, found[0].RunningAppName);
    }

    /// <summary>Kayıtlı PS5'i dinlenme modundan uyandırır.</summary>
    public static void Wake(RegisteredConsole console)
    {
        var credential = console.WakeCredential ?? throw new InvalidOperationException("Registration key is not a wake credential");
        NativeMethods.EnsureInitialized();
        var result = NativeMethods.cs_wake(console.Host, credential);
        if (result != 0) throw new InvalidOperationException($"PS5 wake-up could not be sent ({result})");
    }

    private sealed class Collector
    {
        public readonly Dictionary<string, ConsoleInfo> Hosts = [];
    }

    /// <summary>Bloklayan arama (oturum kuyruğu ve DiscoverAsync kullanır).</summary>
    internal static unsafe IReadOnlyList<ConsoleInfo> Discover(string? host, TimeSpan timeout)
    {
        NativeMethods.EnsureInitialized();
        // Adres verilmezse yerel ağdaki her adrese ayrı ayrı sorulur; genel yayına PS5'ten yanıt
        // gelmeyebiliyor, tek tek sorgu her ağda çalışıyor.
        var targets = host is null ? LocalTargets() : [host];
        var collector = new Collector();
        var handle = GCHandle.Alloc(collector);
        var strings = new nint[targets.Count];
        try
        {
            for (var i = 0; i < targets.Count; i++) strings[i] = Marshal.StringToCoTaskMemUTF8(targets[i]);
            delegate* unmanaged[Cdecl]<byte*, byte*, int, byte*, byte*, nint, void> callback = &OnConsole;
            fixed (nint* pointer = strings)
                NativeMethods.cs_discover_ex(pointer, strings.Length, (int)timeout.TotalMilliseconds, (nint)callback, GCHandle.ToIntPtr(handle));
        }
        finally
        {
            foreach (var pointer in strings) Marshal.FreeCoTaskMem(pointer);
            handle.Free();
        }
        lock (collector) return [.. collector.Hosts.Values.OrderBy(c => c.Host, StringComparer.Ordinal)];
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void OnConsole(byte* host, byte* name, int awake, byte* titleId, byte* appName, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is not Collector collector || NativeMethods.Utf8(host) is not { } address) return;
            var info = new ConsoleInfo(address, NativeMethods.Utf8(name) ?? "PS5", awake != 0, NativeMethods.Utf8(titleId), NativeMethods.Utf8(appName));
            lock (collector) collector.Hosts[info.Host] = info;
        }
        catch
        {
            // Yerel iş parçacığına istisna sızmamalı.
        }
    }

    /// <summary>Bağlı IPv4 ağlarındaki tüm adresler (en çok /22, yani 1022 adres) ve genel yayın.</summary>
    internal static IReadOnlyList<string> LocalTargets()
    {
        var result = new List<string>();
        try
        {
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var unicast in adapter.GetIPProperties().UnicastAddresses)
                {
                    if (unicast.Address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(unicast.Address)) continue;
                    var mask = unicast.IPv4Mask;
                    if (mask is null || mask.Equals(IPAddress.Any)) continue;
                    result.AddRange(Hosts(ToUInt32(unicast.Address), ToUInt32(mask)).Select(ToText));
                }
            }
        }
        catch (NetworkInformationException)
        {
            // Ağ bilgisi okunamazsa yalnız genel yayın kalır.
        }
        result.Add(Broadcast);
        return [.. result.Distinct()];
    }

    /// <summary>Ağdaki diğer adresler (ağ ve yayın adresi hariç); /22'den büyük ağlarda boş.</summary>
    internal static IReadOnlyList<uint> Hosts(uint address, uint netmask)
    {
        var hostCount = ~netmask;
        if (hostCount <= 1 || hostCount > 1023) return [];
        var network = address & netmask;
        var result = new List<uint>((int)hostCount);
        for (uint i = 1; i < hostCount; i++)
            if (network + i != address) result.Add(network + i);
        return result;
    }

    internal static uint ToUInt32(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];
    }

    internal static string ToText(uint address) => $"{address >> 24}.{(address >> 16) & 0xFF}.{(address >> 8) & 0xFF}.{address & 0xFF}";
}
