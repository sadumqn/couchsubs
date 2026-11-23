// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;

namespace CouchSubs.Shell.Tests;

/// <summary>Eski üç sabit ek bölge yuvası (ExtraRegion1-3) adlı ek alan listesine kayıpsız dönüşür.</summary>
public class ExtraAreaMigrationTests
{
    private static readonly CropRegion Quest = new(0.03, 0.30, 0.66, 0.98);
    private static readonly CropRegion Phone = new(0.50, 0.95, 0.72, 0.98);

    /// <summary>Eski sürümün yazdığı gibi bir ayar dosyası (yuva 1 boş, 2 ve 3 dolu).</summary>
    private static string Legacy(string extra = "") => $$"""
        {
          "Region": { "Top": 0.6, "Bottom": 0.9, "Left": 0.1, "Right": 0.9 },
          "ExtraRegion2": { "Top": 0.03, "Bottom": 0.30, "Left": 0.66, "Right": 0.98 },
          "ExtraRegion3": { "Top": 0.50, "Bottom": 0.95, "Left": 0.72, "Right": 0.98 },
          "ExtraTarget1": 2,
          "ExtraTarget2": 1,
          "ExtraTarget3": 2,
          "ExtraLive1": true,
          "ExtraLive2": false,
          "ExtraLive3": true,
          "FreeAreaTarget": 1,
          "Hotkeys": [ { "Action": "ExtraRegion3", "Slot": 1, "Key": { "Modifiers": "Alt", "VirtualKey": 113 } } ]
          {{extra}}
        }
        """;

    [Fact]
    public void FilledSlotsBecomeAreasWithTheirPlaceLiveChoiceAndTarget()
    {
        var settings = ExtraAreaMigration.Load(Legacy());
        Assert.Equal(2, settings.ExtraAreas.Count);
        var (second, third) = (settings.ExtraAreas[0], settings.ExtraAreas[1]);
        Assert.Equal(new ExtraArea("area2", "", Quest, false, ResultTarget.Pc), second);
        Assert.Equal(new ExtraArea("area3", "", Phone, true, ResultTarget.Both), third);
        // Diğer ayarlar olduğu gibi kalır.
        Assert.Equal(new CropRegion(0.6, 0.9, 0.1, 0.9), settings.Region);
        Assert.Equal(ResultTarget.Pc, settings.FreeAreaTarget);
        // Sürekli okunan yalnız eski 3. yuva; TV'deki kutusunun kimliği değişmez.
        Assert.Equal("area3", Assert.Single(settings.WatchedAreas()).Id);
    }

    /// <summary>Alan öne kayınca kısayolu da onunla gelir: eskiden Num 2 ile okunan alan yine Num 2 ile okunur.</summary>
    [Fact]
    public void ShortcutsMoveWithTheirAreas()
    {
        var settings = ExtraAreaMigration.Load(Legacy());
        var keys = settings.Hotkeys;
        Assert.Equal(new HotkeyKey(HotkeyModifiers.None, HotkeyTable.NumPad0 + 2), HotkeyTable.KeyFor(keys, HotkeyAction.ExtraRegion1, 0));
        Assert.Equal(new HotkeyKey(HotkeyModifiers.Control | HotkeyModifiers.Shift, HotkeyTable.Digit0 + 2), HotkeyTable.KeyFor(keys, HotkeyAction.ExtraRegion1, 1));
        // Eski 3. yuvanın değiştirilmiş tuşu (Alt+F2) da onunla 2. sıraya geçer.
        Assert.Equal(new HotkeyKey(HotkeyModifiers.Alt, 113), HotkeyTable.KeyFor(keys, HotkeyAction.ExtraRegion2, 1));
        Assert.Equal(new HotkeyKey(HotkeyModifiers.None, HotkeyTable.NumPad0 + 3), HotkeyTable.KeyFor(keys, HotkeyAction.ExtraRegion2, 0));
        // Boşta kalan 3. sıra, kullanılmayan eski 1. yuvanın tuşlarını alır: hiçbir tuş kaybolmaz ya da iki işe gitmez.
        Assert.Equal(new HotkeyKey(HotkeyModifiers.None, HotkeyTable.NumPad0 + 1), HotkeyTable.KeyFor(keys, HotkeyAction.ExtraRegion3, 0));
        var bound = HotkeyTable.Resolve(keys);
        Assert.Equal(HotkeyTable.Bindings.Count, bound.Count);
        Assert.Equal(bound.Count, bound.Select(b => (b.Modifiers, b.VirtualKey)).Distinct().Count());
    }

    [Fact]
    public void SettingsWithoutLegacySlotsAreUnchanged()
    {
        var saved = new UserSettings().WithArea(Quest, live: true) with { FreeAreaTarget = ResultTarget.Both };
        var json = JsonSerializer.Serialize(saved);
        var loaded = ExtraAreaMigration.Load(json);
        Assert.Equal(saved.ExtraAreas, loaded.ExtraAreas);
        Assert.Equal(saved.Hotkeys, loaded.Hotkeys);
        Assert.Equal(ResultTarget.Both, loaded.FreeAreaTarget);
    }

    /// <summary>Dönüşen dosya yeni biçimde yazılır; eski alanlar dosyadan kalkar ve ikinci açılış aynı sonucu verir.</summary>
    [Fact]
    public void MigratedSettingsAreWrittenInTheNewFormatAndRoundTrip()
    {
        var first = ExtraAreaMigration.Load(Legacy());
        var json = JsonSerializer.Serialize(first);
        Assert.DoesNotContain("\"ExtraRegion2\":", json);
        Assert.DoesNotContain("ExtraLive", json);
        Assert.DoesNotContain("ExtraTarget", json);
        var second = ExtraAreaMigration.Load(json);
        Assert.Equal(first.ExtraAreas, second.ExtraAreas);
        Assert.Equal(first.Hotkeys, second.Hotkeys);
    }

    /// <summary>Oyun profillerinin ve kenara alınmış genel alanların yuvaları da dönüşür.</summary>
    [Fact]
    public void ProfilesAndGeneralAreasAreConvertedToo()
    {
        const string areas = """
            { "Region": { "Top": 0.6, "Bottom": 0.9, "Left": 0.1, "Right": 0.9 }, "AreaPreset": 3,
              "ExtraRegion1": { "Top": 0.03, "Bottom": 0.30, "Left": 0.66, "Right": 0.98 },
              "ExtraRegion2": null, "ExtraRegion3": null,
              "ExtraTarget1": 0, "ExtraTarget2": 0, "ExtraTarget3": 0,
              "ExtraLive1": true, "ExtraLive2": false, "ExtraLive3": false }
            """;
        var settings = ExtraAreaMigration.Load(Legacy($$""", "GeneralAreas": {{areas}}, "AreaProfiles": [ { "Key": "far cry 3|stream", "Game": "Far Cry 3", "Areas": {{areas}} } ]"""));
        var profile = Assert.Single(settings.AreaProfiles);
        Assert.Equal(new ExtraArea("area1", "", Quest, true, ResultTarget.Tv), Assert.Single(profile.Areas.ExtraAreas));
        Assert.Equal(new ExtraArea("area1", "", Quest, true, ResultTarget.Tv), Assert.Single(settings.GeneralAreas!.ExtraAreas));
        // Genel alanlar 1. yuvadaydı: kısayollar onların sırasına göre taşınır (yer değiştirme yok).
        Assert.Equal(new HotkeyKey(HotkeyModifiers.None, HotkeyTable.NumPad0 + 1), HotkeyTable.KeyFor(settings.Hotkeys, HotkeyAction.ExtraRegion1, 0));
    }

    /// <summary>Profilin alanları, kaydedildiği andakiyle aynıysa (liste başvurusu değil, içerik) "kaydedilmemiş değişiklik" sayılmaz.</summary>
    [Fact]
    public void AreaSetsWithTheSameAreasAreEqual()
    {
        var area = new ExtraArea("area1", "Görev", Quest);
        Assert.Equal(new AreaSet(new CropRegion(), AreaPreset.Bottom, [area]), new AreaSet(new CropRegion(), AreaPreset.Bottom, [area with { }]));
        Assert.NotEqual(new AreaSet(new CropRegion(), AreaPreset.Bottom, [area]), new AreaSet(new CropRegion(), AreaPreset.Bottom, [area with { Enabled = false }]));
    }
}
