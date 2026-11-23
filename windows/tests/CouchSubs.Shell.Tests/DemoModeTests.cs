// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;

namespace CouchSubs.Shell.Tests;

/// <summary>
/// Deneme modu (Mac AppModel.startDemo / exitDemo ile aynı davranış): konsol, hesap ve TV olmadan örnek karelerle çeviri.
/// Sahte servisler deneme akışını değiştirmez; gerçek <see cref="DemoStream"/> yazısız kare verir, satırı sahte okuyucu "okur".
/// </summary>
public class DemoModeTests
{
    /// <summary>Kurulumu bitmiş uygulama (PS5 ve TV eşleşmiş).</summary>
    private static (AppController Controller, FakeServices Services) Ready(FakeServices? services = null)
    {
        services ??= new FakeServices();
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, new RegisteredConsole("192.168.1.253", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        return (AppControllerTests.Make(services, store), services);
    }

    private static async Task WaitUntil(Func<bool> condition)
    {
        for (var i = 0; i < 500 && !condition(); i++) await Task.Delay(20);
        Assert.True(condition());
    }

    [Fact]
    public async Task DemoStartsWithoutConsoleAccountOrTvAndExitReturnsToSetup()
    {
        var services = new FakeServices();
        var sleep = new FakeSleep();
        var controller = AppControllerTests.Make(services, sleep: sleep);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        Assert.False(controller.CanStart);
        var changed = new List<string?>();
        controller.PropertyChanged += (_, e) => changed.Add(e.PropertyName);

        await controller.StartDemoAsync();
        Assert.True(controller.DemoMode);
        Assert.True(controller.IsRunning);
        Assert.False(controller.IsStarting);
        // Konsola bağlanılmaz; durum karosu "Deneme modu · Örnek görüntüler" yazar.
        Assert.Empty(services.Streams);
        Assert.Equal("Demo mode", controller.ConsoleTitle);
        Assert.Equal("Sample pictures", controller.Ps5StatusText);
        Assert.Equal(SessionPhase.Streaming, controller.SessionState.Phase);
        Assert.Equal(StatusTone.Good, controller.Ps5Tone);
        Assert.True(sleep.Active);
        // Kurulum adımı değişmez: ana ekranı deneme modu açar (ShellWindow), çıkınca kalınan adıma dönülür.
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        Assert.Contains(nameof(AppController.DemoMode), changed);
        Assert.Contains(nameof(AppController.ConsoleTitle), changed);
        Assert.Contains(nameof(AppController.Ps5StatusText), changed);

        changed.Clear();
        controller.ExitDemo();
        Assert.False(controller.DemoMode);
        Assert.False(controller.IsRunning);
        Assert.False(sleep.Active);
        Assert.Equal(OnboardingStep.Welcome, controller.Step);
        Assert.Contains(nameof(AppController.DemoMode), changed);
        Assert.NotEqual("Sample pictures", controller.Ps5StatusText);
        Assert.NotEqual("Demo mode", controller.ConsoleTitle);
        controller.Dispose();
    }

    /// <summary>Çeviri modeli inmemişken de deneme baştan sona çalışır: satırların gömülü hazır çevirisi gösterilir.</summary>
    [Fact]
    public async Task WithoutTheModelDemoLinesUseTheBuiltInTranslations()
    {
        var line = DemoScript.Lines[4];
        var services = new FakeServices { ReaderLines = Reading.FromText(line.English) };
        services.Translation.Installed = false;
        var controller = AppControllerTests.Make(services);
        await controller.StartDemoAsync();
        await WaitUntil(() => controller.LastTranslation.Length > 0);
        Assert.Equal(line.English, controller.LastSource);
        Assert.Equal(line.Turkish, controller.LastTranslation);
        Assert.Equal(line.Turkish, controller.History[0].Translation);
        // Okunan kare deneme karesidir (ana ekrandaki örnek görüntü karosu bunu gösterir).
        Assert.Equal((DemoFrames.Width, DemoFrames.Height), (controller.LastFrame?.Width, controller.LastFrame?.Height));
        controller.ExitDemo();
        controller.Dispose();
    }

    [Fact]
    public async Task StartingDemoWhileTranslatingStopsTheConsoleSessionFirst()
    {
        var (controller, services) = Ready();
        await controller.StartAsync();
        var console = Assert.Single(services.Streams);
        Assert.True(console.Started);
        Assert.False(controller.DemoMode);

        await controller.StartDemoAsync();
        Assert.False(console.Started);
        Assert.Single(services.Streams);
        Assert.True(controller.DemoMode);
        Assert.True(controller.IsRunning);
        Assert.Equal("Sample pictures", controller.Ps5StatusText);

        // Çıkınca gerçek çeviri yeniden başlatılabilir; PS5'e bağlanılır.
        controller.ExitDemo();
        Assert.False(controller.IsRunning);
        await controller.StartAsync();
        Assert.False(controller.DemoMode);
        Assert.Equal(2, services.Streams.Count);
        Assert.True(services.Streams[1].Started);
        Assert.Equal("PS5", controller.ConsoleTitle);
        controller.Dispose();
    }

    /// <summary>"Durdur" da deneme modunu kapatır; uygulama deneme modunda takılı kalmaz.</summary>
    [Fact]
    public async Task StoppingEndsDemoMode()
    {
        var controller = AppControllerTests.Make();
        await controller.StartDemoAsync();
        controller.Stop();
        Assert.False(controller.DemoMode);
        Assert.False(controller.IsRunning);
        // Kurulum bitmeden gerçek çeviri başlamaz.
        await controller.StartAsync();
        Assert.False(controller.IsRunning);
        // Deneme yeniden açılabilir; ikinci çağrı ikinci bir oturum açmaz.
        await controller.StartDemoAsync();
        await controller.StartDemoAsync();
        Assert.True(controller.DemoMode);
        Assert.True(controller.IsRunning);
        controller.Dispose();
        Assert.False(controller.IsRunning);
    }

    /// <summary>Deneme modunda PS5'e özgü ipuçları ve oyun sorusu görünmez.</summary>
    [Fact]
    public async Task DemoHidesConsoleTipsAndTheGameQuestion()
    {
        var (controller, _) = Ready();
        Assert.Equal(FrameSource.Ps5, controller.Settings.FrameSource);
        await controller.StartDemoAsync();
        Assert.False(controller.ShowsMainAccountTip);
        Assert.False(controller.ShowsSubtitleOffTip);
        Assert.False(controller.AskingGame);
        controller.ExitDemo();
        // Gerçek çeviride ilk altyazıya kadar "ana hesabı seçin" ipucu görünür.
        await controller.StartAsync();
        Assert.True(controller.ShowsMainAccountTip);
        controller.Dispose();
    }

    /// <summary>Deneme satırları oyun paketlerinde aranmaz: paket açık ve satır pakette olsa da çeviri paketten gelmez.</summary>
    [Fact]
    public async Task DemoLinesAreNotLookedUpInGamePacks()
    {
        var line = DemoScript.Lines[2];
        var pack = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, string> { [PackKey.Key(line.English)!] = "PAKET" });
        var services = new FakeServices { ReaderLines = Reading.FromText(line.English) };
        services.GamePacks = new GamePackLibrary(() => [("Oyun.json", pack)], null);
        services.Translation.Installed = false;
        var controller = AppControllerTests.Make(services);
        controller.Settings = controller.Settings with { GamePacks = true };
        Assert.NotNull(services.FindInPacks(line.English));
        await controller.StartDemoAsync();
        await WaitUntil(() => controller.LastTranslation.Length > 0);
        Assert.Equal(line.Turkish, controller.LastTranslation);
        Assert.Equal(LineOrigin.Engine, controller.History[0].Origin);
        controller.ExitDemo();
        controller.Dispose();
    }

    [Fact]
    public async Task DemoStreamDeliversFramesAndReportsStreaming()
    {
        var states = new List<SessionState>();
        var got = new TaskCompletionSource<Frame>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var stream = new DemoStream(DemoFrames.Plain);
        stream.StateChanged += states.Add;
        stream.FrameReceived += frame => got.TrySetResult(frame);
        stream.Start();
        var frame = await got.Task.WaitAsync(TimeSpan.FromSeconds(5));
        stream.Stop();
        Assert.Equal([SessionState.Streaming], states);
        Assert.Equal((DemoFrames.Width, DemoFrames.Height), (frame.Width, frame.Height));
    }
}
