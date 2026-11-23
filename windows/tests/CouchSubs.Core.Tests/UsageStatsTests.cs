// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Kullanım verisi (GA4 Measurement Protocol): ortak deneme dosyasındaki olaylardan aynı adres ve gövde
/// (core/Tests/CouchSubsCoreTests/Fixtures/usage-stats.json; Mac UsageStatsTests.swift aynı dosyayı okur), kapalıyken ve
/// yapılandırılmamışken hiç istek yok.
/// </summary>
public class UsageStatsTests
{
    private sealed class Recorder : HttpMessageHandler
    {
        public List<(Uri Url, string Body)> Requests { get; } = [];
        public bool Fails { get; set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            lock (Requests) Requests.Add((request.RequestUri!, body));
            if (Fails) throw new HttpRequestException("çevrimdışı");
            return new HttpResponseMessage(HttpStatusCode.NoContent);
        }
    }

    private static readonly UsageStats.Config Config = UsageStats.Config.Create("G-TEST", "secret")!;

    private static string IdFile() => Path.Combine(Path.GetTempPath(), "usage-" + Guid.NewGuid(), "usage-id");

    private static UsageStats.Event Event(JsonElement spec) => spec.GetProperty("kind").GetString() switch
    {
        "screen" => UsageStats.Event.Screen(spec.GetProperty("screen").GetString()!),
        "onboarding_done" => UsageStats.Event.OnboardingDone(spec.GetProperty("target").GetString()!, spec.GetProperty("console").GetString()!),
        "session_start" => UsageStats.Event.SessionStart(spec.GetProperty("target").GetString()!, spec.GetProperty("engine").GetString()!,
            spec.GetProperty("packs").GetBoolean(), spec.GetProperty("console").GetString()!),
        "session_stop" => UsageStats.Event.SessionStop(spec.GetProperty("seconds").GetInt32(), spec.GetProperty("lines").GetInt32(),
            spec.GetProperty("pack_lines").GetInt32()),
        "tv_connected" => UsageStats.Event.TvConnected(spec.GetProperty("count").GetInt32(), spec.GetProperty("brand").GetString()!),
        "pack_hit" => UsageStats.Event.PackHit(spec.GetProperty("pack").GetString()!),
        var kind => throw new InvalidOperationException(kind),
    };

    [Fact]
    public void SharedVectorBuildsSameUrlAndBody()
    {
        using var vector = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("usage-stats.json")));
        var root = vector.RootElement;
        var config = UsageStats.Config.Create(root.GetProperty("measurement_id").GetString(), root.GetProperty("api_secret").GetString())!;
        Assert.Equal(root.GetProperty("url").GetString(), UsageStats.RequestUri(config).AbsoluteUri);
        var properties = root.GetProperty("user_properties").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString()!);
        var body = UsageStats.Payload(root.GetProperty("client_id").GetString()!, root.GetProperty("session_id").GetString()!, properties,
            root.GetProperty("events").EnumerateArray().Select(Event));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(root.GetProperty("body").GetRawText()), JsonNode.Parse(body)), body);
    }

    [Fact]
    public async Task SendsQueuedEventsInBatchesWithStableRandomId()
    {
        var recorder = new Recorder();
        var file = IdFile();
        using var stats = new UsageStats(Config, file, "1", "Windows 10.0", handler: recorder);
        for (var i = 0; i < 30; i++) stats.Record(UsageStats.Event.Screen("home"));
        await stats.FlushAsync();
        Assert.Equal(2, recorder.Requests.Count);
        Assert.Empty(stats.Queued);
        var first = JsonNode.Parse(recorder.Requests[0].Body)!;
        Assert.Equal(UsageStats.BatchSize, first["events"]!.AsArray().Count);
        var id = first["client_id"]!.GetValue<string>();
        Assert.True(Guid.TryParse(id, out _));
        Assert.Equal(id, File.ReadAllText(file));
        using var again = new UsageStats(Config, file, "1", "Windows 10.0", handler: recorder);
        again.Record(UsageStats.Event.PackHit("gta6"));
        await again.FlushAsync();
        Assert.Equal(id, JsonNode.Parse(recorder.Requests[2].Body)!["client_id"]!.GetValue<string>());
    }

    [Fact]
    public async Task TurnedOffSendsNothing()
    {
        var recorder = new Recorder();
        using var stats = new UsageStats(Config, IdFile(), "1", "x", enabled: false, handler: recorder);
        stats.Record(UsageStats.Event.Screen("home"));
        stats.Record(UsageStats.Event.SessionStart("tv", "free", true, "ps5"));
        await stats.FlushAsync();
        Assert.Empty(recorder.Requests);
        Assert.Empty(stats.Queued);
    }

    [Fact]
    public async Task TurningOffDropsWaitingEvents()
    {
        var recorder = new Recorder();
        using var stats = new UsageStats(Config, IdFile(), "1", "x", handler: recorder);
        stats.Record(UsageStats.Event.Screen("home"));
        stats.SetEnabled(false);
        await stats.FlushAsync();
        stats.SetEnabled(true);
        await stats.FlushAsync();
        Assert.Empty(recorder.Requests);
    }

    [Fact]
    public async Task WithoutBuildConfigNothingIsQueuedOrSent()
    {
        Assert.Null(UsageStats.Config.Create("", "secret"));
        Assert.Null(UsageStats.Config.Create("G-X", null));
        Assert.Null(UsageStats.Config.FromBuild(typeof(UsageStatsTests).Assembly, _ => null));
        var recorder = new Recorder();
        var file = IdFile();
        using var stats = new UsageStats(null, file, "1", "x", handler: recorder);
        Assert.False(stats.IsConfigured);
        stats.Record(UsageStats.Event.Screen("home"));
        await stats.FlushAsync();
        Assert.Empty(recorder.Requests);
        Assert.Empty(stats.Queued);
        Assert.False(File.Exists(file));
    }

    [Fact]
    public void EnvironmentConfigComesFirst()
    {
        var config = UsageStats.Config.FromBuild(typeof(UsageStatsTests).Assembly,
            name => name == "COUCHSUBS_GA_MEASUREMENT_ID" ? "G-ENV" : name == "COUCHSUBS_GA_API_SECRET" ? "env-secret" : null);
        Assert.Equal(new UsageStats.Config("G-ENV", "env-secret"), config);
    }

    [Fact]
    public async Task NetworkErrorKeepsEventsQuietly()
    {
        var recorder = new Recorder { Fails = true };
        using var stats = new UsageStats(Config, IdFile(), "1", "x", handler: recorder);
        stats.Record(UsageStats.Event.Screen("home"));
        await stats.FlushAsync();
        Assert.Single(stats.Queued);
        recorder.Fails = false;
        await stats.FlushAsync();
        Assert.Empty(stats.Queued);
        Assert.Equal(2, recorder.Requests.Count);
    }

    [Fact]
    public void QueueIsBounded()
    {
        using var stats = new UsageStats(Config, IdFile(), "1", "x", handler: new Recorder());
        for (var i = 0; i < UsageStats.MaxQueue + 10; i++) stats.Record(UsageStats.Event.PackHit("p" + i));
        Assert.Equal(UsageStats.MaxQueue, stats.Queued.Count);
        Assert.Equal(UsageStats.Event.PackHit("p10"), stats.Queued[0]);
    }
}
