// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CouchSubs.Core;

namespace CouchSubs.App.Services;

/// <summary>
/// Deneme karelerini çizer (Mac'teki DemoFrames ile aynı sahne, renk ve ölçüler): düz bir kıyı sahnesi, sol üstte görev
/// yazısı, altta İngilizce altyazı. Kareler gerçek hattan geçer; yazıyı yazı tanıma okur.
/// </summary>
internal static class DemoFrameRenderer
{
    private const double W = DemoFrames.Width;
    private const double H = DemoFrames.Height;

    /// <summary>Gökyüzü, ufuk, deniz ve kara renkleri; satır gruplarıyla değişir.</summary>
    private static readonly (Color Sky, Color Horizon, Color Sea, Color Land)[] Palettes =
    [
        (Rgb(0.16, 0.22, 0.42), Rgb(0.86, 0.55, 0.38), Rgb(0.10, 0.24, 0.36), Rgb(0.12, 0.20, 0.16)),
        (Rgb(0.08, 0.10, 0.22), Rgb(0.36, 0.30, 0.50), Rgb(0.06, 0.14, 0.24), Rgb(0.08, 0.12, 0.12)),
        (Rgb(0.30, 0.46, 0.62), Rgb(0.78, 0.82, 0.80), Rgb(0.16, 0.34, 0.44), Rgb(0.20, 0.30, 0.20)),
    ];

    private static readonly Typeface Bold = new(new FontFamily("Arial"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);

    /// <summary>
    /// <paramref name="line"/>: gösterilen altyazının sırası (null: altyazısız kare). <paramref name="scene"/>: arka planın
    /// tonu. Akışın iş parçacığından çağrılır; çizim arayüz iş parçacığında yapılır. Uygulama kapanıyorsa null.
    /// </summary>
    public static Frame? Render(int? line, int scene)
    {
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted) return null;
        try
        {
            return dispatcher.CheckAccess() ? Draw(line, scene) : dispatcher.Invoke(() => Draw(line, scene));
        }
        catch (Exception error) when (error is OperationCanceledException or InvalidOperationException)
        {
            return null;
        }
    }

    internal static Frame Draw(int? line, int scene)
    {
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            DrawScene(context, scene);
            DrawText(context, DemoScript.Objective.English, size: 24, x: 48, top: 0.08);
            if (line is { } index)
            {
                var count = DemoScript.Lines.Count;
                DrawText(context, DemoScript.Lines[((index % count) + count) % count].English, size: 36, x: null, top: DemoFrames.SubtitleBaseline);
            }
        }
        var bitmap = new RenderTargetBitmap(DemoFrames.Width, DemoFrames.Height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var stride = DemoFrames.Width * 4;
        var pixels = new byte[stride * DemoFrames.Height];
        bitmap.CopyPixels(pixels, stride, 0);
        return new Frame(pixels, DemoFrames.Width, DemoFrames.Height, stride);
    }

    /// <summary>Gökyüzü, deniz, tepe ve deniz feneri (ölçüler Mac'teki çizimle aynı; orada eksen alttan yukarıdır).</summary>
    private static void DrawScene(DrawingContext context, int scene)
    {
        var palette = Palettes[((scene % Palettes.Length) + Palettes.Length) % Palettes.Length];
        var sky = new LinearGradientBrush(palette.Horizon, palette.Sky, new Point(0, H * 0.62), new Point(0, 0)) { MappingMode = BrushMappingMode.Absolute };
        sky.Freeze();
        context.DrawRectangle(sky, null, new Rect(0, 0, W, H));
        // Güneş ya da ay.
        context.DrawEllipse(Fill(Rgb(1, 0.92, 0.75, 0.85)), null, new Point((W * 0.70) + 45, H - (H * 0.52) - 45), 45, 45);
        // Deniz.
        context.DrawRectangle(Fill(palette.Sea), null, new Rect(0, H * 0.60, W, H * 0.40));
        // Dalga çizgileri.
        var wave = new Pen(Fill(Rgb(1, 1, 1, 0.12)), 2);
        wave.Freeze();
        for (var row = 0; row < 6; row++)
        {
            var y = H - ((H * 0.36) - (row * 38));
            var geometry = new StreamGeometry();
            using (var path = geometry.Open())
            {
                path.BeginFigure(new Point(0, y), isFilled: false, isClosed: false);
                for (var step = 0; step <= (int)W; step += 40)
                    path.LineTo(new Point(step, y - (step / 40 % 2 == 0 ? 4 : -4)), isStroked: true, isSmoothJoin: false);
            }
            geometry.Freeze();
            context.DrawGeometry(null, wave, geometry);
        }
        // Kıyıdaki tepe.
        var hill = new StreamGeometry();
        using (var path = hill.Open())
        {
            path.BeginFigure(new Point(0, H * 0.60), isFilled: true, isClosed: true);
            path.BezierTo(new Point(W * 0.06, H * 0.40), new Point(W * 0.30, H * 0.42), new Point(W * 0.42, H * 0.60), isStroked: false, isSmoothJoin: false);
        }
        hill.Freeze();
        context.DrawGeometry(Fill(palette.Land), null, hill);
        // Deniz feneri: gövde, şeritler, ışık odası ve ışık.
        double baseX = W * 0.16, baseY = H * 0.50;
        context.DrawGeometry(Fill(Rgb(0.93, 0.92, 0.88)), null, Polygon(
            new Point(baseX - 26, baseY), new Point(baseX + 26, baseY), new Point(baseX + 16, baseY - 150), new Point(baseX - 16, baseY - 150)));
        var stripe = Fill(Rgb(0.72, 0.20, 0.18));
        context.DrawRectangle(stripe, null, new Rect(baseX - 22, baseY - 40 - 18, 44, 18));
        context.DrawRectangle(stripe, null, new Rect(baseX - 19, baseY - 95 - 16, 38, 16));
        context.DrawRectangle(Fill(Rgb(1, 0.88, 0.45)), null, new Rect(baseX - 14, baseY - 150 - 22, 28, 22));
        context.DrawGeometry(Fill(Rgb(1, 0.88, 0.45, 0.18)), null, Polygon(
            new Point(baseX, baseY - 161), new Point(W * 0.55, baseY - 210), new Point(W * 0.55, baseY - 120)));
    }

    /// <summary>
    /// Yazı, okunaklı olsun diye yarı saydam koyu kutunun üstünde beyaz çizilir (oyunlardaki altyazı gibi).
    /// <paramref name="top"/>: satırın taban çizgisinin üstten oranı. <paramref name="x"/>: sola yaslı yazının başladığı
    /// yer (ortalıysa null).
    /// </summary>
    private static void DrawText(DrawingContext context, string text, double size, double? x, double top)
    {
        var formatted = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Bold, size, Brushes.White, 1.0);
        var originX = x ?? (W - formatted.WidthIncludingTrailingWhitespace) / 2;
        var originY = (H * top) - formatted.Baseline;
        var pad = size * 0.45;
        context.DrawRoundedRectangle(Fill(Rgb(0, 0, 0, 0.62)), null,
            new Rect(originX - pad, originY - (pad * 0.6), formatted.WidthIncludingTrailingWhitespace + (pad * 2), formatted.Height + (pad * 1.2)), 8, 8);
        context.DrawText(formatted, new Point(originX, originY));
    }

    private static StreamGeometry Polygon(params Point[] points)
    {
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            path.BeginFigure(points[0], isFilled: true, isClosed: true);
            foreach (var point in points.Skip(1)) path.LineTo(point, isStroked: false, isSmoothJoin: false);
        }
        geometry.Freeze();
        return geometry;
    }

    private static Color Rgb(double red, double green, double blue, double alpha = 1) =>
        Color.FromArgb((byte)Math.Round(alpha * 255), (byte)Math.Round(red * 255), (byte)Math.Round(green * 255), (byte)Math.Round(blue * 255));

    private static SolidColorBrush Fill(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
