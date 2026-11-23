// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json.Serialization;

namespace CouchSubs.Core;

/// <summary>Altyazı bölgesinin hazır seçimleri (Ayarlar › Altyazı alanı). Mac'teki CouchSubsCore/Pipeline/AreaPreset.swift ile aynı.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<AreaPreset>))]
public enum AreaPreset
{
    /// <summary>Ekranın altı: oyunların çoğu altyazıyı orada gösterir (varsayılan bölge).</summary>
    Bottom,
    /// <summary>Ekranın üstü.</summary>
    Top,
    /// <summary>Bütün kare.</summary>
    Full,
    /// <summary>Kullanıcının ayarladığı bölge.</summary>
    Custom,
}

public static class AreaPresets
{
    /// <summary>Bölgenin en küçük yüksekliği (kenara oranla).</summary>
    public const double MinimumSize = 0.05;

    /// <summary>Hazır seçimin bölgesi; <see cref="AreaPreset.Custom"/> için null (kayıtlı bölge kullanılır).</summary>
    public static CropRegion? Region(this AreaPreset preset) => preset switch
    {
        AreaPreset.Bottom => new CropRegion(),
        AreaPreset.Top => new CropRegion(0.03, 0.38, 0.14, 0.86),
        AreaPreset.Full => new CropRegion(0, 1, 0, 1),
        _ => null,
    };

    /// <summary>Bölge bir hazır seçimle aynıysa o, değilse Custom (eski kayıtlarda seçim yoktur; bölgeden çıkarılır).</summary>
    public static AreaPreset Matching(CropRegion region) =>
        Enum.GetValues<AreaPreset>().FirstOrDefault(preset => preset.Region() is { } known && known.IsClose(region), AreaPreset.Custom);

    /// <summary>İki bölge yuvarlama payı içinde aynı mı (kaydırıcılar ve kayıt küçük farklar bırakabilir).</summary>
    public static bool IsClose(this CropRegion region, CropRegion other, double tolerance = 0.001) =>
        Math.Abs(region.Top - other.Top) <= tolerance && Math.Abs(region.Bottom - other.Bottom) <= tolerance
        && Math.Abs(region.Left - other.Left) <= tolerance && Math.Abs(region.Right - other.Right) <= tolerance;

    /// <summary>Bölgenin üst kenarı ve yüksekliği, yüzde olarak (Özel bölgenin "Dikey konum" ve "Yükseklik" kaydırıcıları).</summary>
    public static (double Position, double Height) VerticalPercent(this CropRegion region) =>
        (region.Top * 100, (region.Bottom - region.Top) * 100);

    /// <summary>
    /// Üst kenarı <paramref name="positionPercent"/>, yüksekliği <paramref name="heightPercent"/> yüzde olan bölge; sola
    /// ve sağa dokunulmaz. Yükseklik en az %5'tir; bölge karenin dışına taşmaz (gerekirse yukarı kayar).
    /// </summary>
    public static CropRegion WithVertical(this CropRegion region, double positionPercent, double heightPercent)
    {
        var height = Math.Clamp(heightPercent / 100, MinimumSize, 1);
        var top = Math.Clamp(positionPercent / 100, 0, 1 - height);
        return region with { Top = top, Bottom = top + height };
    }
}

/// <summary>
/// Sürekli okunan ek bölgenin hazır seçimleri: oyunların çoğu bu yazıları ekranın köşelerinde gösterir (Mac:
/// ExtraArea.swift'teki ExtraAreaPreset ile aynı bölgeler).
/// </summary>
public enum ExtraAreaPreset
{
    /// <summary>Sağ üstteki görev yazısı.</summary>
    Quest,
    /// <summary>Sol alttaki bildirim.</summary>
    Notification,
    /// <summary>Sağ alttaki telefon mesajı ya da e-posta.</summary>
    Phone,
}

public static class ExtraAreaPresets
{
    public static CropRegion Region(this ExtraAreaPreset preset) => preset switch
    {
        ExtraAreaPreset.Quest => new CropRegion(0.03, 0.30, 0.66, 0.98),
        ExtraAreaPreset.Notification => new CropRegion(0.58, 0.88, 0.02, 0.30),
        _ => new CropRegion(0.50, 0.95, 0.72, 0.98),
    };
}
