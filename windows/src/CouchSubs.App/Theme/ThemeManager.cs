// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Media;
using CouchSubs.Core;
using CouchSubs.Shell;
using Microsoft.Win32;

namespace CouchSubs.App.Theme;

/// <summary>
/// design/tokens.json'daki değerleri uygulama kaynaklarına çevirir. Renkler ayarlardaki görünümle gelir (varsayılan
/// koyu; "Sistemle aynı" seçiliyse Windows'un uygulama temasını izler); XAML bunları DynamicResource ile kullanır,
/// görünüm değişince anında güncellenir.
/// </summary>
public static class ThemeManager
{
    private static readonly DesignTokens Tokens = DesignTokens.Shared;
    /// <summary>Uygulanan görünüm; null ise henüz uygulanmadı.</summary>
    private static AppAppearance? current;

    /// <summary>Koyu ve açık zorlanır; "Sistemle aynı" null döner (Windows'un teması izlenir).</summary>
    public static bool? ForceDark(AppAppearance appearance) => appearance switch
    {
        AppAppearance.Dark => true,
        AppAppearance.Light => false,
        _ => null,
    };

    /// <summary>Ayarlardaki görünümü uygular; aynı görünüm yeniden uygulanmaz.</summary>
    public static void Use(ResourceDictionary resources, AppAppearance appearance)
    {
        if (current == appearance) return;
        current = appearance;
        Apply(resources, ForceDark(appearance));
    }

    public static void Apply(ResourceDictionary resources, bool? forceDark = null)
    {
        var dark = forceDark ?? IsDarkTheme();
        IsDark = dark;
        foreach (var (name, pair) in Tokens.Color) SetColor(resources, name, pair.For(dark));
        foreach (var (name, font) in Tokens.Font) SetFont(resources, name, font.Size, font.Weight);
        foreach (var (name, value) in Tokens.Space) SetSpace(resources, name, value);
        foreach (var (name, value) in Tokens.Radius) resources[$"radius.{name}"] = new CornerRadius(value);
        foreach (var (name, value) in Tokens.Size) resources[$"size.{name}"] = value;
        // Yeni arayüzün değerleri (Palette) ortak değerlerin üstüne yazılır; eski adlar da yeni renkleri alır.
        foreach (var (name, pair) in Palette.Colors) SetColor(resources, name, dark ? pair.Dark : pair.Light);
        foreach (var (name, font) in Palette.Fonts) SetFont(resources, name, font.Size, font.Weight);
        foreach (var (name, value) in Palette.Space) SetSpace(resources, name, value);
        foreach (var (name, value) in Palette.Radius) resources[$"radius.{name}"] = new CornerRadius(value);
        foreach (var (name, value) in Palette.Size) resources[$"size.{name}"] = value;
        // Kart taban gölgesi yok; kartlar 1 px çerçeveyle ayrılır. Döşeme (tile) zemini hafif degradedir (tasarım: .tile).
        var tile = new LinearGradientBrush((Color)resources["tileTopColor"], (Color)resources["tileBottomColor"], 45);
        tile.Freeze();
        resources["tileBrush"] = tile;
        resources["windowBackgroundBrush"] = resources["backgroundBrush"];
        ApplyPerde(resources, dark);
        Changed?.Invoke();
    }

    /// <summary>
    /// Perde'nin bileşik fırçaları (tasarim.json v2 › elevation, effect): kartın kıl çizgisi + koyu temada üst kenar parlaması
    /// (e1), ana düğmenin amber degradesi (glowPrimary), üst parlama, cam çubuklar (e3: yarı saydam koyu degrade; WPF
    /// arkadaki içeriği bulanıklaştırmaz, bu yüzden cam katmanı biraz daha koyudur).
    /// </summary>
    private static void ApplyPerde(ResourceDictionary resources, bool dark)
    {
        Color Get(string name) => resources[$"{name}Color"] is Color color ? color : Colors.Transparent;
        static Brush Frozen(Brush brush)
        {
            brush.Freeze();
            return brush;
        }
        var border = Get("border");
        var highlight = Get("topHighlight");
        // e1: üst kenarda kıl çizgi + parlama (inset 0 1 0 topHighlight), ortaya doğru normal kıl çizgiye iner.
        var top = Color.FromArgb((byte)Math.Min(255, border.A + highlight.A * 2), Blend(border.R, 255, highlight.A), Blend(border.G, 255, highlight.A), Blend(border.B, 255, highlight.A));
        resources["cardEdgeBrush"] = Frozen(new LinearGradientBrush(new GradientStopCollection { new(top, 0), new(border, 0.5) }, 90));
        var strong = Get("borderStrong");
        var strongTop = Color.FromArgb((byte)Math.Min(255, strong.A + highlight.A * 2), Blend(strong.R, 255, highlight.A), Blend(strong.G, 255, highlight.A), Blend(strong.B, 255, highlight.A));
        resources["raisedEdgeBrush"] = Frozen(new LinearGradientBrush(new GradientStopCollection { new(strongTop, 0), new(strong, 0.5) }, 90));
        // Ana düğme: amberHover → amber (yukarıdan aşağı); üzerine gelince daha açık.
        resources["primaryFillBrush"] = Frozen(new LinearGradientBrush(Get("amberHover"), Get("amber"), 90));
        resources["primaryHoverBrush"] = Frozen(new LinearGradientBrush(Color.FromRgb(0xFF, 0xD5, 0x78), Get("amber"), 90));
        resources["primaryEdgeBrush"] = Frozen(new SolidColorBrush(Color.FromArgb(0x99, Get("amberLine").R, Get("amberLine").G, Get("amberLine").B)));
        resources["primarySheenBrush"] = Frozen(new LinearGradientBrush(new GradientStopCollection { new(Color.FromArgb(0x73, 255, 255, 255), 0), new(Color.FromArgb(0, 255, 255, 255), 0.5) }, 90));
        // İlerleme çubuğunun dolgusu: amber → amberHover (soldan sağa).
        resources["progressFillBrush"] = Frozen(new LinearGradientBrush(Get("amber"), Get("amberHover"), 0));
        // e3 cam: üst ve alt çubuklar (içerik arkalarından kayar). Bulanıklık yerine yarı saydam koyu degrade.
        var glass = Get("glass");
        var bg = Get("background");
        resources["glassBarBrush"] = Frozen(new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromArgb(0xFA, bg.R, bg.G, bg.B), 0), new(Color.FromArgb(0xEB, bg.R, bg.G, bg.B), 0.72), new(Color.FromArgb(0x00, bg.R, bg.G, bg.B), 1),
        }, 90));
        resources["glassBarBottomBrush"] = Frozen(new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromArgb(0x00, bg.R, bg.G, bg.B), 0), new(Color.FromArgb(0xEB, bg.R, bg.G, bg.B), 0.28), new(Color.FromArgb(0xFA, bg.R, bg.G, bg.B), 1),
        }, 90));
        resources["glassFillBrush"] = Frozen(new SolidColorBrush(Color.FromArgb((byte)Math.Min(255, glass.A + 0x30), glass.R, glass.G, glass.B)));
        // Durdur düğmesi: üzerine gelince dolu canlı zemin %8 koyulaşır (Mac: siyah %8 örtü).
        var stop = Get("stopFill");
        resources["stopHoverBrush"] = Frozen(new SolidColorBrush(Color.FromRgb((byte)(stop.R * 0.92), (byte)(stop.G * 0.92), (byte)(stop.B * 0.92))));
        resources["focusGlowColor"] = Get("amber");
        resources["shadowColor"] = dark ? Colors.Black : Color.FromRgb(0x3C, 0x28, 0x0A);
        resources["raisedShadowOpacity"] = dark ? 0.45 : 0.16;
    }

    private static byte Blend(byte from, byte to, byte alpha) => (byte)Math.Round(from + (to - from) * (alpha / 255.0));

    /// <summary>Uygulanan tema koyu mu (kodda çizilen renkler için).</summary>
    public static bool IsDark { get; private set; }

    /// <summary>Tema her uygulandığında (kodda çizilen öğeler yenilensin diye).</summary>
    public static event Action? Changed;

    private static void SetColor(ResourceDictionary resources, string name, string hex) => SetColor(resources, name, ToColor(hex));

    private static void SetColor(ResourceDictionary resources, string name, Color color)
    {
        resources[$"{name}Color"] = color;
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        resources[$"{name}Brush"] = brush;
    }

    private static void SetFont(ResourceDictionary resources, string name, double size, string weight)
    {
        resources[$"{name}FontSize"] = size;
        resources[$"{name}FontWeight"] = weight switch
        {
            "bold" => FontWeights.Bold,
            "semibold" => FontWeights.SemiBold,
            "medium" => FontWeights.Medium,
            _ => FontWeights.Normal,
        };
    }

    private static void SetSpace(ResourceDictionary resources, string name, double value)
    {
        resources[$"space.{name}"] = value;
        resources[$"pad.{name}"] = new Thickness(value);
    }

    /// <summary>"Sistemle aynı" seçiliyken Windows'un teması değişince kaynakları yeniler.</summary>
    public static void Follow(ResourceDictionary resources)
    {
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General)
                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (current is null or AppAppearance.System) Apply(resources);
                });
        };
    }

    public static bool IsDarkTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
    }

    private static Color ToColor(string hex)
    {
        var (r, g, b) = DesignTokens.Rgb(hex) ?? (0, 0, 0);
        return Color.FromRgb((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));
    }
}
