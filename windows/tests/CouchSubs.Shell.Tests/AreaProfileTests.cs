// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using CouchSubs.Core.LgTv;
using CouchSubs.RemotePlay;
using CouchSubs.Shell;
using Xunit;

namespace CouchSubs.Shell.Tests;

/// <summary>Oyuna göre alanlar: kaydetme, oyun seçilince uygulama, geri alma ve oturum sonunda genel alanlara dönüş.</summary>
public class AreaProfileTests
{
    private static readonly CropRegion General = new(0.62, 0.97, 0.14, 0.86);
    private static readonly CropRegion FarCryArea = new(0.70, 0.95, 0.20, 0.80);
    private static readonly CropRegion Quest = new(0.03, 0.30, 0.66, 0.98);

    private static (AppController Controller, MemorySettings Settings) Ready(UserSettings? saved = null)
    {
        var store = new MemoryStore();
        store.Save(StoreKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
        store.Save(StoreKeys.Console, new RegisteredConsole("192.168.1.253", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));
        store.Save(StoreKeys.Tv, new LgTv("LG TV", "127.0.0.1"));
        store.Save(StoreKeys.TvKey, "tv-key");
        var settings = new MemorySettings();
        if (saved is not null) settings.Save(saved);
        return (AppControllerTests.Make(store: store, settings: settings), settings);
    }

    /// <summary>Far Cry 3 için alanları kaydeder ve oturumu bitirir: genel alan <see cref="General"/>, profil <see cref="FarCryArea"/> + görev alanı.</summary>
    private static async Task<(AppController Controller, MemorySettings Settings)> WithFarCryProfile()
    {
        var (controller, settings) = Ready();
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        controller.Settings = controller.Settings.WithCustomRegion(FarCryArea).WithArea(Quest, live: true);
        controller.SaveAreaProfile();
        controller.Stop();
        return (controller, settings);
    }

    [Fact]
    public async Task AreasCanBeSavedOnlyWhileTranslatingAGameThatIsKnown()
    {
        var (controller, _) = Ready();
        Assert.Null(controller.AreaProfileTarget);
        controller.SaveAreaProfile();
        Assert.Empty(controller.Settings.AreaProfiles);

        await controller.StartAsync();
        Assert.Null(controller.AreaProfileTarget);
        controller.ChooseGame("Far Cry 3");
        Assert.Equal("Far Cry 3", controller.AreaProfileTarget);
        controller.SaveAreaProfile();
        var profile = Assert.Single(controller.Settings.AreaProfiles);
        Assert.Equal("far cry 3|stream", profile.Key);
        Assert.Equal("Far Cry 3", controller.AreaProfileGame);
        Assert.False(controller.AreaProfileUnsaved);
    }

    [Fact]
    public async Task TheSessionEndsWithTheGeneralAreasAndTheGamesAreasComeBackWithTheGame()
    {
        var (controller, settings) = await WithFarCryProfile();
        // Profil yokken yapılan değişiklik genel ayardı; kaydedilince profil o alanlarla oluşur, oturum bitince genel ayar kalır.
        Assert.Null(controller.AreaProfileGame);
        Assert.Null(controller.Settings.GeneralAreas);
        Assert.Equal(FarCryArea, controller.Settings.Region);

        controller.Settings = controller.Settings.WithCustomRegion(General) with { ExtraAreas = [] };
        // Elle seçilen oyun uygulama açık kaldıkça hatırlanır; ama başka oyuna geçilmiş olabilir: alanları sorulur,
        // kendiliğinden uygulanmaz. Oyun yeniden seçilince gelir.
        await controller.StartAsync();
        Assert.Null(controller.AreaProfileGame);
        Assert.Equal("Far Cry 3", controller.OfferedAreaProfileGame);
        Assert.Equal(General, controller.Settings.Region);
        controller.ChooseGame("Far Cry III");
        Assert.Equal("Far Cry 3", controller.AreaProfileGame);
        Assert.Equal(FarCryArea, controller.Settings.Region);
        var quest = Assert.Single(controller.Settings.ExtraAreas);
        Assert.Equal(Quest, quest.Region);
        Assert.True(quest.Enabled);
        Assert.Single(controller.Settings.WatchedAreas());
        Assert.Equal(General, settings.Saved?.GeneralAreas?.Region);

        controller.Stop();
        Assert.Null(controller.AreaProfileGame);
        Assert.Equal(General, controller.Settings.Region);
        Assert.Empty(controller.Settings.ExtraAreas);
        Assert.Null(settings.Saved?.ActiveAreaProfile);
    }

    [Fact]
    public async Task ChangesInAProfileAreKeptOnlyWhenSaved()
    {
        var (controller, _) = await WithFarCryProfile();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        var moved = new CropRegion(0.50, 0.80, 0.20, 0.80);
        controller.Settings = controller.Settings.WithCustomRegion(moved);
        Assert.True(controller.AreaProfileUnsaved);
        controller.Stop();
        Assert.Equal(General, controller.Settings.Region);

        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        Assert.Equal(FarCryArea, controller.Settings.Region);
        controller.Settings = controller.Settings.WithCustomRegion(moved);
        controller.SaveAreaProfile();
        Assert.False(controller.AreaProfileUnsaved);
        controller.Stop();
        Assert.Equal(General, controller.Settings.Region);
        Assert.Equal(moved, Assert.Single(controller.Settings.AreaProfiles).Areas.Region);
    }

    [Fact]
    public async Task UndoKeepsTheGeneralAreasForTheRestOfTheSession()
    {
        var (controller, _) = await WithFarCryProfile();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        controller.UndoAreaProfile();
        Assert.Null(controller.AreaProfileGame);
        Assert.Equal(General, controller.Settings.Region);
        controller.ChooseGame("Far Cry 3");
        Assert.Equal(General, controller.Settings.Region);

        // Yeni oturumda yeniden uygulanır.
        controller.Stop();
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        Assert.Equal(FarCryArea, controller.Settings.Region);
    }

    [Fact]
    public async Task AnotherGameWithoutAProfileGoesBackToTheGeneralAreas()
    {
        var (controller, _) = await WithFarCryProfile();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        controller.ChooseGame("Hades");
        Assert.Null(controller.AreaProfileGame);
        Assert.Equal(General, controller.Settings.Region);
        Assert.Equal("Hades", controller.AreaProfileTarget);
    }

    [Fact]
    public async Task DeletingTheProfileGoesBackToTheGeneralAreas()
    {
        var (controller, _) = await WithFarCryProfile();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        await controller.StartAsync();
        controller.ChooseGame("Far Cry 3");
        controller.DeleteAreaProfile();
        Assert.Empty(controller.Settings.AreaProfiles);
        Assert.Null(controller.AreaProfileGame);
        Assert.Equal(General, controller.Settings.Region);
    }

    [Fact]
    public void AProfileLeftOpenByACrashIsClosedAtStartup()
    {
        var general = new UserSettings().WithCustomRegion(General).Areas;
        var profile = new AreaProfile("far cry 3|stream", "Far Cry 3", general with { Region = FarCryArea });
        var saved = new UserSettings().WithAreas(profile.Areas) with
        {
            AreaProfiles = [profile], ActiveAreaProfile = profile.Key, GeneralAreas = general,
        };
        var (controller, settings) = Ready(saved);
        Assert.Equal(General, controller.Settings.Region);
        Assert.Null(controller.Settings.ActiveAreaProfile);
        Assert.Null(controller.Settings.GeneralAreas);
        Assert.Single(controller.Settings.AreaProfiles);
        Assert.Null(settings.Saved?.GeneralAreas);
    }

    private static readonly CropRegion GtaArea = new(0.74, 0.93, 0.18, 0.82);
    private static readonly CropRegion AcArea = new(0.80, 0.98, 0.10, 0.90);

    /// <summary>
    /// Kullanıcının bildirdiği durum: GTA 6 için alanlar kaydedildi, sonraki oturumda Assassin's Creed oynandı, seçim GTA
    /// 6'da kaldı. Eskiden GTA 6 profili kendiliğinden uygulanıyor, AC için yapılan değişiklik GTA 6'nın üzerine yazılıyordu.
    /// </summary>
    [Fact]
    public async Task AnotherGamesAreasNeverOverwriteAProfile()
    {
        var (controller, _) = Ready();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        await controller.StartAsync();
        controller.ChooseGame("GTA 6");
        controller.Settings = controller.Settings.WithCustomRegion(GtaArea);
        controller.SaveAreaProfile();
        controller.Stop();
        controller.Settings = controller.Settings.WithCustomRegion(General);

        await controller.StartAsync();
        Assert.Equal("GTA 6", controller.OfferedAreaProfileGame);
        controller.DeclineOfferedAreaProfile();
        controller.Settings = controller.Settings.WithCustomRegion(AcArea);
        Assert.True(controller.AreaProfileTargetHasOther);
        controller.SaveAreaProfile();
        Assert.Equal(GtaArea, controller.Settings.FindAreaProfile("gta 6|stream")?.Areas.Region);

        Assert.Equal(AreaProfiles.Edit.Done, controller.SaveAreaProfileAs("Assassin's Creed Valhalla"));
        Assert.Equal("Assassin's Creed Valhalla", controller.PlayedGame);
        Assert.Equal("assassins creed valhalla|stream", controller.Settings.ActiveAreaProfile);
        Assert.Equal(AreaProfiles.Edit.Exists, controller.SaveAreaProfileAs("Grand Theft Auto VI"));
        controller.Settings = controller.Settings.WithCustomRegion(General);
        controller.SaveAreaProfile();
        Assert.Equal(General, controller.Settings.FindAreaProfile("assassins creed valhalla|stream")?.Areas.Region);
        Assert.Equal(GtaArea, controller.Settings.FindAreaProfile("gta 6|stream")?.Areas.Region);

        controller.UseAreaProfile("gta 6|stream");
        Assert.Equal(GtaArea, controller.Settings.Region);
        Assert.Equal("GTA 6", controller.PlayedGame);
        controller.Stop();
        Assert.Equal(AcArea, controller.Settings.Region);
        Assert.Equal(2, controller.Settings.AreaProfiles.Count);
    }

    [Fact]
    public void ProfilesCanBeAddedRenamedDuplicatedAndDeletedWhileStopped()
    {
        var (controller, _) = Ready();
        controller.Settings = controller.Settings.WithCustomRegion(General);
        Assert.Equal(AreaProfiles.Edit.Done, controller.SaveAreaProfileAs("GTA 6"));
        Assert.Equal(AreaProfiles.Edit.Empty, controller.SaveAreaProfileAs("  "));
        Assert.Equal("GTA 6", controller.PlayedGame);
        Assert.Equal(AreaProfiles.Edit.Done, controller.DuplicateAreaProfile("gta 6|stream", "Mafia: The Old Country"));
        Assert.Equal(AreaProfiles.Edit.Exists, controller.DuplicateAreaProfile("gta 6|stream", "Grand Theft Auto VI"));
        Assert.Equal(AreaProfiles.Edit.Exists, controller.RenameAreaProfile("gta 6|stream", "Mafia The Old Country"));
        Assert.Equal(AreaProfiles.Edit.Done, controller.RenameAreaProfile("gta 6|stream", "Red Dead Redemption 2"));
        Assert.Equal("rdr 2|stream", controller.Settings.ActiveAreaProfile);
        Assert.Equal("Red Dead Redemption 2", controller.PlayedGame);
        Assert.Equal(["Mafia: The Old Country", "Red Dead Redemption 2"], controller.GameProfiles.Select(profile => profile.Game));
        controller.DeleteAreaProfile("rdr 2|stream");
        Assert.Null(controller.Settings.ActiveAreaProfile);
        Assert.Equal("mafia the old country|stream", Assert.Single(controller.Settings.AreaProfiles).Key);
    }

    /// <summary>Eski sürümün kaydı (20 profil): hiçbiri kaybolmaz, her oyun kendi alanlarında kalır.</summary>
    [Fact]
    public void OldSettingsKeepEveryGamesProfile()
    {
        var areas = new UserSettings().WithCustomRegion(General).Areas;
        var old = new UserSettings() with
        {
            AreaProfiles = [.. Enumerable.Range(0, 20).Select(i => new AreaProfile($"game {i}|stream", $"Game {i}", areas with { Region = GtaArea }))],
        };
        var json = System.Text.Json.JsonSerializer.Serialize(old);
        var (controller, _) = Ready(System.Text.Json.JsonSerializer.Deserialize<UserSettings>(json));
        Assert.Equal(20, controller.Settings.AreaProfiles.Count);
        Assert.Equal(GtaArea, controller.Settings.FindAreaProfile("game 7|stream")?.Areas.Region);
    }

    [Fact]
    public void OldSettingsFilesHaveNoProfiles()
    {
        var old = System.Text.Json.JsonSerializer.Deserialize<UserSettings>("""{"Region":{"Top":0.5,"Bottom":0.9,"Left":0.1,"Right":0.9}}""")!;
        Assert.Empty(old.AreaProfiles);
        Assert.Null(old.ActiveAreaProfile);
        var copy = System.Text.Json.JsonSerializer.Deserialize<UserSettings>(System.Text.Json.JsonSerializer.Serialize(
            old.WithSavedAreaProfile("Hades")))!;
        Assert.Equal("Hades", Assert.Single(copy.AreaProfiles).Game);
        Assert.Equal(old.Region, copy.AreaProfiles[0].Areas.Region);
    }
}
