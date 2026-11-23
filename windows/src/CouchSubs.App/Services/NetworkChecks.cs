// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace CouchSubs.App.Services;

/// <summary>PS5 bulunamayınca kendiliğinden yapılan bir denetimin sonucu. Okunamayan şey "Bilinmiyor"dur (uydurma yok).</summary>
public enum CheckResult { Passed, Problem, Unknown }

/// <summary>
/// "PS5 Bulunamadı" ekranının denetimleri (tuval 04, METINLER.md › 04): aynı ağ, PS5'in aramaya yanıtı, Wi-Fi bandı ve VPN
/// bu bilgisayardan okunur. Uzaktan Oynatma ve dinlenme modunda internet PS5'in ayarıdır, buradan okunamaz: Bilinmiyor.
/// </summary>
public static partial class NetworkChecks
{
    public sealed record Results(CheckResult SameNetwork, CheckResult Ps5Responds, CheckResult RemotePlay, CheckResult RestModeInternet,
        CheckResult Wifi5Ghz, CheckResult VpnOff);

    public static async Task<Results> RunAsync(bool ps5Found)
    {
        var interfaces = Safe(NetworkInterface.GetAllNetworkInterfaces) ?? [];
        var up = interfaces.Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback).ToList();
        var lan = up.Any(n => !IsVpn(n) && Safe(() => n.GetIPProperties().UnicastAddresses
            .Any(a => a.Address.AddressFamily == AddressFamily.InterNetwork && IsPrivate(a.Address.GetAddressBytes()))) == true);
        var vpn = up.Any(IsVpn);
        var band = await WifiBandAsync();
        return new Results(
            lan ? CheckResult.Passed : CheckResult.Problem,
            ps5Found ? CheckResult.Passed : CheckResult.Problem,
            CheckResult.Unknown,
            CheckResult.Unknown,
            band,
            vpn ? CheckResult.Problem : CheckResult.Passed);
    }

    private static bool IsPrivate(byte[] ip) =>
        ip[0] == 10 || (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) || (ip[0] == 192 && ip[1] == 168);

    /// <summary>Açık VPN: PPP/tünel arabirimi ya da bilinen VPN sürücüleri (Teredo ve ISATAP sayılmaz).</summary>
    private static bool IsVpn(NetworkInterface adapter)
    {
        var text = $"{adapter.Name} {adapter.Description}";
        if (text.Contains("Teredo", StringComparison.OrdinalIgnoreCase) || text.Contains("ISATAP", StringComparison.OrdinalIgnoreCase)) return false;
        return adapter.NetworkInterfaceType is NetworkInterfaceType.Ppp
               || VpnNames().IsMatch(text);
    }

    [GeneratedRegex(@"VPN|WireGuard|TAP-Windows|OpenVPN|Tailscale|ZeroTier|NordLynx|Wintun|Cisco AnyConnect|Fortinet", RegexOptions.IgnoreCase)]
    private static partial Regex VpnNames();

    /// <summary>"netsh wlan show interfaces" kanalı: 14'ten büyükse 5 GHz. Kablolu ya da okunamazsa Bilinmiyor.</summary>
    private static async Task<CheckResult> WifiBandAsync()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("netsh", "wlan show interfaces")
            {
                RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true,
            });
            if (process is null) return CheckResult.Unknown;
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            var channel = ChannelLine().Match(output);
            if (!channel.Success || !int.TryParse(channel.Groups[1].Value, out var number)) return CheckResult.Unknown;
            return number > 14 ? CheckResult.Passed : CheckResult.Problem;
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return CheckResult.Unknown;
        }
    }

    // "Channel : 36" (Türkçe Windows'ta "Kanal : 36").
    [GeneratedRegex(@"^\s*(?:Channel|Kanal)\s*:\s*(\d+)", RegexOptions.Multiline | RegexOptions.IgnoreCase)]
    private static partial Regex ChannelLine();

    private static T? Safe<T>(Func<T> read)
    {
        try { return read(); }
        catch (NetworkInformationException) { return default; }
    }
}
