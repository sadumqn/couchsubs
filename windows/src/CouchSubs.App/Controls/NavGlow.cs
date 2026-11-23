// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Media;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Controls;

/// <summary>
/// Ayarlar menü kartının arkasındaki sıcak renk lekeleri (Perde; Mac SettingsNavGlow): amber (%22), şeftali (%14) ve gök
/// mavisi (%10) üç yumuşak radyal leke. DURAĞAN: hareket pencerenin ortam ışığındadır (o da Ayarlar'da durağan), menüdeki
/// kopya animasyon çalıştırmaz (boşta ≤ %2 işlemci). Bulanıklık süzgeci yok; kartın köşe yarıçapına (radius.card) kırpılır.
/// </summary>
public sealed class NavGlow : FrameworkElement
{
    /// <summary>Eski çağrılar için (çeviri sürerken durdurma); lekeler zaten durağan.</summary>
    public static readonly DependencyProperty PausedProperty = DependencyProperty.Register(nameof(Paused), typeof(bool), typeof(NavGlow),
        new FrameworkPropertyMetadata(false));

    /// <summary>Renk adı (tasarim.json), merkez (oransal) ve saydamlık.</summary>
    private static readonly (string Name, double X, double Y, double Alpha)[] Blobs =
        [("amber", 0.2, 0.12, 0.22), ("peach", 0.85, 0.5, 0.14), ("sky", 0.3, 0.92, 0.10)];

    private Brush[] brushes = [];

    public NavGlow()
    {
        IsHitTestVisible = false;
        Focusable = false;
        void OnTheme()
        {
            MakeBrushes();
            InvalidateVisual();
        }
        Loaded += (_, _) =>
        {
            ThemeManager.Changed -= OnTheme;
            ThemeManager.Changed += OnTheme;
            OnTheme();
        };
        Unloaded += (_, _) => ThemeManager.Changed -= OnTheme;
    }

    public bool Paused { get => (bool)GetValue(PausedProperty); set => SetValue(PausedProperty, value); }

    /// <summary>Hiç oynamaz (testler ve tanı için).</summary>
    public bool Running => false;

    private void MakeBrushes()
    {
        brushes = [.. Blobs.Select(blob =>
        {
            var color = TryFindResource(blob.Name + "Color") is Color found ? found : Colors.Transparent;
            var brush = new RadialGradientBrush(Color.FromArgb((byte)Math.Round(blob.Alpha * 255), color.R, color.G, color.B), Color.FromArgb(0, color.R, color.G, color.B));
            brush.Freeze();
            return (Brush)brush;
        })];
    }

    protected override void OnRender(DrawingContext context)
    {
        var size = RenderSize;
        if (size.Width <= 0 || size.Height <= 0 || brushes.Length < Blobs.Length) return;
        var radius = TryFindResource("radius.card") is CornerRadius corner ? corner.TopLeft : 24;
        context.PushClip(new RectangleGeometry(new Rect(size), radius, radius));
        var span = Math.Max(size.Width, size.Height) * 0.55;
        for (var i = 0; i < Blobs.Length; i++)
            context.DrawEllipse(brushes[i], null, new Point(size.Width * Blobs[i].X, size.Height * Blobs[i].Y), span, span);
        context.Pop();
    }
}
