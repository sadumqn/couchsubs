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
        Assert.Empty(settings.ExtraAreas);
        Assert.Null(settings.ExtraAreaAt(1));
    }

    [Fact]
    public void ExtraRegionsAreNotReadContinuouslyByDefault()
    {
        var settings = new UserSettings();
        Assert.Empty(settings.WatchedAreas());
        Assert.Empty(settings.WithArea(new CropRegion()).WatchedAreas());
    }

    [Fact]
    public void OnlyConfiguredLiveRegionsAreWatched()
    {
        var quest = ExtraAreaPreset.Quest.Region();
        var settings = new UserSettings()
            .WithArea(quest, live: true)
            .WithArea(new CropRegion());
        var watched = Assert.Single(settings.WatchedAreas());
        Assert.Equal("area1", watched.Id);
        Assert.Equal(quest, watched.Region);
    }

    /// <summary>
    /// Altyazı alanı Tam ekranken sürekli okunan bölge yoktur (ekranın tamamı zaten okunuyor); ayarlar değişmez, başka
    /// alana dönünce bölgeler eskisi gibi okunur.
    /// </summary>
    [Fact]
    public void FullScreenAreaPausesWatchedRegionsWithoutChangingThem()
    {
        var quest = ExtraAreaPreset.Quest.Region();
        var settings = new UserSettings().WithArea(quest, live: true);
        var full = settings with { AreaPreset = AreaPreset.Full, Region = new CropRegion(0, 1, 0, 1) };
        Assert.True(full.ExtraAreasPausedByFullScreen);
        Assert.Empty(full.WatchedAreas());
        Assert.True(full.ExtraAreas[0].Enabled);
        Assert.Equal(quest, full.ExtraAreas[0].Region);
        var back = full with { AreaPreset = AreaPreset.Bottom, Region = new CropRegion() };
        Assert.False(back.ExtraAreasPausedByFullScreen);
        Assert.Equal("area1", Assert.Single(back.WatchedAreas()).Id);
    }

    /// <summary>Eski ayar dosyasında hazır seçim yoktur; tam kare bölge de Tam ekran sayılır.</summary>
    [Fact]
    public void FullFrameRegionWithoutPresetCountsAsFullScreen()
    {
        var settings = new UserSettings { Region = new CropRegion(0, 1, 0, 1) }.WithArea(ExtraAreaPreset.Quest.Region(), live: true);
        Assert.Empty(settings.WatchedAreas());
    }

    /// <summary>Çeviri sürerken Tam ekran seçilince ek alan kutusu kalkar; başka alana dönünce yeniden okunup gelir.</summary>
    [Fact]
    public async Task SwitchingToFullScreenRemovesLiveRegionAndSwitchingBackBringsItBack()
    {
        var (controller, services) = Ready();
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        services.ReaderLines = new Reading([new TextLine("Find the blacksmith", new TextBox(0.1, 0.2, 0.9, 0.3))]);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        controller.Settings = controller.Settings.WithArea(ExtraAreaPreset.Quest.Region(), live: true);
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += e => { lock (received) received.Add(e); };
        await controller.StartAsync();

        async Task<SubtitleEvent?> WaitForRegion()
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (DateTime.UtcNow < deadline)
            {
                services.Streams[0].Emit(Frame.Blank(64, 64));
                await Task.Delay(100);
                lock (received)
                    if (received.FirstOrDefault(e => e.Kind == SubtitleEventKind.Region && e.Text != "") is { } found) return found;
            }
            return null;
        }

        Assert.NotNull(await WaitForRegion());
        lock (received) received.Clear();
        controller.Settings = controller.Settings with { AreaPreset = AreaPreset.Full, Region = new CropRegion(0, 1, 0, 1) };
        for (var i = 0; i < 5; i++)
        {
            services.Streams[0].Emit(Frame.Blank(64, 64));
            await Task.Delay(50);
        }
        lock (received)
        {
            Assert.Contains(received, e => e.Kind == SubtitleEventKind.RegionClear);
            Assert.DoesNotContain(received, e => e.Kind == SubtitleEventKind.Region && e.Text != "");
            received.Clear();
        }
        Assert.True(controller.Settings.ExtraAreas[0].Enabled);

        controller.Settings = controller.Settings with { AreaPreset = AreaPreset.Bottom, Region = new CropRegion() };
        var back = await WaitForRegion();
        Assert.NotNull(back);
        Assert.Equal("area1", back.Id);
        controller.Stop();
    }

    /// <summary>Sürekli okunan bölge tuşa basmadan okunur ve çevirisi "region" olayıyla pencereye (ve TV'ye) gider.</summary>
    [Fact]
    public async Task LiveRegionIsReadWithoutAKeyPress()
    {
        var (controller, services) = Ready();
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        services.ReaderLines = new Reading([new TextLine("Find the blacksmith", new TextBox(0.1, 0.2, 0.9, 0.3))]);
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        controller.Settings = controller.Settings.WithArea(ExtraAreaPreset.Quest.Region(), live: true);
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += e => { lock (received) received.Add(e); };
        await controller.StartAsync();
        // Ek bölgenin kendi okuyucusu vardır (altyazının okumasını bekletmesin).
        Assert.Equal(2, services.ReaderLanguages.Count);
        var deadline = DateTime.UtcNow.AddSeconds(5);
        SubtitleEvent? region = null;
        while (region is null && DateTime.UtcNow < deadline)
        {
            services.Streams[0].Emit(Frame.Blank(64, 64));
            await Task.Delay(100);
            lock (received) region = received.FirstOrDefault(e => e.Kind == SubtitleEventKind.Region);
        }
        Assert.NotNull(region);
        Assert.Equal("area1", region.Id);
        Assert.NotEqual("", region.Text);
        controller.Stop();
        lock (received) Assert.Contains(received, e => e.Kind == SubtitleEventKind.RegionClear);
    }


    [Fact]
    public async Task SwitchingGamesRefreshesAnUnchangedLivePromptFromTheNewPack()
    {
        const string prompt = "Find the blacksmith";
        byte[] Pack(string translation) => System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(
            new Dictionary<string, string> { [PackKey.Key(prompt)!] = translation });
        var (controller, services) = Ready();
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        services.GamePacks = new GamePackLibrary(() => [("Hades.json", Pack("Demirciyi bul.")), ("Celeste.json", Pack("Nalbandı bul."))], null);
        services.ReaderLines = new Reading([new TextLine(prompt, new TextBox(0.1, 0.2, 0.9, 0.3))]);
        controller.Settings = (controller.Settings with { Output = SubtitleOutput.Computer, GamePacks = true })
            .WithArea(ExtraAreaPreset.Quest.Region(), live: true);
        var received = new System.Collections.Concurrent.ConcurrentQueue<SubtitleEvent>();
        controller.OverlayEvent += received.Enqueue;
        var frame = Frame.Blank(64, 64);
        async Task<bool> Shows(string translation)
        {
            var deadline = DateTime.UtcNow.AddSeconds(4);
            while (DateTime.UtcNow < deadline)
            {
                services.Streams[0].Emit(frame);
                if (received.Any(e => e.Kind == SubtitleEventKind.Region && e.Id == "area1" && e.Text == translation)) return true;
                await Task.Delay(50);
            }
            return false;
        }

        try
        {
            await controller.StartAsync();
            controller.ChooseGame("Hades");
            Assert.True(await Shows("Demirciyi bul."));
            received.Clear();
            controller.ChooseGame("Celeste");
            Assert.True(await Shows("Nalbandı bul."));
            Assert.Contains(received, e => e.Kind == SubtitleEventKind.RegionClear);
            Assert.DoesNotContain(received, e => e.Kind == SubtitleEventKind.Region && e.Text == "Demirciyi bul.");
        }
        finally { controller.Stop(); }
    }

    [Fact]
    public void ExtraAreasAreAddedChangedAndRemovedById()
    {
        var region = new CropRegion(0.1, 0.3, 0.6, 0.95);
        var settings = new UserSettings().WithArea(new CropRegion()).WithArea(region);
        Assert.Equal(region, settings.ExtraAreaAt(2)?.Region);
        var moved = new CropRegion(0.2, 0.4, 0.6, 0.95);
        settings = settings.WithExtraArea("area2", area => area with { Region = moved, Name = "Görev" });
        Assert.Equal(moved, settings.ExtraAreaAt(2)?.Region);
        Assert.Equal("Görev", settings.ExtraAreaAt(2)?.DisplayName(2));
        // Silinen alanın arkasındaki öne gelir; kısayolu da artık onu okur.
        settings = settings.WithoutExtraArea("area1");
        Assert.Equal("area2", settings.ExtraAreaAt(1)?.Id);
        Assert.Null(settings.ExtraAreaAt(2));
    }

    /// <summary>Ek alan sınırı yok (yeni arayüz): dördüncü ve sonrası eklenir; kısayol yalnız ilk üçünde.</summary>
    [Fact]
    public void ExtraAreasHaveNoLimit()
    {
        var settings = new UserSettings().WithArea(new CropRegion()).WithArea(new CropRegion()).WithArea(new CropRegion());
        Assert.True(settings.CanAddExtraArea);
        var more = settings.WithAddedExtraArea(ExtraArea.Create("Dördüncü", new CropRegion())).WithAddedExtraArea(ExtraArea.Create("Beşinci", new CropRegion()));
        Assert.Equal(5, more.ExtraAreas.Count);
        Assert.Equal(3, ExtraArea.ShortcutCount);
    }

    /// <summary>Yeni ek alan sürekli okunur ve sonucu TV'de gösterir (Mac, iPhone, Android ile aynı varsayılan).</summary>
    [Fact]
    public void NewExtraAreaIsReadContinuouslyAndShowsOnTheTv()
    {
        var area = ExtraArea.Create("Görev", ExtraAreaPreset.Quest.Region());
        Assert.True(area.Enabled);
        Assert.Equal(ResultTarget.Tv, area.Target);
        Assert.NotEqual(area.Id, ExtraArea.Create("Görev", ExtraAreaPreset.Quest.Region()).Id);
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
        controller.Settings = controller.Settings.WithArea(new CropRegion());
        Assert.Equal(ExtraRegionOutcome.NotRunning, await controller.TranslateExtraRegionAsync(1));
    }

    [Fact]
    public async Task EmptyRegionReportsNoText()
    {
        var (controller, services) = Ready();
        controller.Settings = controller.Settings.WithArea(new CropRegion());
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ExtraRegionOutcome.NoText, await controller.TranslateExtraRegionAsync(1));
        controller.Stop();
    }

    [Fact]
    public void FreeAreaResultShowsOnTheTvByDefault() =>
        Assert.Equal(ResultTarget.Tv, new UserSettings().FreeAreaTarget);

    [Fact]
    public async Task FreeAreaDoesNothingWhileTranslationIsStopped()
    {
        var (controller, _) = Ready();
        var (outcome, result) = await controller.TranslateAreaAsync(Frame.Blank(64, 64), new CropRegion());
        Assert.Equal(ExtraRegionOutcome.NotRunning, outcome);
        Assert.Null(result);
    }

    [Fact]
    public async Task FreeAreaWithoutTextReportsNoText()
    {
        var (controller, _) = Ready();
        await controller.StartAsync();
        var (outcome, result) = await controller.TranslateAreaAsync(Frame.Blank(64, 64), new CropRegion(0.2, 0.4, 0.2, 0.4));
        Assert.Equal(ExtraRegionOutcome.NoText, outcome);
        Assert.Null(result);
        controller.Stop();
    }

    [Fact]
    public void SnapshotRequestReachesListeners()
    {
        var (controller, _) = Ready();
        var raised = 0;
        controller.SnapshotRequested += () => raised++;
        controller.RequestSnapshot();
        Assert.Equal(1, raised);
    }

    [Fact]
    public void ExtraAreaResultsShowOnTheTvByDefault()
    {
        var settings = new UserSettings().WithArea(new CropRegion());
        Assert.Equal(ResultTarget.Tv, settings.ExtraAreas[0].Target);
    }

    [Fact]
    public void ThirdAreaAndItsTargetAreStoredSeparately()
    {
        var region = new CropRegion(0.3, 0.6, 0.3, 0.7);
        var settings = new UserSettings().WithArea(new CropRegion()).WithArea(new CropRegion()).WithArea(region, target: ResultTarget.Both);
        Assert.Equal(region, settings.ExtraAreaAt(3)?.Region);
        Assert.Equal(ResultTarget.Both, settings.ExtraAreaAt(3)?.Target);
        Assert.Equal(ResultTarget.Tv, settings.ExtraAreaAt(1)?.Target);
    }

    [Fact]
    public async Task PcTargetRaisesThePcResultOnly()
    {
        var (controller, services) = Ready();
        controller.Settings = controller.Settings.WithArea(new CropRegion()).WithArea(new CropRegion()).WithArea(new CropRegion(), target: ResultTarget.Pc);
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        string? shown = null;
        controller.PcResultReady += (text, _) => shown = text;
        Assert.Equal(ExtraRegionOutcome.NoText, await controller.TranslateExtraRegionAsync(3));
        Assert.Equal("No text found in this area.", shown);
        controller.Stop();
    }

    [Fact]
    public async Task TvTargetDoesNotRaiseThePcResult()
    {
        var (controller, services) = Ready();
        controller.Settings = controller.Settings.WithArea(new CropRegion());
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        var raised = false;
        controller.PcResultReady += (_, _) => raised = true;
        await controller.TranslateExtraRegionAsync(1);
        Assert.False(raised);
        controller.Stop();
    }
}

public class ScreenTranslationControllerTests
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
    public async Task DoesNothingWhileTranslationIsStopped()
    {
        var (controller, _) = Ready();
        Assert.Equal(ScreenOutcome.NotRunning, await controller.TranslateScreenAsync());
    }

    [Fact]
    public async Task EmptyScreenReportsNoText()
    {
        var (controller, services) = Ready();
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ScreenOutcome.NoText, await controller.TranslateScreenAsync());
        controller.Stop();
    }

    [Fact]
    public async Task SecondPressRemovesTheTranslations()
    {
        var (controller, services) = Ready();
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        services.ReaderLines = new Reading([new TextLine("Open the door.", new TextBox(0.4, 0.8, 0.6, 0.84))]);
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ScreenOutcome.Shown, await controller.TranslateScreenAsync());
        Assert.Equal(ScreenOutcome.Cleared, await controller.TranslateScreenAsync());
        Assert.Equal(ScreenOutcome.Shown, await controller.TranslateScreenAsync());
        controller.Stop();
    }

    /// <summary>
    /// Bildirilen hata (GTA 6): telefonda başka bir sohbete geçip tuşa basınca çeviriler kalkıyor, yeni sohbet hiç
    /// çevrilmiyordu. Ekran değiştiyse ikinci basış yeni ekranı çevirir; değişmediyse çevirileri kaldırır.
    /// </summary>
    [Fact]
    public async Task SecondPressOnAChangedScreenTranslatesTheNewOne()
    {
        var (controller, services) = Ready();
        controller.SubtitleEcho = null;
        services.ReaderLines = new Reading([new TextLine("Where are you man", new TextBox(0.74, 0.40, 0.94, 0.44))]);
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ScreenOutcome.Shown, await controller.TranslateScreenAsync());
        services.ReaderLines = new Reading([new TextLine("Did you get the money", new TextBox(0.74, 0.40, 0.94, 0.44))]);
        Assert.Equal(ScreenOutcome.Shown, await controller.TranslateScreenAsync());
        Assert.Equal(ScreenOutcome.Cleared, await controller.TranslateScreenAsync());
        controller.Stop();
    }

    /// <summary>
    /// Bildirilen hata: altyazı yalnız bilgisayar ekranındayken (TV yok, PS Remote Play monitörde) çeviriler yalnız TV'ye
    /// giden "screen" olayıyla gidiyor, altyazı penceresine hiç ulaşmıyordu; yalnız "Ekran çevriliyor…" görünüyordu.
    /// </summary>
    [Fact]
    public async Task ComputerOnlyShowsTheTranslationsInTheSubtitleWindow()
    {
        var (controller, services) = Ready();
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        services.ReaderLines = new Reading([new TextLine("Open the door.", new TextBox(0.4, 0.8, 0.6, 0.84))]);
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += e => { lock (received) received.Add(e); };
        await controller.StartAsync();
        services.Streams[0].Emit(Frame.Blank(64, 64));
        Assert.Equal(ScreenOutcome.Shown, await controller.TranslateScreenAsync());
        SubtitleEvent screen;
        lock (received) screen = Assert.Single(received, e => e.Kind == SubtitleEventKind.Screen);
        Assert.NotEqual("", screen.Text);
        Assert.NotEqual("Open the door.", screen.Text);
        Assert.Equal(ScreenOutcome.Cleared, await controller.TranslateScreenAsync());
        lock (received) Assert.Contains(received, e => e.Kind == SubtitleEventKind.ScreenClear);
        controller.Stop();
    }

    /// <summary>Çeviri sürüyor ama PS5'ten görüntü gelmedi: tuş sessizce yok sayılmaz.</summary>
    [Fact]
    public async Task NoPictureYetIsSaid()
    {
        var (controller, _) = Ready();
        controller.Settings = controller.Settings with { Output = SubtitleOutput.Computer };
        var received = new List<SubtitleEvent>();
        controller.OverlayEvent += e => { lock (received) received.Add(e); };
        await controller.StartAsync();
        Assert.Equal(ScreenOutcome.NotRunning, await controller.TranslateScreenAsync());
        lock (received) Assert.Contains(received, e => e.Kind == SubtitleEventKind.Subtitle && e.Text.Contains("PS5", StringComparison.Ordinal));
        controller.Stop();
    }
}
