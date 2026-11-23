// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

/// <summary>
/// Kullanım verisi (Ayarlar › Oyun paketleri › Kullanım verisi; Mac AppModel ile aynı olaylar): çeviri oturumu, ekranlar
/// ve kapatınca hiçbir isteğin gitmemesi.
/// </summary>
public class UsageDataTests
{
    private sealed class CountingHandler : HttpMessageHandler
    {
        public int Requests;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Requests);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
        }
    }

    private static (AppController Controller, UsageStats Usage, CountingHandler Handler) Ready(bool usageData = true)
    {
        var handler = new CountingHandler();
        var usage = new UsageStats(UsageStats.Config.Create("G-TEST", "secret"), Path.Combine(Path.GetTempPath(), "usage-" + Guid.NewGuid(), "usage-id"),
            "1.0", "Windows 10.0", handler: handler);
        var services = new FakeServices { Usage = usage };
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, new RegisteredConsole("192.168.1.253", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        var settings = new MemorySettings();
        settings.Save(new UserSettings { UsageData = usageData });
        return (AppControllerTests.Make(services, store, settings), usage, handler);
    }

    [Fact]
    public async Task TranslationSessionAndScreensAreRecorded()
    {
        var (controller, usage, handler) = Ready();
        Assert.True(controller.ShowsUsageNotice);
        Assert.True(controller.UsageConfigured);
        Assert.Equal(UsageStats.Event.Screen("home"), usage.Queued[0]);
        await controller.StartAsync();
        Assert.Contains(UsageStats.Event.SessionStart("tv", "free", true, "ps5"), usage.Queued);
        // İlk çeviride bilgi notu kaybolur.
        Assert.False(controller.ShowsUsageNotice);
        controller.Stop();
        Assert.Equal("subtitle_session_stop", usage.Queued[^1].Name);
        Assert.Equal(0, usage.Queued[^1].Params["lines"]);
        controller.NoteScreen("settings");
        Assert.Equal(UsageStats.Event.Screen("settings"), usage.Queued[^1]);
        await usage.FlushAsync();
        Assert.Equal(1, handler.Requests);
        Assert.Empty(usage.Queued);
        controller.Dispose();
    }

    [Fact]
    public async Task TurnedOffSendsNothing()
    {
        var (controller, usage, handler) = Ready(usageData: false);
        await controller.StartAsync();
        controller.Stop();
        controller.NoteScreen("settings");
        Assert.Empty(usage.Queued);
        await usage.FlushAsync();
        Assert.Equal(0, handler.Requests);
        controller.Dispose();
        Assert.Equal(0, handler.Requests);
    }

    [Fact]
    public async Task TurningOffInSettingsDropsWaitingEventsAndHidesTheNotice()
    {
        var (controller, usage, handler) = Ready();
        Assert.NotEmpty(usage.Queued);
        controller.Settings = controller.Settings with { UsageData = false };
        Assert.False(controller.ShowsUsageNotice);
        Assert.True(controller.Settings.UsageNoticeSeen);
        Assert.Empty(usage.Queued);
        await controller.StartAsync();
        controller.Stop();
        await usage.FlushAsync();
        Assert.Equal(0, handler.Requests);
        controller.Dispose();
    }
}
