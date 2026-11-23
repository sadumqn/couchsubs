// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Otomatik ekran yazısının türleri Ayarlar'dan ayrı açılıp kapanır (Mac/iPhone: ScreenTextKindTests.swift, Android:
/// ScreenTextKindTest.kt). Ayar tarafı: CouchSubs.Shell.Tests/ScreenTextKindSettingsTests.
/// </summary>
public class ScreenTextKindTests
{
    [Fact]
    public void KindOfAnArea()
    {
        Assert.Equal([ScreenTextKind.Help, ScreenTextKind.Phone],
                     GameAreaPresets.Areas("GTA 6").Select(area => ScreenTextKinds.Of(area)));
        Assert.Equal(ScreenTextKind.Mission, ScreenTextKinds.Of(new WatchedArea(MissionLine.AreaId, "Mission", new CropRegion()) { Auto = true }));
        var auto = new WatchedArea("auto-1", ScreenTextDetector.AreaName, new CropRegion()) { Auto = true };
        Assert.Null(ScreenTextKinds.Of(auto)); // menü dışındaki otomatik alanın türü yazısından çıkar
        Assert.Equal(ScreenTextKind.Menu, ScreenTextKinds.Of(auto with { Menu = true }));
        Assert.Null(ScreenTextKinds.Of(new WatchedArea("area1", "Area 1", new CropRegion()))); // kullanıcının kendi alanı
    }

    [Fact]
    public void KindOfAutoText()
    {
        Assert.Equal(ScreenTextKind.Help, ScreenTextKinds.Of([$"Press {ButtonIcons.Marker} to open the phone"]));
        Assert.Equal(ScreenTextKind.Help, ScreenTextKinds.Of(["R2 Aim"]));
        Assert.Equal(ScreenTextKind.Help, ScreenTextKinds.Of(["You can buy properties from the website on your phone."]));
        Assert.Equal(ScreenTextKind.Help, ScreenTextKinds.Of(["VICE CITY", "Leonida Keys"])); // birden çok parça: kutu
        Assert.Equal(ScreenTextKind.Other, ScreenTextKinds.Of(["Ocean Drive"]));
        Assert.Equal(ScreenTextKind.Mission, ScreenTextKinds.Of(["Follow Paulie to the car."]));
    }

    // RegionWatcher

    private sealed class Reader : ITextReader
    {
        public List<TextLine> Lines { get; set; } = [];
        public string Read(Frame image) => "";
        public Reading ReadLines(Frame image, bool deep) => new(Lines);
    }

    private sealed class Translator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
            Task.FromResult($"çeviri {text.Length}");
    }

    private sealed class Server : IRegionSender
    {
        public List<(string Id, string Text)> Sent { get; } = [];
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight = null)
        {
            lock (Sent) Sent.Add((id, text));
        }
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight, IReadOnlyList<IconPlacement>? icons,
                               IReadOnlyList<ScreenTranslation.Item>? blocks) => SendRegion(id, text, box, lineHeight);
        public void ClearRegions() { }
        public int Drawn => Sent.Count(item => item.Text.Length > 0);
    }

    private static TextLine Line(string text, double top = 0.3) => new(text, new TextBox(0.1, top, 0.9, top + 0.2));

    private static (RegionWatcher Watcher, Server Server) Watcher(HashSet<ScreenTextKind> on, params TextLine[] lines)
    {
        var server = new Server();
        var watcher = new RegionWatcher(new Reader { Lines = [.. lines] }, new Translator(), server) { Allows = on.Contains };
        return (watcher, server);
    }

    private static readonly HashSet<ScreenTextKind> Defaults = [ScreenTextKind.Phone, ScreenTextKind.Mission, ScreenTextKind.Help];

    private static async Task Twice(RegionWatcher watcher, WatchedArea area)
    {
        await watcher.PassAsync(Frame.Blank(320, 180), [area]);
        await watcher.PassAsync(Frame.Blank(320, 180), [area]);
    }

    /// <summary>Menüler kapalıyken (varsayılan) menü alanı okunmaz; açılınca çevrilir.</summary>
    [Fact]
    public async Task MenuAreaIsTranslatedOnlyWhenMenusAreOn()
    {
        var area = new WatchedArea("auto-1", ScreenTextDetector.AreaName, new CropRegion(0.2, 0.4, 0.1, 0.5)) { Auto = true, Menu = true };
        TextLine[] lines = [Line("Story Mode"), Line("Online Settings", 0.6)];
        var (off, offServer) = Watcher(Defaults, lines);
        await Twice(off, area);
        Assert.Empty(offServer.Sent);
        var (on, onServer) = Watcher([.. Defaults, ScreenTextKind.Menu], lines);
        await Twice(on, area);
        Assert.True(onServer.Drawn > 0);
    }

    /// <summary>Kısa tek satır "diğer" türdür (varsayılan kapalı); tuş ipucu yardım/eylemdir (varsayılan açık).</summary>
    [Fact]
    public async Task AutoAreaKindComesFromItsText()
    {
        var area = new WatchedArea("auto-1", ScreenTextDetector.AreaName, new CropRegion(0.2, 0.4, 0.1, 0.5)) { Auto = true };
        var (other, otherServer) = Watcher(Defaults, Line("Welcome to Ocean Drive Beach"));
        var rejected = new List<string>();
        other.Rejected = rejected.Add;
        await Twice(other, area);
        Assert.Equal(0, otherServer.Drawn);
        Assert.Equal(["auto-1"], rejected); // kapalı tür dedektöre bildirilir
        var (help, helpServer) = Watcher(Defaults, Line("Press X to open the phone menu now"));
        await Twice(help, area);
        Assert.Equal(1, helpServer.Drawn);
    }

    /// <summary>Görev kapalıyken görev satırının alanı okunmaz; açıkken kendi yerinde çizilir.</summary>
    [Fact]
    public async Task MissionAreaFollowsItsKind()
    {
        var mission = new WatchedArea(MissionLine.AreaId, "Mission", new CropRegion(0.85, 0.92, 0.3, 0.7)) { Auto = true };
        var line = Line("Get in the sea plane and fly to the island");
        var (off, offServer) = Watcher([ScreenTextKind.Phone, ScreenTextKind.Help], line);
        await Twice(off, mission);
        Assert.Empty(offServer.Sent);
        var (on, onServer) = Watcher(Defaults, line);
        await Twice(on, mission);
        Assert.Equal([MissionLine.AreaId], onServer.Sent.Where(item => item.Text.Length > 0).Select(item => item.Id));
    }
}
