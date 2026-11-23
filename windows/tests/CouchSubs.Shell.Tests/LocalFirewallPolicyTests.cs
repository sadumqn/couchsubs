// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell.Tests;

public class LocalFirewallPolicyTests
{
    private const string Exe = @"C:\Users\Oyuncu & Aile\CouchSubsApp\current\CouchSubs.exe";
    private static FirewallRule Legacy => new(LocalFirewallPolicy.LegacyName, Exe, true, 1, 1, int.MaxValue, 256);

    private sealed class Store(params FirewallRule[] initial) : IFirewallRuleStore
    {
        public List<FirewallRule> Rules { get; } = [.. initial];
        public List<string> Removed { get; } = [];
        public int Puts { get; private set; }
        public bool FailSecondPut { get; init; }
        public bool IgnorePuts { get; init; }
        public IReadOnlyList<FirewallRule> Read() => Rules.ToArray();
        public void Put(FirewallRule rule)
        {
            if (++Puts == 2 && FailSecondPut) throw new InvalidOperationException("write denied");
            if (IgnorePuts) return;
            Rules.RemoveAll(r => r.Name == rule.Name);
            Rules.Add(rule);
        }
        public void Remove(string name)
        {
            Removed.Add(name);
            var index = Rules.FindIndex(r => r.Name == name);
            if (index >= 0) Rules.RemoveAt(index);
        }
    }

    [Fact]
    public void CreatesPrivateLocalTcpAndUdpWithoutRestrictingDynamicPorts()
    {
        var store = new Store();
        Assert.True(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Equal(2, store.Rules.Count);
        Assert.Equal(new[] { 6, 17 }, store.Rules.Select(r => r.Protocol));
        Assert.All(store.Rules, r =>
        {
            Assert.Equal(2, r.Profiles);
            Assert.Equal("LocalSubnet", r.RemoteAddresses);
            Assert.Equal("*", r.LocalPorts);
            Assert.Equal("*", r.RemotePorts);
            Assert.Equal(Exe, r.Program);
            Assert.Equal(1, r.Direction);
        });
        Assert.True(LocalFirewallPolicy.HasRules(store.Read(), Exe));
    }

    /// Ortak ağda dar kural işe yaramaz; eski geniş kural silinirse TV bağlantısı kesilir. Hiçbir şey değişmez.
    [Fact]
    public void KeepsLegacyRuleOnPublicNetwork()
    {
        var store = new Store(Legacy);
        Assert.True(LocalFirewallPolicy.HasLegacyRule(store.Read(), Exe));
        Assert.False(LocalFirewallPolicy.Apply(store, Exe, publicNetwork: true));
        Assert.Empty(store.Removed);
        Assert.Equal(0, store.Puts);
        Assert.Equal(new[] { Legacy }, store.Rules);
    }

    [Fact]
    public void PublicNetworkWithoutLegacyRuleStillWritesPrivateRules()
    {
        var store = new Store();
        Assert.False(LocalFirewallPolicy.HasLegacyRule(store.Read(), Exe));
        Assert.True(LocalFirewallPolicy.Apply(store, Exe, publicNetwork: true));
        Assert.Equal(2, store.Rules.Count);
    }

    [Fact]
    public void MigratesOnlyLegacyRuleAndDoesNotDuplicateOnRetry()
    {
        var custom = Legacy with { Name = "My CouchSubs permission", Profiles = 2 };
        var store = new Store(Legacy, custom);
        Assert.False(LocalFirewallPolicy.HasRules(store.Read(), Exe));
        Assert.True(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Equal(new[] { LocalFirewallPolicy.LegacyName }, store.Removed);
        Assert.Contains(custom, store.Rules);
        Assert.True(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Equal(3, store.Rules.Count);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(4)]
    public void OtherProfilesDoNotSatisfyPrivatePermission(int profile)
    {
        var rules = LocalFirewallPolicy.Required(Exe).Select(r => r with { Profiles = profile }).ToArray();
        Assert.False(LocalFirewallPolicy.HasRules(rules, Exe));
    }

    [Theory]
    [InlineData("192.168.1.35", "*", "*", "All", "")]
    [InlineData("LocalSubnet", "8787", "*", "All", "")]
    [InlineData("LocalSubnet", "*", "9296", "All", "")]
    [InlineData("LocalSubnet", "*", "*", "Wireless", "")]
    [InlineData("LocalSubnet", "*", "*", "All", "OtherService")]
    public void PartialRulesDoNotMasqueradeAsCompletePermission(string remote, string localPorts,
        string remotePorts, string interfaces, string service)
    {
        var rules = LocalFirewallPolicy.Required(Exe).Select(r => r with
        { RemoteAddresses = remote, LocalPorts = localPorts, RemotePorts = remotePorts, InterfaceTypes = interfaces, ServiceName = service }).ToArray();
        Assert.False(LocalFirewallPolicy.HasRules(rules, Exe));
    }

    [Fact]
    public void DisabledOutboundOrWrongProgramRulesDoNotCount()
    {
        var rules = LocalFirewallPolicy.Required(Exe);
        Assert.False(LocalFirewallPolicy.HasRules(rules.Select(r => r with { Enabled = false }).ToArray(), Exe));
        Assert.False(LocalFirewallPolicy.HasRules(rules.Select(r => r with { Direction = 2 }).ToArray(), Exe));
        Assert.False(LocalFirewallPolicy.HasRules(rules.Select(r => r with { InterfaceRestricted = true }).ToArray(), Exe));
        Assert.False(LocalFirewallPolicy.HasRules(rules.Select(r => r with { Program = @"C:\Other.exe" }).ToArray(), Exe));
        Assert.False(LocalFirewallPolicy.HasRules([rules[0]], Exe));
    }

    [Fact]
    public void OwnExeBlockFromWindowsPromptIsReplacedByPrivatePermission()
    {
        // Windows ilk açılış sorusu kapatılınca exe için TCP/UDP engel kuralları yazar; "izin ver" bunları kaldırır.
        var tcpBlock = Legacy with { Action = 0, Profiles = 2, Protocol = 6 };
        var udpBlock = tcpBlock with { Protocol = 17 };
        var store = new Store(tcpBlock, udpBlock);
        Assert.False(LocalFirewallPolicy.HasRules(store.Read(), Exe));
        Assert.True(LocalFirewallPolicy.Apply(store, Exe));
        Assert.DoesNotContain(tcpBlock, store.Rules);
        Assert.DoesNotContain(udpBlock, store.Rules);
        Assert.True(LocalFirewallPolicy.HasRules(store.Read(), Exe));
    }

    [Fact]
    public void BlockSharingNameWithForeignRuleIsPreservedAndPermissionIsNotClaimed()
    {
        var block = Legacy with { Name = "User block", Action = 0, Profiles = 2 };
        var foreign = block with { Program = @"C:\Other.exe" };
        var store = new Store(Legacy, block, foreign);
        Assert.False(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Empty(store.Removed);
        Assert.Equal(0, store.Puts);
        Assert.Equal(new[] { Legacy, block, foreign }, store.Rules);
    }

    [Fact]
    public void PublicBlockIsPreservedWithoutBlockingPrivateSetup()
    {
        var block = Legacy with { Name = "Public block", Action = 0, Profiles = 4 };
        var store = new Store(block);
        Assert.True(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Contains(block, store.Rules);
    }

    [Fact]
    public void GlobalBlockCountsButAnotherProgramsOrServicesBlockDoesNot()
    {
        var block = Legacy with { Name = "Block", Program = "", Profiles = 2, Action = 0 };
        var allow = LocalFirewallPolicy.Required(Exe);
        Assert.False(LocalFirewallPolicy.HasRules([.. allow, block], Exe));
        Assert.True(LocalFirewallPolicy.HasRules([.. allow, block with { Program = @"C:\Other.exe" }], Exe));
        Assert.True(LocalFirewallPolicy.HasRules([.. allow, block with { ServiceName = "OtherService" }], Exe));
    }

    [Fact]
    public void FailedWriteLeavesLegacyPermissionIntact()
    {
        var store = new Store(Legacy) { FailSecondPut = true };
        Assert.Throws<InvalidOperationException>(() => LocalFirewallPolicy.Apply(store, Exe));
        Assert.Contains(Legacy, store.Rules);
        Assert.Empty(store.Removed);
    }

    [Fact]
    public void SilentFailedWriteCannotBeMaskedByLegacyAllow()
    {
        var store = new Store(Legacy) { IgnorePuts = true };
        Assert.False(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Contains(Legacy, store.Rules);
        Assert.Empty(store.Removed);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ManagedNameCollisionNeverOverwritesForeignRule(bool lowerCase)
    {
        var foreign = LocalFirewallPolicy.Required(@"C:\Other.exe")[0];
        if (lowerCase) foreign = foreign with { Name = foreign.Name.ToLowerInvariant() };
        var store = new Store(foreign);
        Assert.False(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Equal(0, store.Puts);
        Assert.Equal(foreign, Assert.Single(store.Rules));
    }

    [Fact]
    public void LegacyNameCollisionNeverDeletesForeignRule()
    {
        var foreign = Legacy with { Program = @"C:\Other.exe" };
        var store = new Store(Legacy, foreign);
        Assert.False(LocalFirewallPolicy.Apply(store, Exe));
        Assert.Empty(store.Removed);
        Assert.Equal(0, store.Puts);
    }

    [Fact]
    public void UninstallPreservesOtherProgramsAndCustomRules()
    {
        var custom = Legacy with { Name = "Custom" };
        var foreign = Legacy with { Program = @"C:\Other.exe" };
        var store = new Store([.. LocalFirewallPolicy.Required(Exe), custom, foreign]);
        LocalFirewallPolicy.RemoveOwned(store, Exe);
        Assert.Equal(new[] { custom, foreign }, store.Rules);
    }

    [Fact]
    public void DisabledFirewallDoesNotNeedAllowRulesButLegacyMigrationStillApplies()
    {
        Assert.True(LocalFirewallPolicy.HasRules([], Exe, privateFirewallEnabled: false));
        Assert.False(LocalFirewallPolicy.HasRules([Legacy], Exe, privateFirewallEnabled: false));
    }
}
