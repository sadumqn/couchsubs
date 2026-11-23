// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;

namespace CouchSubs.Core.Tests;

/// <summary>Birincil paket adresi (workers.dev) ulaşılamazsa yedek adres (#583).</summary>
public sealed class PackFallbackTests : IDisposable
{
    private const string Primary = "https://packs.primary.test";
    private const string Fallback = "https://packs.fallback.test";
    private readonly string root = Path.Combine(Path.GetTempPath(), "fallback-" + Guid.NewGuid());

    /// <summary>Adres → sonuç: gövde (200), durum kodu ya da yoksa ağ hatası.</summary>
    private sealed class MirrorHandler : HttpMessageHandler
    {
        public Dictionary<string, object> Answers { get; } = [];
        public List<string> Calls { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var url = request.RequestUri!.AbsoluteUri;
            Calls.Add(url);
            return Answers.TryGetValue(url, out var answer) switch
            {
                true when answer is byte[] data => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) }),
                true when answer is HttpStatusCode code => Task.FromResult(new HttpResponseMessage(code)),
                _ => throw new HttpRequestException("unreachable"),
            };
        }
    }

    private readonly MirrorHandler handler = new();
    private static readonly byte[] PackData = Encoding.UTF8.GetBytes("pack");

    private void Serve(string baseUrl)
    {
        var list = JsonSerializer.SerializeToUtf8Bytes(new { packs = new[] { new RemotePack("gta-6", "GTA 6", 1, PackUpdater.Sha256(PackData)) } });
        handler.Answers[$"{baseUrl}/v1/packs"] = list;
        handler.Answers[$"{baseUrl}/v1/packs/gta-6"] = PackData;
    }

    private PackUpdater Make(params string[] fallbacks) =>
        new(new Uri(Primary), Path.Combine(root, "packs"), Path.Combine(root, "state.json"), handler,
            fallbackUrls: fallbacks.Select(f => new Uri(f)));

    [Fact]
    public async Task PrimaryWorksFallbackUntouched()
    {
        Serve(Primary);
        using var updater = Make(Fallback);
        var result = await updater.RefreshAsync(force: true);
        Assert.Equal(["gta-6"], result.Downloaded);
        Assert.DoesNotContain(handler.Calls, c => c.StartsWith(Fallback));
        Assert.Equal(0, updater.PreferredIndex);
    }

    [Fact]
    public async Task NetworkErrorFallsBackAndRemembersWorkingAddress()
    {
        Serve(Fallback);
        using var updater = Make(Fallback + "/");
        var result = await updater.RefreshAsync(force: true);
        Assert.Equal(["gta-6"], result.Downloaded);
        Assert.Equal(1, updater.PreferredIndex);
        // Paket doğrudan yedekten iner; birincil adres her istekte yeniden beklenmez.
        Assert.Equal([$"{Primary}/v1/packs", $"{Fallback}/v1/packs", $"{Fallback}/v1/packs/gta-6"], handler.Calls);
        Assert.Equal("pack", File.ReadAllText(Path.Combine(root, "packs", "gta-6.json.gz")));
    }

    [Fact]
    public async Task ServerErrorFallsBackClientErrorDoesNot()
    {
        Serve(Fallback);
        handler.Answers[$"{Primary}/v1/packs"] = HttpStatusCode.BadGateway;
        using (var updater = Make(Fallback))
            Assert.Equal(["gta-6"], (await updater.RefreshAsync(force: true)).Downloaded);

        Directory.Delete(root, recursive: true);
        handler.Calls.Clear();
        handler.Answers[$"{Primary}/v1/packs"] = HttpStatusCode.TooManyRequests;
        using var limited = Make(Fallback);
        Assert.True((await limited.RefreshAsync(force: true)).Failed);
        Assert.Equal([$"{Primary}/v1/packs"], handler.Calls);
    }

    [Fact]
    public async Task BothDownFailsAndNoFallbackMeansPrimaryOnly()
    {
        using (var updater = Make(Fallback))
            Assert.True((await updater.RefreshAsync(force: true)).Failed);
        Assert.Equal([$"{Primary}/v1/packs", $"{Fallback}/v1/packs"], handler.Calls);

        handler.Calls.Clear();
        using var alone = Make();
        Assert.True((await alone.RefreshAsync(force: true)).Failed);
        Assert.Equal([$"{Primary}/v1/packs"], handler.Calls);
    }

    [Fact]
    public void FallbackAddressComesFromConfiguration()
    {
        var assembly = typeof(PackFallbackTests).Assembly;
        Assert.Null(PackUpdater.ConfiguredFallbackUrl("", assembly));
        Assert.Null(PackUpdater.ConfiguredFallbackUrl("ftp://x", assembly));
        Assert.Equal("b.test", PackUpdater.ConfiguredFallbackUrl("https://b.test", assembly)?.Host);
    }

    public void Dispose()
    {
        try { Directory.Delete(root, recursive: true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}
