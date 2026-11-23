// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace CouchSubs.Core.LgTv;

/// <summary>Bilgisayarın yerel ağ adresleri ve TV aramak için taranacak komşu adresler.</summary>
public static class LocalNetwork
{
    /// <summary>Açık ağ bağdaştırıcılarının özel (ev ağı) IPv4 adresleri.</summary>
    public static IReadOnlyList<IPAddress> PrivateAddresses()
    {
        try
        {
            return
            [
                .. NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback
                                && !IsContainerBridge(n.Name))
                    .SelectMany(n => n.GetIPProperties().UnicastAddresses)
                    .Select(a => a.Address)
                    .Where(a => a.AddressFamily == AddressFamily.InterNetwork && IsPrivate(a)),
            ];
        }
        catch (NetworkInformationException)
        {
            return [];
        }
    }

    /// <summary>
    /// Linux'ta Docker ve sanal makine köprüleri (docker0, br-…, veth…, virbr…) de özel adres taşır ama arkalarında TV
    /// ya da PS5 yoktur; her biri ağ taramasına 254 adres ekleyip aramayı yarım dakikaya çıkarıyordu.
    /// </summary>
    public static bool IsContainerBridge(string interfaceName) =>
        OperatingSystem.IsLinux() && (interfaceName.StartsWith("docker", StringComparison.Ordinal) || interfaceName.StartsWith("br-", StringComparison.Ordinal)
                                      || interfaceName.StartsWith("veth", StringComparison.Ordinal) || interfaceName.StartsWith("virbr", StringComparison.Ordinal));

    /// <summary>Açık bir bağdaştırıcının IPv4 adresi; bu bilgisayarın TV'ye söylenecek adresi bunların arasından seçilir.</summary>
    public sealed record AdapterAddress(string Name, string Description, NetworkInterfaceType Type, IPAddress Address, IPAddress Mask, bool HasGateway);

    /// <summary>Açık (loopback dışı) bağdaştırıcıların IPv4 adresleri.</summary>
    public static IReadOnlyList<AdapterAddress> Ipv4Adapters()
    {
        var found = new List<AdapterAddress>();
        try
        {
            foreach (var network in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (network.OperationalStatus != OperationalStatus.Up || network.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var properties = network.GetIPProperties();
                var hasGateway = properties.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));
                foreach (var unicast in properties.UnicastAddresses)
                {
                    if (unicast.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    found.Add(new AdapterAddress(network.Name, network.Description, network.NetworkInterfaceType, unicast.Address,
                        unicast.IPv4Mask ?? IPAddress.Any, hasGateway));
                }
            }
        }
        catch (NetworkInformationException) { }
        return found;
    }

    /// <summary>Adında ya da açıklamasında bunlardan biri geçen bağdaştırıcı sanaldır (VPN, sanal makine, WSL…).</summary>
    private static readonly string[] VirtualMarkers =
    [
        "virtual", "vethernet", "hyper-v", "virtualbox", "vmware", "vmnet", "wsl", "docker", "tailscale", "zerotier",
        "wireguard", "wintun", "tap-", "tap ", "openvpn", "vpn", "hamachi", "radmin", "nordlynx", "forticlient",
        "fortinet", "anyconnect", "globalprotect", "pangp", "npcap", "loopback", "bluetooth", "teredo", "isatap",
        // Cloudflare WARP ("CloudflareWARP", 172.16.0.2), Mullvad, Parallels, Clash/sing-box TUN ("Meta"), ZScaler, NetBird.
        "cloudflare", "warp", "mullvad", "parallels", "clash", "sing-box", "singbox", "mihomo", "meta tunnel", "v2ray",
        "zscaler", "netbird", "outline", "windscribe", "surfshark", "expressvpn", "proton",
        // Telefonla USB internet paylaşımı (RNDIS) ve Windows Mobil etkin nokta: TV bu ağlarda değildir.
        "rndis", "remote ndis", "wi-fi direct", "wan miniport", "kernel debug",
    ];

    /// <summary>
    /// VPN, sanal makine ve WSL bağdaştırıcıları da 192.168.x.x/10.x.x.x adresi taşır ama TV onlara ulaşamaz; Samsung'un
    /// "Host PC IP" alanına bunlardan biri yazılınca TV bağlantıyı kesiyordu (2026-11-13, Duhan Ay, 65U8000F).
    /// </summary>
    public static bool IsVirtual(string name, string description, NetworkInterfaceType type)
    {
        if (type is NetworkInterfaceType.Tunnel or NetworkInterfaceType.Ppp) return true;
        var text = $"{name} {description}".ToLowerInvariant();
        return VirtualMarkers.Any(text.Contains);
    }

    private static bool SameSubnet(AdapterAddress adapter, IPAddress target)
    {
        var mask = adapter.Mask.GetAddressBytes();
        var address = adapter.Address.GetAddressBytes();
        var wanted = target.GetAddressBytes();
        return mask.Length == 4 && mask.Any(b => b != 0) && Enumerable.Range(0, 4).All(i => (address[i] & mask[i]) == (wanted[i] & mask[i]));
    }

    /// <summary>Clash ve sing-box TUN bağdaştırıcısı "Meta" adını taşır; yalnız tam ad eşleşir ("Metadata" sanal değil).</summary>
    private static bool IsTunName(string name) =>
        name.Equals("Meta", StringComparison.OrdinalIgnoreCase) || name.StartsWith("tun", StringComparison.OrdinalIgnoreCase)
                                                               || name.StartsWith("utun", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Gerçek bağdaştırıcılar arasında sıra: Wi-Fi ve Ethernet önce, varsayılan ağ geçidi olan önce, özel (ev ağı) adres
    /// önce. Eskiden bağdaştırıcı listesindeki ilk "gerçek" adres alınıyordu; Windows'un sırası öncelik değildir.
    /// </summary>
    private static int Rank(AdapterAddress a) =>
        (a.Type is NetworkInterfaceType.Wireless80211 or NetworkInterfaceType.Ethernet or NetworkInterfaceType.GigabitEthernet ? 0 : 4)
        + (a.HasGateway ? 0 : 2) + (IsPrivate(a.Address) ? 0 : 1);

    private static bool IsReal(AdapterAddress a) => !IsVirtual(a.Name, a.Description, a.Type) && !IsTunName(a.Name);

    /// <summary>
    /// TV'nin ulaşacağı bu bilgisayar adresi. Sıra: TV ile aynı ağdaki gerçek bağdaştırıcı, sonra varsayılan yolun
    /// (<paramref name="defaultRoute"/>, internete çıkılan bağdaştırıcı) gerçek adresi, sonra Wi-Fi/Ethernet, ağ geçidi
    /// olan, ev ağı adresi taşıyan gerçek bağdaştırıcı; sanal bağdaştırıcı ancak başka adres yoksa seçilir. TV adresi
    /// bilinmiyorsa (<paramref name="near"/> null) aynı ağ adımı atlanır.
    /// </summary>
    public static string? ChooseComputerAddress(IReadOnlyList<AdapterAddress> adapters, IPAddress? near) =>
        ChooseBySubnet(adapters, near, null);

    private static string? ChooseBySubnet(IReadOnlyList<AdapterAddress> adapters, IPAddress? near, IPAddress? defaultRoute)
    {
        var real = adapters.Where(IsReal).OrderBy(Rank).ToList();
        if (near is { AddressFamily: AddressFamily.InterNetwork })
        {
            var sameNetwork = real.FirstOrDefault(a => SameSubnet(a, near))
                              ?? adapters.FirstOrDefault(a => SameSubnet(a, near));
            if (sameNetwork is not null) return sameNetwork.Address.ToString();
        }
        if (defaultRoute is not null && real.FirstOrDefault(a => a.Address.Equals(defaultRoute) && IsPrivate(a.Address)) is { } routed)
            return routed.Address.ToString();
        var best = real.FirstOrDefault()
                   ?? adapters.FirstOrDefault(a => IsPrivate(a.Address))
                   ?? adapters.FirstOrDefault();
        return best?.Address.ToString();
    }

    /// <summary>
    /// Bu bilgisayarın gerçek (VPN ve sanal olmayan) bağdaştırıcılarındaki ev ağı adresleri, tercih sırasıyla ve
    /// tekrarsız. Birden çoksa Samsung kurulumunda TV'nin kabul etmediği durumda denenecek diğer adresler gösterilir.
    /// </summary>
    public static IReadOnlyList<string> HomeAddresses(IReadOnlyList<AdapterAddress> adapters) =>
        [.. adapters.Where(a => IsReal(a) && IsPrivate(a.Address)).OrderBy(Rank).Select(a => a.Address.ToString()).Distinct()];

    /// <summary>
    /// TV'ye giden bağlantının kaynak adresi: işletim sistemi <paramref name="target"/>'a hangi bağdaştırıcıdan çıkacaksa
    /// onun adresi. UDP soketi "bağlanır" (paket gönderilmez) ve yerel uç okunur; TCP bağlantısı da aynı adresi kullanır.
    /// Birden çok bağdaştırıcıda (Wi-Fi + Ethernet, VPN, WSL) TV'nin göreceği adres budur. Okunamazsa null.
    /// </summary>
    public static IPAddress? RouteSourceAddress(IPAddress target)
    {
        if (target.AddressFamily != AddressFamily.InterNetwork) return null;
        try
        {
            using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.Connect(new IPEndPoint(target, 8001));
            return (socket.LocalEndPoint as IPEndPoint)?.Address;
        }
        catch (SocketException)
        {
            return null;
        }
    }

    /// <summary>
    /// TV'nin göreceği bu bilgisayar adresi: TV'ye giden yolun kaynak adresi (<paramref name="routeSource"/>) açık bir
    /// bağdaştırıcınınsa o; yoksa <see cref="ChooseComputerAddress(IReadOnlyList{AdapterAddress}, IPAddress?)"/>.
    /// Alt ağ tahmini birden çok bağdaştırıcıda (aynı ağda Wi-Fi ve Ethernet, Hyper-V dış anahtarı) yanlış adresi
    /// seçebiliyordu; Samsung "Host PC IP" ile karşılaştırılan adres yanlış olunca TV bağlantıyı kesiyordu (#343).
    /// </summary>
    public static string? ChooseComputerAddress(IReadOnlyList<AdapterAddress> adapters, IPAddress? near, IPAddress? routeSource) =>
        ChooseComputerAddress(adapters, near, routeSource, null);

    /// <summary>
    /// <see cref="ChooseComputerAddress(IReadOnlyList{AdapterAddress}, IPAddress?, IPAddress?)"/>; TV adresi bilinmiyorsa
    /// <paramref name="defaultRoute"/> (internete çıkılan bağdaştırıcının adresi) gerçek bir ev ağı adresiyse o seçilir.
    /// </summary>
    public static string? ChooseComputerAddress(IReadOnlyList<AdapterAddress> adapters, IPAddress? near, IPAddress? routeSource,
        IPAddress? defaultRoute)
    {
        if (routeSource is { AddressFamily: AddressFamily.InterNetwork } source && !IPAddress.IsLoopback(source)
            && !source.Equals(IPAddress.Any) && (adapters.Count == 0 || adapters.Any(a => a.Address.Equals(source))))
            return source.ToString();
        return ChooseBySubnet(adapters, near, defaultRoute);
    }

    /// <summary>İnternete giden varsayılan yolun kaynak adresi (paket gönderilmez); TV adresi bilinmiyorken kullanılır.</summary>
    public static IPAddress? DefaultRouteSourceAddress() => RouteSourceAddress(IPAddress.Parse("1.1.1.1"));

    public static bool IsPrivate(IPAddress address)
    {
        var b = address.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168));
    }

    /// <summary>Her yerel adresin /24 ağındaki diğer adresler (kendisi hariç), tekrarsız.</summary>
    public static IEnumerable<string> ScanTargets(IEnumerable<IPAddress> locals)
    {
        var seen = new HashSet<string>();
        foreach (var local in locals)
        {
            var bytes = local.GetAddressBytes();
            for (var last = 1; last < 255; last++)
            {
                if (last == bytes[3]) continue;
                var candidate = $"{bytes[0]}.{bytes[1]}.{bytes[2]}.{last}";
                if (seen.Add(candidate)) yield return candidate;
            }
        }
    }

    /// <summary>Verilen portu açık olan adresler.</summary>
    public static async Task<IReadOnlyList<string>> HostsWithOpenPortAsync(int port, TimeSpan connectTimeout,
        CancellationToken cancellationToken = default)
    {
        var found = new System.Collections.Concurrent.ConcurrentBag<string>();
        await Parallel.ForEachAsync(ScanTargets(PrivateAddresses()),
            new ParallelOptions { MaxDegreeOfParallelism = 64, CancellationToken = cancellationToken },
            async (host, token) =>
            {
                using var client = new TcpClient();
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
                timeout.CancelAfter(connectTimeout);
                try
                {
                    await client.ConnectAsync(host, port, timeout.Token);
                    found.Add(host);
                }
                catch (Exception error) when (error is SocketException or OperationCanceledException) { }
            });
        cancellationToken.ThrowIfCancellationRequested();
        return [.. found.OrderBy(h => IPAddress.Parse(h).GetAddressBytes()[3])];
    }
}
