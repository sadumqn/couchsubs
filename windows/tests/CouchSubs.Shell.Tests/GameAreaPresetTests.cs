// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;
using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Oyuna göre hazır ek alanlar: ne zaman eklenir, ne zaman kalkar.</summary>
public class GameAreaPresetTests
{
    private static IEnumerable<string> Ids(IReadOnlyList<WatchedArea> areas) => areas.Select(area => area.Id);

    /// <summary>Hazır alanlar varsayılan kapalı; bu testler kullanıcının bilerek açtığı ayarla çalışır.</summary>
    private static UserSettings On => new() { GameAreaPresets = true };

    [Fact]
    public void Gta6GetsBothAreasWhenTheUserHasNone() =>
        Assert.Equal(["preset-help", "preset-phone"], Ids(On.PresetAreas("GTA 6", phoneOpen: false)));

    [Fact]
    public void UserAreaOffSettingFullScreenAndProfileTurnThemOff()
    {
        var own = On.WithArea(ExtraAreaPreset.Quest.Region(), live: true);
        Assert.Empty(own.PresetAreas("GTA 6", false));
        Assert.Empty((On with { GameAreaPresets = false }).PresetAreas("GTA 6", false));
        Assert.Empty(On.WithAreaPreset(AreaPreset.Full).PresetAreas("GTA 6", false));
        Assert.Empty((On with { ActiveAreaProfile = "gta 6|window" }).PresetAreas("GTA 6", false));
        Assert.Empty(On.PresetAreas("Red Dead Redemption 2", false));
        // Kapalı (sürekli okunmayan) kullanıcı alanı hazır alanları engellemez.
        Assert.Equal(2, On.WithArea(ExtraAreaPreset.Quest.Region()).PresetAreas("GTA 6", false).Count);
    }

    [Fact]
    public void OpenPhoneLeavesOnlyTheHelpArea() =>
        Assert.Equal(["preset-help"], Ids(On.PresetAreas("GTA 6", phoneOpen: true)));

    [Fact]
    public void PresetsAreOffByDefaultAndInOldSettings()
    {
        Assert.False(new UserSettings().GameAreaPresets);
        Assert.Empty(new UserSettings().PresetAreas("GTA 6", false));
        Assert.False(JsonSerializer.Deserialize<UserSettings>("{}")!.GameAreaPresets);
        var on = JsonSerializer.Serialize(On);
        Assert.True(JsonSerializer.Deserialize<UserSettings>(on)!.GameAreaPresets);
    }

    [Fact]
    public void MigrationTurnsPresetsAndPhoneOffOnceWhenAutoScreenTextIsOff()
    {
        // beta.63–68 ayar dosyası: hazır alanlar açık (eski varsayılan), otomatik ekran yazısı kapalı.
        var beta68 = JsonSerializer.Deserialize<UserSettings>(
            """{"AutoScreenText":false,"AutoScreenTextReset":true,"GameAreaPresets":true,"AutoReadGamePhone":true}""")!;
        var migrated = ScreenTextExtrasMigration.Apply(AutoScreenTextMigration.Apply(beta68).Settings);
        Assert.False(migrated.GameAreaPresets);
        Assert.False(migrated.AutoReadGamePhone);
        Assert.False(migrated.ReadsGamePhone);
        Assert.True(migrated.ScreenTextExtrasReset);
        Assert.Empty(migrated.PresetAreas("GTA 6", false));
        // Kullanıcı sonra bilerek açarsa göç tekrarlanmaz.
        var reopened = JsonSerializer.Deserialize<UserSettings>(JsonSerializer.Serialize(migrated))! with
        {
            GameAreaPresets = true, AutoReadGamePhone = true,
        };
        Assert.Equal(reopened, ScreenTextExtrasMigration.Apply(reopened));
        // beta.63 dosyası (otomatik ekran yazısı açık geliyordu): önce o kapanır, ardından hazır alanlar da.
        var beta63 = JsonSerializer.Deserialize<UserSettings>("""{"AutoScreenText":true,"GameAreaPresets":true}""")!;
        Assert.False(ScreenTextExtrasMigration.Apply(AutoScreenTextMigration.Apply(beta63).Settings).GameAreaPresets);
    }

    [Fact]
    public void MigrationLeavesUsersWhoTurnedAutoScreenTextOn()
    {
        var on = JsonSerializer.Deserialize<UserSettings>(
            """{"AutoScreenText":true,"AutoScreenTextReset":true,"GameAreaPresets":true,"AutoReadGamePhone":true}""")!;
        var migrated = ScreenTextExtrasMigration.Apply(AutoScreenTextMigration.Apply(on).Settings);
        Assert.True(migrated.AutoScreenText);
        Assert.True(migrated.GameAreaPresets);
        Assert.True(migrated.AutoReadGamePhone);
        Assert.True(migrated.ScreenTextExtrasReset);
    }

    private static Frame PanelFrame()
    {
        var frame = Frame.Blank(400, 225);
        Array.Fill(frame.Pixels, (byte)120);
        for (var y = 8; y < 60; y++)
            for (var x = 6; x < 140; x++)
            {
                var p = y * frame.Stride + x * 4;
                var value = (byte)(((y >= 16 && y < 26) || (y >= 34 && y < 44)) && x % 7 < 3 ? 235 : 26);
                frame.Pixels[p] = frame.Pixels[p + 1] = frame.Pixels[p + 2] = value;
            }
        return frame;
    }

    [Fact]
    public async Task PresetAreaWithoutAnInterfacePanelShowsNothing()
    {
        // Oyun yanlış seçili (GTA 6) ama ekranda arayüz kutusu yok: hazır alan hiçbir şey çevirmez.
        var services = new FakeServices { ReaderLines = Reading.FromText("Follow Paulie to the car.") };
        var settings = new MemorySettings();
        settings.Save(new UserSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer, AutoScreenText = false,
                                         AutoScreenTextReset = true, GameAreaPresets = true, ScreenTextExtrasReset = true });
        using var controller = AppControllerTests.Make(services, settings: settings);
        var events = new ConcurrentQueue<SubtitleEvent>();
        controller.StreamEvent += events.Enqueue;
        controller.ChooseGame("GTA 6");
        await controller.StartAsync();
        var frame = Frame.Blank(400, 225);
        for (var i = 0; i < 40; i++)
        {
            services.Streams[0].Emit(frame);
            await Task.Delay(50);
        }
        Assert.DoesNotContain(events, e => e.Kind == SubtitleEventKind.Region && e.Text.Length > 0);
        controller.Stop();
    }

    [Fact]
    public async Task PresetAreasAreReadForGta6AndLeaveWhenTheGameChanges()
    {
        var services = new FakeServices { ReaderLines = Reading.FromText("Follow Paulie to the car.") };
        var settings = new MemorySettings();
        var userRegion = new CropRegion(0.70, 0.90, 0.20, 0.80);
        var overlay = new OverlayBounds(100, 600, 900);
        settings.Save(new UserSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer, AutoScreenText = false,
                                         AutoScreenTextReset = true, GameAreaPresets = true, ScreenTextExtrasReset = true,
                                         Overlay = overlay }.WithCustomRegion(userRegion));
        using var controller = AppControllerTests.Make(services, settings: settings);
        // Sahte okuyucu altyazıya ve alana aynı yazıyı verir; altyazı yinelemesi engeli burada sınanmıyor.
        controller.SubtitleEcho = null;
        var events = new ConcurrentQueue<SubtitleEvent>();
        controller.StreamEvent += events.Enqueue;
        controller.ChooseGame("GTA 6");
        await controller.StartAsync();
        // Hazır alan ancak arayüz kutusu kanıtıyla okunur: sol üstte koyu panel üstünde beyaz yazı çizgileri.
        var frame = PanelFrame();
        bool Shown() => events.Any(e => e.Kind == SubtitleEventKind.Region && e.Id == "preset-help" && e.Text.Length > 0);
        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(6)))
            while (!Shown())
            {
                services.Streams[0].Emit(frame);
                await Task.Delay(60, timeout.Token);
            }
        // Hazır alanlar kullanıcının altyazı alanını, ek alanlarını ve altyazı penceresinin yerini değiştirmez.
        Assert.Equal(userRegion, controller.Settings.Region);
        Assert.Equal(AreaPreset.Custom, controller.Settings.AreaPreset);
        Assert.Empty(controller.Settings.ExtraAreas);
        Assert.Equal(overlay, controller.Settings.Overlay);
        Assert.Equal(userRegion, settings.Load().Region);
        events.Clear();
        controller.ChooseGame("Far Cry 3");
        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(6)))
            while (!events.Any(e => e.Kind is SubtitleEventKind.RegionClear
                       || (e.Kind == SubtitleEventKind.Region && e.Id == "preset-help" && e.Text.Length == 0)))
            {
                services.Streams[0].Emit(frame);
                await Task.Delay(60, timeout.Token);
            }
        controller.Stop();
    }

    [Fact]
    public async Task Beta68SettingsTranslateNothingOutsideTheSubtitleAreaInGta6()
    {
        // X bildirimi (GTA 6): otomatik ekran yazısı kapalıyken menüde ve oyun içinde kısmi çeviri vardı; hazır alanlar
        // beta.63–68'de varsayılan açıktı. Göçten sonra sol üstteki arayüz kutusu da okunmaz.
        var services = new FakeServices { ReaderLines = Reading.FromText("Follow Paulie to the car.") };
        var settings = new MemorySettings();
        settings.Save(new UserSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer, AutoScreenText = false,
                                         AutoScreenTextReset = true, GameAreaPresets = true });
        using var controller = AppControllerTests.Make(services, settings: settings);
        controller.SubtitleEcho = null;
        Assert.False(controller.Settings.GameAreaPresets);
        Assert.True(settings.Load().ScreenTextExtrasReset);
        var events = new ConcurrentQueue<SubtitleEvent>();
        controller.StreamEvent += events.Enqueue;
        controller.ChooseGame("GTA 6");
        await controller.StartAsync();
        var frame = PanelFrame();
        for (var i = 0; i < 40; i++)
        {
            services.Streams[0].Emit(frame);
            await Task.Delay(50);
        }
        Assert.DoesNotContain(events, e => e.Kind == SubtitleEventKind.Region && e.Text.Length > 0);
        controller.Stop();
    }
}
