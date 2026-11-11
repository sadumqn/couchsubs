// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using CouchSubs.Core;
using Microsoft.Win32;

namespace CouchSubs.App.Theme;

/// <summary>
/// design/tokens.json'daki değerleri uygulama kaynaklarına çevirir. Renkler Windows'un uygulama
/// temasını (açık/koyu) izler; XAML bunları DynamicResource ile kullanır, tema değişince anında güncellenir.
/// </summary>
public static class ThemeManager
{
    private static readonly DesignTokens Tokens = DesignTokens.Shared;

    public static void Apply(ResourceDictionary resources, bool? forceDark = null)
    {
        var dark = forceDark ?? IsDarkTheme();
        foreach (var (name, pair) in Tokens.Color)
        {
            var color = ToColor(pair.For(dark));
            resources[$"{name}Color"] = color;
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            resources[$"{name}Brush"] = brush;
        }
        foreach (var (name, font) in Tokens.Font)
        {
            resources[$"{name}FontSize"] = font.Size;
            resources[$"{name}FontWeight"] = font.Weight switch
            {
                "bold" => FontWeights.Bold,
                "semibold" => FontWeights.SemiBold,
                "medium" => FontWeights.Medium,
                _ => FontWeights.Normal,
            };
        }
        foreach (var (name, value) in Tokens.Space)
        {
            resources[$"space.{name}"] = value;
            resources[$"pad.{name}"] = new Thickness(value);
        }
        foreach (var (name, value) in Tokens.Radius) resources[$"radius.{name}"] = new CornerRadius(value);
        foreach (var (name, value) in Tokens.Size) resources[$"size.{name}"] = value;
        ApplyGlows(resources, dark);
    }

    /// <summary>
    /// Parıltılar ve degradeler (docs/TASARIM.md › Parıltı): <c>glow.ad</c> dış parıltı efekti, <c>glow.adBrush</c> saydam
    /// renk; birincil düğme, karo, Pro karo ve pencere zemini degradeleri. Tümü dondurulur, böylece paylaşılabilir.
    /// </summary>
    private static void ApplyGlows(ResourceDictionary resources, bool dark)
    {
        foreach (var (name, glow) in Tokens.Glow)
        {
            var color = ToColor(glow.Color);
            var effect = new DropShadowEffect
            {
                Color = color, Opacity = glow.Opacity, BlurRadius = glow.Radius,
                ShadowDepth = glow.Y, Direction = 270, RenderingBias = RenderingBias.Quality,
            };
            effect.Freeze();
            resources[$"glow.{name}"] = effect;
            resources[$"glow.{name}Brush"] = Frozen(new SolidColorBrush(WithAlpha(color, glow.Opacity)));
        }
        Color Pick(string name) => ToColor(Tokens.Color[name].For(dark));
        var surface = Pick("surface");
        var white = Colors.White;

        // Birincil düğme: üstten hafif açık sarı.
        resources["primaryFillBrush"] = Frozen(Vertical((Pick("accentHi"), 0), (Pick("accent"), 1)));
        // Karo: yüzeyin üstüne yukarıdan %4 beyaz.
        resources["tileFillBrush"] = Frozen(Vertical((Blend(surface, white, 0.04), 0), (surface, 0.6)));
        // Pro karo: üstte %10 mor, mor→sarı çerçeve.
        resources["proFillBrush"] = Frozen(Vertical((Blend(surface, Pick("pro"), 0.10), 0), (surface, 0.7)));
        resources["proBorderBrush"] = Frozen(new LinearGradientBrush(Pick("pro"), Pick("accent"), new Point(0, 0), new Point(1, 1)));

        // Pencere zemini: sağ üstte sarı, sol altta mor yumuşak ışık (hareketsiz).
        var area = new RectangleGeometry(new Rect(0, 0, 1, 1));
        var drawing = new DrawingGroup();
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(Pick("background")), null, area));
        drawing.Children.Add(new GeometryDrawing(Light(Tokens.Glow["backgroundAccent"], new Point(0.88, -0.06)), null, area));
        drawing.Children.Add(new GeometryDrawing(Light(Tokens.Glow["backgroundPro"], new Point(-0.12, 1.06)), null, area));
        resources["windowBackgroundBrush"] = Frozen(new DrawingBrush(drawing) { Stretch = Stretch.Fill });
    }

    /// <summary>Pencere zemini ışığı: yarıçap 1040 × 720'lik pencereye göre oranlanır, %62'de söner.</summary>
    private static RadialGradientBrush Light(DesignTokens.GlowToken glow, Point center)
    {
        var color = ToColor(glow.Color);
        var brush = new RadialGradientBrush(
            [new GradientStop(WithAlpha(color, glow.Opacity), 0), new GradientStop(WithAlpha(color, 0), 0.62)])
        {
            Center = center, GradientOrigin = center,
            RadiusX = glow.Radius / Tokens.Size["windowWidth"],
            RadiusY = glow.Radius * 0.76 / Tokens.Size["windowHeight"],
        };
        return brush;
    }

    private static LinearGradientBrush Vertical(params (Color Color, double Offset)[] stops) =>
        new([.. stops.Select(stop => new GradientStop(stop.Color, stop.Offset))], new Point(0, 0), new Point(0, 1));

    private static T Frozen<T>(T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }

    private static Color WithAlpha(Color color, double opacity) =>
        Color.FromArgb((byte)Math.Round(Math.Clamp(opacity, 0, 1) * 255), color.R, color.G, color.B);

    private static Color Blend(Color under, Color over, double amount)
    {
        byte Mix(byte a, byte b) => (byte)Math.Round(a + ((b - a) * amount));
        return Color.FromRgb(Mix(under.R, over.R), Mix(under.G, over.G), Mix(under.B, over.B));
    }

    /// <summary>Tema değişince kaynakları yeniler.</summary>
    public static void Follow(ResourceDictionary resources)
    {
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General)
                Application.Current.Dispatcher.Invoke(() => Apply(resources));
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
