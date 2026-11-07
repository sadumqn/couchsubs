// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

public class ExtraRegionTests
{
    private static (AppController Controller, FakeServices Services) Ready()
    {
        var services = new FakeServices();
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, new RegisteredConsole("192.168.1.253", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        return (AppControllerTests.Make(services, store), services);
    }

    [Fact]
    public void ExtraRegionsAreOffByDefault()
    {
        var settings = new UserSettings();
        Assert.Null(settings.ExtraRegion(1));
        Assert.Null(settings.ExtraRegion(2));
    }

    [Fact]
    public void ExtraRegionIsSetAndClearedBySlot()
    {
        var region = new CropRegion(0.1, 0.3, 0.6, 0.95);
        var settings = new UserSettings().WithExtraRegion(2, region);
        Assert.Null(settings.ExtraRegion(1));
        Assert.Equal(region, settings.ExtraRegion(2));
        Assert.Null(settings.WithExtraRegion(2, null).ExtraRegion(2));
    }

    [Fact]
    public async Task UnconfiguredRegionDoesNothing()
    {
        var (controller, _) = Ready();
        Assert.Equal(ExtraRegionOutcome.NotConfigured, await controller.TranslateExtraRegionAsync(1));
    }

    [Fact]
    public async Task NothingHappensWhileTranslationIsStopped()
    {
        var (controller, _) = Ready();
        controller.Settings = controller.Settings.WithExtraRegion(1, new CropRegion());
        Assert.Equal(ExtraRegionOutcome.NotRunning, await controller.TranslateExtraRegionAsync(1));
    }

    [Fact]
    public async Task EmptyRegionReportsNoText()
    {
        var (controller, services) = Ready();
        controller.Settings = controller.Settings.WithExtraRegion(1, new CropRegion());
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ExtraRegionOutcome.NoText, await controller.TranslateExtraRegionAsync(1));
        controller.Stop();
    }
}
