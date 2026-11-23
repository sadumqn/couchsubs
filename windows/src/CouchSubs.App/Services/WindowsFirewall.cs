// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections;
using System.ComponentModel;
using System.Diagnostics;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Services;

/// <summary>Özel yerel ağ izni: COM ile okunur, yalnız kullanıcının UAC onayladığı yardımcı süreçte yazılır.</summary>
/// <remarks>Velopack güncellemeleri aynı current klasörünü kullanır; kural uygulama yoluna bağlı kalır.</remarks>
internal sealed class WindowsFirewall : IFirewall
{
    internal const string ConfigureArgument = "--configure-local-firewall";

    public bool HasRule()
    {
        if (Environment.ProcessPath is not { } exe) return false;
        var store = new ComRuleStore();
        // Kurallar kayıtlı olsa da Özel profilde bütün gelen bağlantıları engelle ayarı izni geçersiz kılar.
        bool enabled = store.Policy.FirewallEnabled[LocalFirewallPolicy.PrivateProfile];
        if (enabled && (bool)store.Policy.BlockAllInboundTraffic[LocalFirewallPolicy.PrivateProfile]) return false;
        if (enabled && ((int)store.Policy.CurrentProfileTypes & LocalFirewallPolicy.PrivateProfile) != 0
            && (int)store.Policy.LocalPolicyModifyState != 0) return false;
        return LocalFirewallPolicy.HasRules(store.Read(), exe, enabled);
    }

    public async Task<bool> AddRuleAsync()
    {
        if (Environment.ProcessPath is not { } exe) return false;
        try
        {
            // Kabuk komutu üretmeyiz; boşluk, &, % gibi karakterler içeren kurulum yolları da güvenle çalışır.
            var start = new ProcessStartInfo(exe)
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden,
            };
            start.ArgumentList.Add(ConfigureArgument);
            using var process = ChildProcessGuard.StartUncontained(start);
            if (process is null) return false;
            await process.WaitForExitAsync();
            if (process.ExitCode != 0) return false;
            return await Task.Run(HasRule);
        }
        catch (Win32Exception) { return false; } // UAC reddedildi veya yardımcı süreç açılamadı.
        catch (Exception) { return false; } // Kural doğrulanamadıysa başarı bildirilmez.
    }

    /// <summary>WPF/Velopack başlamadan, yalnız sabit komut satırı seçeneğiyle çalışır; dışarıdan yol kabul etmez.</summary>
    internal static int ConfigureCurrentProcess()
    {
        if (Environment.ProcessPath is not { } exe) return 1;
        try { return LocalFirewallPolicy.Apply(new ComRuleStore(), exe, PublicNetworkConnected()) ? 0 : 1; }
        catch (Exception) { return 1; }
    }

    /// <summary>Kaldırmada yalnız bu uygulama yolunun yönettiği kurallar silinir; başka kurallar korunur.</summary>
    public static void RemoveRuleQuietly()
    {
        if (Environment.ProcessPath is not { } exe) return;
        try { LocalFirewallPolicy.RemoveOwned(new ComRuleStore(), exe); }
        catch (Exception) { } // Kaldırma işlemini yönetici izni yok diye durdurmayız.
    }

    public bool HasLegacyRule() =>
        Environment.ProcessPath is { } exe && LocalFirewallPolicy.HasLegacyRule(new ComRuleStore().Read(), exe);

    public bool HasPublicNetwork() => PublicNetworkConnected();

    /// <summary>Ağ listesi COM'u: kategori 0 = Ortak. Ağın kategorisi otomatik değiştirilmez.</summary>
    private static bool PublicNetworkConnected()
    {
        try
        {
            var type = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"));
            if (type is null) return false;
            dynamic manager = Activator.CreateInstance(type)!;
            foreach (dynamic connection in (IEnumerable)manager.GetNetworkConnections())
            {
                if (!(bool)connection.IsConnected) continue;
                if ((int)connection.GetNetwork().GetCategory() == 0) return true;
            }
        }
        catch (Exception) { }
        return false;
    }

    private sealed class ComRuleStore : IFirewallRuleStore
    {
        public dynamic Policy { get; } = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2")
            ?? throw new PlatformNotSupportedException("Windows Firewall COM unavailable"))!;

        public IReadOnlyList<FirewallRule> Read()
        {
            var result = new List<FirewallRule>();
            foreach (dynamic rule in (IEnumerable)Policy.Rules)
                result.Add(ReadRule(rule));
            return result;
        }

        private static FirewallRule ReadRule(dynamic rule)
        {
            int protocol = rule.Protocol;
            var ports = protocol is LocalFirewallPolicy.Tcp or LocalFirewallPolicy.Udp;
            return new FirewallRule((string)rule.Name, (string?)rule.ApplicationName ?? "", (bool)rule.Enabled,
                (int)rule.Direction, (int)rule.Action, (int)rule.Profiles, protocol,
                Scope((string?)rule.RemoteAddresses), Scope((string?)rule.LocalAddresses),
                ports ? Scope((string?)rule.LocalPorts) : "*", ports ? Scope((string?)rule.RemotePorts) : "*",
                (string?)rule.ServiceName ?? "", (string?)rule.InterfaceTypes ?? "All", (string?)rule.Grouping ?? "",
                rule.Interfaces is Array { Length: > 0 }, (bool)rule.EdgeTraversal);
        }

        private static string Scope(string? value) => string.IsNullOrEmpty(value) ? "*"
            : value.Equals("LocalSubnet", StringComparison.OrdinalIgnoreCase) ? "LocalSubnet" : value;

        public void Put(FirewallRule spec)
        {
            // COM'da görünen ad tekil olmak zorunda değil. Yeniden kurulumda yeni kopyalar eklemek yerine
            // yalnız bize ait mevcut kuralları yerinde güncelle; aynı adlı yabancı kuralı asla üzerine yazma.
            var existing = new List<object>();
            foreach (dynamic rule in (IEnumerable)Policy.Rules)
            {
                if (!string.Equals((string)rule.Name, spec.Name, StringComparison.OrdinalIgnoreCase)) continue;
                var snapshot = ReadRule(rule);
                if (!LocalFirewallPolicy.SameProgram(snapshot.Program, spec.Program)
                    || !string.Equals(snapshot.Grouping, spec.Grouping, StringComparison.OrdinalIgnoreCase)
                    || snapshot.Direction != spec.Direction || snapshot.Action != spec.Action)
                    throw new InvalidOperationException("Firewall rule name belongs to another policy");
                existing.Add(rule);
            }
            if (existing.Count == 0) Policy.Rules.Add(BuildRule(spec));
            else foreach (var rule in existing) SetRule(rule, spec);
        }

        private static object BuildRule(FirewallRule spec)
        {
            dynamic rule = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FWRule")
                ?? throw new PlatformNotSupportedException("Windows Firewall rule COM unavailable"))!;
            SetRule(rule, spec);
            return rule;
        }

        private static void SetRule(dynamic rule, FirewallRule spec)
        {
            rule.Name = spec.Name;
            rule.Description = "CouchSubs: TV and Remote Play on the private local network.";
            rule.Grouping = spec.Grouping;
            rule.ApplicationName = spec.Program;
            rule.Protocol = spec.Protocol; // Portlar protokolden sonra atanmalı (INetFwRule).
            rule.LocalPorts = spec.LocalPorts;
            rule.RemotePorts = spec.RemotePorts;
            rule.LocalAddresses = spec.LocalAddresses;
            rule.RemoteAddresses = spec.RemoteAddresses;
            rule.InterfaceTypes = spec.InterfaceTypes;
            rule.Interfaces = null;
            rule.Direction = spec.Direction;
            rule.Profiles = spec.Profiles;
            rule.Action = spec.Action;
            rule.EdgeTraversal = false;
            rule.Enabled = spec.Enabled;
        }

        public void Remove(string name) => Policy.Rules.Remove(name);
    }
}
