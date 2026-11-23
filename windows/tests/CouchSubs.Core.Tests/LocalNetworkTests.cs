// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using CouchSubs.Core.LgTv;
using Xunit;

namespace CouchSubs.Core.Tests;

public class LocalNetworkTests
{
    [Fact]
    public void ScanCoversTheWholeHomeNetworkExceptThisComputer()
    {
        var targets = LocalNetwork.ScanTargets([IPAddress.Parse("192.168.1.40")]).ToList();
        Assert.Equal(253, targets.Count);
        Assert.Contains("192.168.1.1", targets);
        Assert.Contains("192.168.1.254", targets);
        Assert.DoesNotContain("192.168.1.40", targets);
    }

    [Fact]
    public void TwoAdaptersOnTheSameNetworkAreScannedOnce()
    {
        var targets = LocalNetwork.ScanTargets([IPAddress.Parse("10.0.0.5"), IPAddress.Parse("10.0.0.6")]).ToList();
        Assert.Equal(targets.Count, targets.Distinct().Count());
    }

    [Fact]
    public void OnlyHomeNetworkAddressesArePrivate()
    {
        Assert.True(LocalNetwork.IsPrivate(IPAddress.Parse("192.168.0.10")));
        Assert.True(LocalNetwork.IsPrivate(IPAddress.Parse("172.20.1.1")));
        Assert.True(LocalNetwork.IsPrivate(IPAddress.Parse("10.1.2.3")));
        Assert.False(LocalNetwork.IsPrivate(IPAddress.Parse("8.8.8.8")));
        Assert.False(LocalNetwork.IsPrivate(IPAddress.Parse("172.32.0.1")));
    }

    // Host PC IP: VPN ve sanal bağdaştırıcılar seçilmez (Duhan Ay, 2026-11-13).
    private static LocalNetwork.AdapterAddress Adapter(string name, string description, string address, bool gateway,
        System.Net.NetworkInformation.NetworkInterfaceType type = System.Net.NetworkInformation.NetworkInterfaceType.Ethernet) =>
        new(name, description, type, IPAddress.Parse(address), IPAddress.Parse("255.255.255.0"), gateway);

    private static readonly LocalNetwork.AdapterAddress Wifi = Adapter("Wi-Fi", "Intel(R) Wi-Fi 6 AX201 160MHz", "192.168.1.34", true,
        System.Net.NetworkInformation.NetworkInterfaceType.Wireless80211);
    private static readonly LocalNetwork.AdapterAddress HyperV = Adapter("vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter", "172.24.80.1", false);
    private static readonly LocalNetwork.AdapterAddress VirtualBox = Adapter("Ethernet 2", "VirtualBox Host-Only Ethernet Adapter", "192.168.56.1", false);
    private static readonly LocalNetwork.AdapterAddress Vpn = Adapter("ProtonVPN", "WireGuard Tunnel", "10.2.0.2", true);

    [Fact]
    public void TheAdapterOnTheTvsNetworkIsChosen() =>
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, VirtualBox, Vpn, Wifi], IPAddress.Parse("192.168.1.171")));

    [Fact]
    public void WithoutATvAddressWifiWinsOverVpnAndVirtualMachines()
    {
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, VirtualBox, Vpn, Wifi], null));
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([Vpn, HyperV, Wifi], IPAddress.Parse("10.0.0.9")));
    }

    // Aynı ağda Wi-Fi ve Ethernet: alt ağ tahmini ilkini seçiyordu, TV ise diğerinden gelen bağlantıyı görüyordu (#343).
    private static readonly LocalNetwork.AdapterAddress Cable = Adapter("Ethernet", "Realtek PCIe GbE", "192.168.1.35", true);

    [Fact]
    public void TheAddressTheTvSeesWinsOverTheSubnetGuess()
    {
        var tv = IPAddress.Parse("192.168.1.171");
        Assert.Equal("192.168.1.35", LocalNetwork.ChooseComputerAddress([Wifi, Cable], tv, IPAddress.Parse("192.168.1.35")));
        // Hyper-V dış anahtarında gerçek adres sanal adlı bağdaştırıcıdadır; yol oradan geçiyorsa o seçilir.
        Assert.Equal("172.24.80.1", LocalNetwork.ChooseComputerAddress([HyperV, Wifi], tv, IPAddress.Parse("172.24.80.1")));
    }

    [Fact]
    public void AnUnknownRouteFallsBackToTheSubnetGuess()
    {
        var tv = IPAddress.Parse("192.168.1.171");
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, Wifi], tv, null));
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, Wifi], tv, IPAddress.Loopback));
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, Wifi], tv, IPAddress.Any));
        // Hiçbir açık bağdaştırıcıya ait olmayan adres (bağdaştırıcı listesi eskidi) kullanılmaz.
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([HyperV, Wifi], tv, IPAddress.Parse("10.9.9.9")));
    }

    [Fact]
    public void RouteSourceTowardsThisComputerIsLoopback() =>
        Assert.Equal(IPAddress.Loopback, LocalNetwork.RouteSourceAddress(IPAddress.Loopback));

    [Fact]
    public void AVirtualAdapterIsUsedOnlyWhenNothingElseExists()
    {
        Assert.Equal("10.2.0.2", LocalNetwork.ChooseComputerAddress([Vpn], null));
        Assert.Null(LocalNetwork.ChooseComputerAddress([], null));
    }

    [Fact]
    public void VirtualAdaptersAreRecognised()
    {
        Assert.True(LocalNetwork.IsVirtual(HyperV.Name, HyperV.Description, HyperV.Type));
        Assert.True(LocalNetwork.IsVirtual(VirtualBox.Name, VirtualBox.Description, VirtualBox.Type));
        Assert.True(LocalNetwork.IsVirtual(Vpn.Name, Vpn.Description, Vpn.Type));
        Assert.False(LocalNetwork.IsVirtual(Wifi.Name, Wifi.Description, Wifi.Type));
        Assert.False(LocalNetwork.IsVirtual("Ethernet", "Realtek PCIe GbE Family Controller", System.Net.NetworkInformation.NetworkInterfaceType.Ethernet));
    }

    // X (Samsung M7): TV adresi bilinmeden seçilen adres bağdaştırıcı listesindeki ilk "gerçek" adresti.
    private static readonly LocalNetwork.AdapterAddress Warp = Adapter("CloudflareWARP", "Cloudflare WARP Interface Tunnel", "172.16.0.2", true);
    private static readonly LocalNetwork.AdapterAddress Mullvad = Adapter("Mullvad", "Mullvad Tunnel", "10.64.0.5", true);
    private static readonly LocalNetwork.AdapterAddress Parallels = Adapter("Ethernet 3", "Parallels Shared Networking Adapter", "10.211.55.2", false);
    private static readonly LocalNetwork.AdapterAddress Clash = Adapter("Meta", "Meta Tunnel", "198.18.0.1", true);
    private static readonly LocalNetwork.AdapterAddress Tethering = Adapter("Ethernet 4", "Remote NDIS based Internet Sharing Device", "192.168.42.10", true);
    private static readonly LocalNetwork.AdapterAddress DirectLink = Adapter("Ethernet 5", "Realtek USB GbE", "192.168.0.10", false);

    [Fact]
    public void MoreVpnAndSharingAdaptersAreRecognised()
    {
        foreach (var adapter in new[] { Warp, Mullvad, Parallels, Clash, Tethering })
            Assert.True(LocalNetwork.IsVirtual(adapter.Name, adapter.Description, adapter.Type) ||
                        LocalNetwork.HomeAddresses([adapter]).Count == 0, adapter.Description);
        Assert.Empty(LocalNetwork.HomeAddresses([Warp, Mullvad, Parallels, Clash, Tethering]));
    }

    [Fact]
    public void WithoutATvAddressWifiWithAGatewayWinsOverEarlierAdapters()
    {
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([Warp, Tethering, Parallels, Clash, DirectLink, Wifi], null));
        // İnternete çıkılan bağdaştırıcı (varsayılan yol) biliniyorsa o.
        Assert.Equal("192.168.1.35", LocalNetwork.ChooseComputerAddress([Wifi, Cable], null, null, IPAddress.Parse("192.168.1.35")));
        // Varsayılan yol VPN'den geçiyorsa (WARP) VPN adresi seçilmez.
        Assert.Equal("192.168.1.34", LocalNetwork.ChooseComputerAddress([Warp, Wifi], null, null, IPAddress.Parse("172.16.0.2")));
    }

    [Fact]
    public void HomeAddressesListEveryRealHomeNetworkAddressBestFirst()
    {
        Assert.Equal(["192.168.1.34", "192.168.1.35", "192.168.0.10"],
            LocalNetwork.HomeAddresses([HyperV, DirectLink, Warp, Wifi, Vpn, Cable]));
        Assert.Empty(LocalNetwork.HomeAddresses([HyperV, Vpn]));
    }
}
