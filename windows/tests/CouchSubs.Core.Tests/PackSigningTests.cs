// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;

namespace CouchSubs.Core.Tests;

/// <summary>Paket isteklerinin imzası (server/packs). Mac PackSigningTests.swift ve Android PackSigningTest.kt ile aynı vektör.</summary>
public sealed class PackSigningTests : IDisposable
{
    private const string Secret = "test-secret-not-real";
    private const string Vector = "c7d9ee8207b98e3d43de0bfd2ecbcaaadf125e718f03b4fe8dae1779f18b5f30";
    private readonly string root = Path.Combine(Path.GetTempPath(), "signing-" + Guid.NewGuid());

    private sealed class Recorder : HttpMessageHandler
    {
        public List<(string Path, string? Time, string? Signature)> Seen { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            string? Header(string name) => request.Headers.TryGetValues(name, out var values) ? values.Single() : null;
            Seen.Add((request.RequestUri!.AbsolutePath, Header(PackSigning.TimeHeader), Header(PackSigning.SignatureHeader)));
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"packs\":[]}") });
        }
    }

    [Fact]
    public void SharedVector() =>
        Assert.Equal(Vector, PackSigning.Signature(Secret, "GET", "/v1/packs/gta-6", 1_764_460_800));

    [Fact]
    public async Task UpdaterSignsRequestsWhenSecretGiven()
    {
        var recorder = new Recorder();
        using var updater = new PackUpdater(new Uri("https://packs.example.test"), Path.Combine(root, "packs"),
            Path.Combine(root, "state.json"), recorder, () => DateTimeOffset.FromUnixTimeSeconds(1_764_460_800), secret: Secret);
        await updater.RefreshAsync(force: true);
        var (path, time, signature) = Assert.Single(recorder.Seen);
        Assert.Equal("/v1/packs", path);
        Assert.Equal("1764460800", time);
        Assert.Equal(PackSigning.Signature(Secret, "GET", "/v1/packs", 1_764_460_800), signature);
    }

    [Fact]
    public async Task NoSecretNoHeaders()
    {
        var recorder = new Recorder();
        using var updater = new PackUpdater(new Uri("https://packs.example.test"), Path.Combine(root, "packs"),
            Path.Combine(root, "state.json"), recorder);
        await updater.RefreshAsync(force: true);
        Assert.Null(Assert.Single(recorder.Seen).Signature);
    }

    [Fact]
    public void ConfiguredSecretIgnoresEmptyValues()
    {
        Assert.Null(PackSigning.ConfiguredSecret("  ", typeof(PackSigningTests).Assembly));
        Assert.Equal("abc", PackSigning.ConfiguredSecret("abc", typeof(PackSigningTests).Assembly));
    }

    public void Dispose()
    {
        try { Directory.Delete(root, recursive: true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}
