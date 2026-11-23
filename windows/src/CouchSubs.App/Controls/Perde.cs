// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Controls;

// Perde tasarım dilinin Windows bileşenleri (Mac Perde.swift ile aynı adlar ve ölçüler; tasarim.json v2 › effect, motion).
// Sürekli animasyonların hepsi hareket kapısına (Theme.MotionGate) bağlıdır: çeviri sürerken yalnız canlı nabız atar;
// hareket azaltılmışken ya da pencere arka plandayken hepsi durağandır. Bir efektin hatası uygulamayı düşürmez.

/// <summary>Perde renklerine kod içinden erişim (tema değişince yeniden okunur).</summary>
internal static class PerdeColors
{
    public static Color Get(string name, Color fallback) =>
        Application.Current?.TryFindResource($"{name}Color") is Color color ? color : fallback;

    public static Color WithAlpha(Color color, double alpha) => Color.FromArgb((byte)Math.Clamp(Math.Round(alpha * 255), 0, 255), color.R, color.G, color.B);

    public static Color Rgb(int r, int g, int b) => Color.FromRgb((byte)r, (byte)g, (byte)b);

    public static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

/// <summary>Perde ışımaları (DropShadowEffect; GPU'da çizilir, durağan).</summary>
public static class PerdeEffects
{
    /// <summary>Amber ışıma (effect.glowPrimary / amberGlow): verilen bulanıklıkta, kaymasız.</summary>
    public static DropShadowEffect AmberGlow(double blur, double depth = 0, double opacity = 0.45)
    {
        var effect = new DropShadowEffect { BlurRadius = blur, ShadowDepth = depth, Direction = 270, Opacity = opacity,
            Color = PerdeColors.Rgb(0xF5, 0xB8, 0x3D), RenderingBias = RenderingBias.Performance };
        effect.Freeze();
        return effect;
    }
}

// ───────────── Canlı nokta ─────────────

/// <summary>
/// Canlı/çalışıyor noktası (DSPulseDot): dolu nokta + 1,6 sn'de bir dışa yayılıp sönen halka. Çeviri sürerken de atar;
/// hareket azaltılmışken ya da pencere arka plandayken sabit nokta.
/// </summary>
public sealed class PulseDot : Grid
{
    public static readonly DependencyProperty FillProperty = DependencyProperty.Register(nameof(Fill), typeof(Brush), typeof(PulseDot),
        new FrameworkPropertyMetadata(null, (d, _) => ((PulseDot)d).ApplyFill()));
    public static readonly DependencyProperty DiameterProperty = DependencyProperty.Register(nameof(Diameter), typeof(double), typeof(PulseDot),
        new FrameworkPropertyMetadata(8.0, (d, _) => ((PulseDot)d).ApplySize()));

    private readonly Ellipse ring = new() { Opacity = 0, IsHitTestVisible = false };
    private readonly Ellipse dot = new() { IsHitTestVisible = false };
    private readonly ScaleTransform grow = new(1, 1);

    public PulseDot()
    {
        ring.RenderTransformOrigin = new Point(0.5, 0.5);
        ring.RenderTransform = grow;
        Children.Add(ring);
        Children.Add(dot);
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Center;
        ApplySize();
        ApplyFill();
        Motion.Gated(this, () => MotionGate.Live, Start, Stop);
    }

    public Brush? Fill { get => (Brush?)GetValue(FillProperty); set => SetValue(FillProperty, value); }
    public double Diameter { get => (double)GetValue(DiameterProperty); set => SetValue(DiameterProperty, value); }

    private void ApplySize()
    {
        Width = Height = Diameter;
        ring.Width = ring.Height = dot.Width = dot.Height = Diameter;
    }

    private void ApplyFill()
    {
        if (Fill is { } fill)
        {
            ring.Fill = dot.Fill = fill;
            return;
        }
        ring.SetResourceReference(Shape.FillProperty, "liveDotBrush");
        dot.SetResourceReference(Shape.FillProperty, "liveDotBrush");
    }

    private void Start()
    {
        var period = TimeSpan.FromMilliseconds(Palette.MotionMs("livePulse", 1600));
        var spread = (Diameter + 2 * 6) / Diameter;
        var active = TimeSpan.FromMilliseconds(period.TotalMilliseconds * 0.7);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        var scale = new DoubleAnimationUsingKeyFrames { Duration = period, RepeatBehavior = RepeatBehavior.Forever };
        scale.KeyFrames.Add(new DiscreteDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.Zero)));
        scale.KeyFrames.Add(new EasingDoubleKeyFrame(spread, KeyTime.FromTimeSpan(active), ease));
        var fade = new DoubleAnimationUsingKeyFrames { Duration = period, RepeatBehavior = RepeatBehavior.Forever };
        fade.KeyFrames.Add(new DiscreteDoubleKeyFrame(0.55, KeyTime.FromTimeSpan(TimeSpan.Zero)));
        fade.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(active), ease));
        Motion.Fps(scale, 30);
        Motion.Fps(fade, 30);
        grow.BeginAnimation(ScaleTransform.ScaleXProperty, scale);
        grow.BeginAnimation(ScaleTransform.ScaleYProperty, scale);
        ring.BeginAnimation(OpacityProperty, fade);
    }

    private void Stop()
    {
        grow.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        grow.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        ring.BeginAnimation(OpacityProperty, null);
        ring.Opacity = 0;
    }
}

// ───────────── Durum hapı ─────────────

/// <summary>Durum hapının tonu (DSStatusChip.Tone).</summary>
public enum ChipTone { Muted, Ok, Live, Amber, Info, Glass, GlassLive }

/// <summary>
/// Durum hapı (DSStatusChip): 26 yüksek, tam yuvarlak; renk + nokta/simge + yazı birlikte (durum rengi tek başına anlam
/// taşımaz). Canlı tonunda nokta nabız atar; cam tonu perde üstünde kullanılır.
/// </summary>
public sealed class Chip : Border
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(nameof(Text), typeof(string), typeof(Chip),
        new FrameworkPropertyMetadata(null, (d, _) => ((Chip)d).Build()));
    public static readonly DependencyProperty ToneProperty = DependencyProperty.Register(nameof(Tone), typeof(ChipTone), typeof(Chip),
        new FrameworkPropertyMetadata(ChipTone.Muted, (d, _) => ((Chip)d).Build()));
    public static readonly DependencyProperty ShowDotProperty = DependencyProperty.Register(nameof(ShowDot), typeof(bool), typeof(Chip),
        new FrameworkPropertyMetadata(true, (d, _) => ((Chip)d).Build()));
    /// <summary>Noktanın yerine Segoe Fluent Icons simgesi (ör. tik).</summary>
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(nameof(Glyph), typeof(string), typeof(Chip),
        new FrameworkPropertyMetadata(null, (d, _) => ((Chip)d).Build()));

    public Chip()
    {
        Height = 26;
        CornerRadius = new CornerRadius(13);
        Padding = new Thickness(10, 0, 10, 0);
        HorizontalAlignment = HorizontalAlignment.Left;
        VerticalAlignment = VerticalAlignment.Center;
        SnapsToDevicePixels = true;
        Build();
    }

    public string? Text { get => (string?)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public ChipTone Tone { get => (ChipTone)GetValue(ToneProperty); set => SetValue(ToneProperty, value); }
    public bool ShowDot { get => (bool)GetValue(ShowDotProperty); set => SetValue(ShowDotProperty, value); }
    public string? Glyph { get => (string?)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }

    private void Build()
    {
        var (fore, back) = Tone switch
        {
            ChipTone.Ok => ("successTextBrush", "successSoftBrush"),
            ChipTone.Live => ("liveTextBrush", "liveSoftBrush"),
            ChipTone.Amber => ("amberTextBrush", "amberSoftBrush"),
            ChipTone.Info => ("infoTextBrush", "infoSoftBrush"),
            ChipTone.Glass or ChipTone.GlassLive => ("", ""),
            _ => ("mutedBrush", "fieldBrush"),
        };
        var glass = Tone is ChipTone.Glass or ChipTone.GlassLive;
        if (glass)
        {
            Background = PerdeColors.Frozen(Color.FromArgb(0x8C, 0x0B, 0x0B, 0x0D));
            BorderBrush = PerdeColors.Frozen(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
            BorderThickness = new Thickness(1);
        }
        else
        {
            SetResourceReference(BackgroundProperty, back);
            BorderThickness = new Thickness(0);
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var text = new TextBlock { Text = Text, FontSize = 12, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.NoWrap };
        if (glass) text.Foreground = PerdeColors.Frozen(PerdeColors.Rgb(0xF3, 0xEE, 0xE4));
        else text.SetResourceReference(TextBlock.ForegroundProperty, fore);
        if (Glyph is { Length: > 0 } glyph)
        {
            var icon = new TextBlock { Text = glyph, FontSize = 10, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center, Margin = Sp.T("0", "0", "unitHint", "0") };
            icon.SetResourceReference(TextBlock.FontFamilyProperty, "IconFont");
            icon.Foreground = text.Foreground;
            if (!glass) icon.SetResourceReference(TextBlock.ForegroundProperty, fore);
            row.Children.Add(icon);
        }
        else if (ShowDot)
        {
            FrameworkElement dot;
            if (Tone is ChipTone.Live or ChipTone.GlassLive) dot = new PulseDot { Diameter = 7 };
            else
            {
                var circle = new Ellipse { Width = 7, Height = 7 };
                if (glass) circle.Fill = PerdeColors.Frozen(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));
                else circle.SetResourceReference(Shape.FillProperty, fore);
                dot = circle;
            }
            dot.Margin = Sp.T("0", "0", "unitHint", "0");
            dot.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(dot);
        }
        row.Children.Add(text);
        Child = row;
        AutomationProperties.SetName(this, Text ?? "");
    }
}

/// <summary>Sayı rozeti (DSCountBadge; ör. Oyun Paketleri 6): amber dolu ya da nötr.</summary>
public sealed class CountBadge : Border
{
    private readonly TextBlock text = new() { FontSize = 12, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

    public CountBadge(int count, bool neutral = false)
    {
        MinWidth = 22;
        Height = 22;
        CornerRadius = new CornerRadius(11);
        Padding = new Thickness(7, 0, 7, 0);
        text.Text = count.ToString(System.Globalization.CultureInfo.CurrentCulture);
        text.SetResourceReference(TextBlock.ForegroundProperty, neutral ? "mutedBrush" : "onAmberBrush");
        SetResourceReference(BackgroundProperty, neutral ? "fieldBrush" : "amberBrush");
        Child = text;
        VerticalAlignment = VerticalAlignment.Center;
    }
}

// ───────────── Simge karesi ─────────────

/// <summary>Simge karesinin tonu (tasarim.json: peach, olive, teal, plum, sky; ana eylem amber, nötr gri).</summary>
public enum IconTone { Gray, Peach, Olive, Teal, Plum, Sky, Amber }

/// <summary>
/// Renkli simge karesi (DSIconSquare): degrade tonlu yuvarlak kare (köşe boyun %30'u), beyaz simge (amberde koyu).
/// </summary>
public sealed class IconSquare : Border
{
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(nameof(Glyph), typeof(string), typeof(IconSquare),
        new FrameworkPropertyMetadata(null, (d, _) => ((IconSquare)d).Build()));
    public static readonly DependencyProperty ToneProperty = DependencyProperty.Register(nameof(Tone), typeof(IconTone), typeof(IconSquare),
        new FrameworkPropertyMetadata(IconTone.Gray, (d, _) => ((IconSquare)d).Build()));
    public static readonly DependencyProperty SizeProperty = DependencyProperty.Register(nameof(Size), typeof(double), typeof(IconSquare),
        new FrameworkPropertyMetadata(32.0, (d, _) => ((IconSquare)d).Build()));

    private readonly TextBlock glyph = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

    public IconSquare()
    {
        glyph.SetResourceReference(TextBlock.FontFamilyProperty, "IconFont");
        Child = glyph;
        VerticalAlignment = VerticalAlignment.Center;
        Build();
    }

    public string? Glyph { get => (string?)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }
    public IconTone Tone { get => (IconTone)GetValue(ToneProperty); set => SetValue(ToneProperty, value); }
    public double Size { get => (double)GetValue(SizeProperty); set => SetValue(SizeProperty, value); }

    public static (Color Top, Color Bottom) Colors(IconTone tone) => tone switch
    {
        IconTone.Peach => (PerdeColors.Rgb(244, 162, 122), PerdeColors.Rgb(224, 123, 74)),
        IconTone.Olive => (PerdeColors.Rgb(180, 190, 106), PerdeColors.Rgb(142, 154, 69)),
        IconTone.Teal => (PerdeColors.Rgb(92, 194, 183), PerdeColors.Rgb(58, 158, 148)),
        IconTone.Plum => (PerdeColors.Rgb(184, 146, 220), PerdeColors.Rgb(156, 108, 196)),
        IconTone.Sky => (PerdeColors.Rgb(120, 174, 226), PerdeColors.Rgb(79, 143, 203)),
        IconTone.Amber => (PerdeColors.Rgb(255, 203, 99), PerdeColors.Rgb(233, 165, 42)),
        _ => (PerdeColors.Rgb(138, 141, 150), PerdeColors.Rgb(90, 93, 102)),
    };

    private void Build()
    {
        Width = Height = Size;
        CornerRadius = new CornerRadius(Size * 0.3);
        var (top, bottom) = Colors(Tone);
        var fill = new LinearGradientBrush(top, bottom, new Point(0, 0), new Point(1, 1));
        fill.Freeze();
        Background = fill;
        glyph.Text = Glyph ?? "";
        glyph.FontSize = Math.Round(Size * 0.46);
        glyph.Foreground = Tone == IconTone.Amber ? PerdeColors.Frozen(PerdeColors.Rgb(0x1D, 0x1E, 0x22)) : Brushes.White;
    }
}

// ───────────── Yükleyiciler ─────────────

/// <summary>
/// Çubuk yükleyici (DSBarsLoader): logodaki iki amber altyazı çubuğu sırayla daralıp genişler (1,2 sn). Kapı kapalıyken
/// durağan. "…ıyor…" yazan düğmelerde ve kısa beklemelerde.
/// </summary>
public sealed class BarsLoader : Canvas
{
    public static readonly DependencyProperty BarBrushProperty = DependencyProperty.Register(nameof(BarBrush), typeof(Brush), typeof(BarsLoader),
        new FrameworkPropertyMetadata(null, (d, _) => ((BarsLoader)d).ApplyBrush()));

    private readonly Rectangle top = new() { Width = 18, Height = 4, RadiusX = 2, RadiusY = 2 };
    private readonly Rectangle bottom = new() { Width = 12, Height = 4, RadiusX = 2, RadiusY = 2 };
    private readonly ScaleTransform topScale = new(1, 1);
    private readonly ScaleTransform bottomScale = new(1, 1);

    public BarsLoader()
    {
        Width = 18;
        Height = 11;
        top.RenderTransformOrigin = bottom.RenderTransformOrigin = new Point(0.5, 0.5);
        top.RenderTransform = topScale;
        bottom.RenderTransform = bottomScale;
        SetLeft(top, 0);
        SetTop(top, 0);
        SetLeft(bottom, 3);
        SetTop(bottom, 7);
        Children.Add(top);
        Children.Add(bottom);
        VerticalAlignment = VerticalAlignment.Center;
        ApplyBrush();
        Motion.Gated(this, () => MotionGate.Ambient, Start, Stop);
    }

    public Brush? BarBrush { get => (Brush?)GetValue(BarBrushProperty); set => SetValue(BarBrushProperty, value); }

    private void ApplyBrush()
    {
        if (BarBrush is { } brush) top.Fill = bottom.Fill = brush;
        else
        {
            top.SetResourceReference(Shape.FillProperty, "amberBrush");
            bottom.SetResourceReference(Shape.FillProperty, "amberBrush");
        }
    }

    private void Start()
    {
        var period = Palette.MotionMs("barsLoader", 1200) / 1000;
        DoubleAnimation Squeeze(double offset) => Motion.Fps(new DoubleAnimation(1, 0.45, TimeSpan.FromSeconds(period / 2))
        {
            AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.InOut, BeginTime = TimeSpan.FromSeconds(offset),
        }, 30);
        topScale.BeginAnimation(ScaleTransform.ScaleXProperty, Squeeze(0));
        bottomScale.BeginAnimation(ScaleTransform.ScaleXProperty, Squeeze(0.18));
    }

    private void Stop()
    {
        topScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        bottomScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
    }
}

/// <summary>
/// Arama halkası dalgası (DSSearchRings): ortadaki ışımalı amber noktadan üç halka 0,8 sn arayla dışa yayılır (2,4 sn).
/// Kapı kapalıyken tek durağan halka.
/// </summary>
public sealed class SearchRings : Grid
{
    public static readonly DependencyProperty SizeProperty = DependencyProperty.Register(nameof(Size), typeof(double), typeof(SearchRings),
        new FrameworkPropertyMetadata(56.0, (d, _) => ((SearchRings)d).ApplySize()));

    private readonly Ellipse[] rings = [new(), new(), new()];
    private readonly ScaleTransform[] scales = [new(0.82, 0.82), new(0.82, 0.82), new(0.82, 0.82)];
    private readonly Ellipse center = new();

    public SearchRings()
    {
        for (var i = 0; i < rings.Length; i++)
        {
            rings[i].StrokeThickness = 2;
            rings[i].SetResourceReference(Shape.StrokeProperty, "amberBrush");
            rings[i].RenderTransformOrigin = new Point(0.5, 0.5);
            rings[i].RenderTransform = scales[i];
            rings[i].Opacity = i == 0 ? 0.5 : 0;
            Children.Add(rings[i]);
        }
        center.SetResourceReference(Shape.FillProperty, "amberBrush");
        center.Effect = PerdeEffects.AmberGlow(16);
        center.HorizontalAlignment = HorizontalAlignment.Center;
        center.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(center);
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
        ApplySize();
        Motion.Gated(this, () => MotionGate.Ambient, Start, Stop);
    }

    public double Size { get => (double)GetValue(SizeProperty); set => SetValue(SizeProperty, value); }

    private void ApplySize()
    {
        Width = Height = Size;
        center.Width = center.Height = Math.Max(8, Size - 36);
    }

    private void Start()
    {
        var period = TimeSpan.FromMilliseconds(Palette.MotionMs("searchRings", 2400));
        var stagger = 0.8;
        for (var i = 0; i < rings.Length; i++)
        {
            var begin = TimeSpan.FromSeconds(-i * stagger + 0); // eksi başlangıç: üç halka hemen yayılmış görünür
            var grow = Motion.Fps(new DoubleAnimation(0.3, 1.25, period) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.Enter, BeginTime = begin }, 30);
            var fade = Motion.Fps(new DoubleAnimation(0.9, 0, period) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.Enter, BeginTime = begin }, 30);
            scales[i].BeginAnimation(ScaleTransform.ScaleXProperty, grow);
            scales[i].BeginAnimation(ScaleTransform.ScaleYProperty, grow);
            rings[i].BeginAnimation(OpacityProperty, fade);
        }
    }

    private void Stop()
    {
        for (var i = 0; i < rings.Length; i++)
        {
            scales[i].BeginAnimation(ScaleTransform.ScaleXProperty, null);
            scales[i].BeginAnimation(ScaleTransform.ScaleYProperty, null);
            rings[i].BeginAnimation(OpacityProperty, null);
            scales[i].ScaleX = scales[i].ScaleY = 0.82;
            rings[i].Opacity = i == 0 ? 0.5 : 0;
        }
    }
}

// ───────────── Adım çizelgesi ─────────────

/// <summary>Adım çizelgesindeki durum: bitti (amber + tik), şimdiki (amber halka + ışıma), sıradaki (soluk).</summary>
public enum StepPhase { Done, Current, Todo }

/// <summary>Adım çizelgesinin bir satırı.</summary>
public sealed record TimelineStep(string Title, string? Detail, StepPhase State);

/// <summary>
/// Adım çizelgesi (DSStepTimeline): biten adım amber dolu + tik (çizgisi amber), şimdiki adım yükseltilmiş + amber halka ve
/// ışıma, sıradaki soluk. Tıklanmaz; seçenek gibi görünmez. Adımlar <see cref="Steps"/> ile verilir.
/// </summary>
public sealed class StepTimeline : StackPanel
{
    private IReadOnlyList<TimelineStep> steps = [];

    public IReadOnlyList<TimelineStep> Steps
    {
        get => steps;
        set
        {
            steps = value;
            Build();
        }
    }

    public static StepPhase Phase(bool done, bool current) => done ? StepPhase.Done : current ? StepPhase.Current : StepPhase.Todo;

    private void Build()
    {
        Children.Clear();
        for (var index = 0; index < steps.Count; index++)
        {
            var step = steps[index];
            var last = index == steps.Count - 1;
            var row = new Grid { Margin = last ? new Thickness(0) : Sp.T("0", "0", "0", "m") };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            if (!last)
            {
                // Sonraki adıma inen 2 px çizgi: biten adımda amber, değilse güçlü kıl çizgi.
                var line = new Rectangle { Width = 2, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(11, 26, 0, -Sp.V("m") + 2) };
                line.SetResourceReference(Shape.FillProperty, step.State == StepPhase.Done ? "amberBrush" : "borderStrongBrush");
                row.Children.Add(line);
            }
            row.Children.Add(Dot(step.State, index + 1));
            var texts = new StackPanel { Margin = Sp.T("s", "line", "0", "0") };
            Grid.SetColumn(texts, 1);
            var title = new TextBlock { Text = step.Title, TextWrapping = TextWrapping.Wrap };
            title.SetResourceReference(TextBlock.FontSizeProperty, "bodyFontSize");
            title.FontWeight = step.State == StepPhase.Current ? FontWeights.Medium : FontWeights.Normal;
            title.SetResourceReference(TextBlock.ForegroundProperty, step.State == StepPhase.Todo ? "mutedBrush" : "textBrush");
            texts.Children.Add(title);
            if (!string.IsNullOrEmpty(step.Detail))
            {
                var detail = new TextBlock { Text = step.Detail, Margin = Sp.T("0", "line", "0", "0") };
                detail.SetResourceReference(StyleProperty, "HintText");
                texts.Children.Add(detail);
            }
            row.Children.Add(texts);
            AutomationProperties.SetName(row, step.Title);
            Children.Add(row);
        }
    }

    private static FrameworkElement Dot(StepPhase state, int number)
    {
        var grid = new Grid { Width = 24, Height = 24, VerticalAlignment = VerticalAlignment.Top };
        var circle = new Ellipse();
        switch (state)
        {
            case StepPhase.Done:
                var halo = new Ellipse { Margin = new Thickness(-4), StrokeThickness = 4 };
                halo.SetResourceReference(Shape.StrokeProperty, "amberSoftBrush");
                grid.Children.Add(halo);
                circle.SetResourceReference(Shape.FillProperty, "amberBrush");
                grid.Children.Add(circle);
                grid.Children.Add(Check(11, "onAmberBrush"));
                break;
            case StepPhase.Current:
                circle.SetResourceReference(Shape.FillProperty, "surfaceRaisedBrush");
                circle.SetResourceReference(Shape.StrokeProperty, "amberBrush");
                circle.StrokeThickness = 2;
                circle.Effect = PerdeEffects.AmberGlow(14);
                grid.Children.Add(circle);
                grid.Children.Add(Number(number, "amberTextBrush"));
                break;
            default:
                circle.SetResourceReference(Shape.FillProperty, "fieldBrush");
                grid.Children.Add(circle);
                grid.Children.Add(Number(number, "mutedBrush"));
                break;
        }
        return grid;
    }

    private static TextBlock Number(int number, string brush)
    {
        var text = new TextBlock { Text = number.ToString(System.Globalization.CultureInfo.InvariantCulture), FontSize = 12, FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        text.SetResourceReference(TextBlock.ForegroundProperty, brush);
        return text;
    }

    /// <summary>Tik işareti (yuvarlak uçlu yol).</summary>
    internal static Path Check(double size, string brush, double thickness = 2.6)
    {
        var path = new Path
        {
            Data = Geometry.Parse("M6,12.5 L10,16.5 L18,8"), StrokeThickness = thickness, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round, Width = size, Height = size, Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        path.SetResourceReference(Shape.StrokeProperty, brush);
        return path;
    }
}

// ───────────── Başarı anı ─────────────

/// <summary>
/// Başarı anı (DSCelebration): arkada amber ışınlar bir kez döner ve söner, ortadaki amber yuvarlakta tik yayla oturur. Hepsi
/// en çok 1 sn. Hareket kapısı kapalıyken (çeviri sürüyor, hareket azaltılmış) yalnız tik.
/// </summary>
public sealed class Celebration : Grid
{
    private readonly double size;
    private bool played;

    public Celebration(double size = 64)
    {
        this.size = size;
        Width = Height = size * 1.6;
        HorizontalAlignment = HorizontalAlignment.Center;
        Loaded += (_, _) => Play();
    }

    private void Play()
    {
        if (played) return;
        played = true;
        try
        {
            Children.Clear();
            var amber = PerdeColors.Get("amber", PerdeColors.Rgb(0xF5, 0xB8, 0x3D));
            if (MotionGate.Ambient) Children.Add(Rays(amber));
            var halo = new Ellipse { Width = size + 16, Height = size + 16, StrokeThickness = 8, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            halo.SetResourceReference(Shape.StrokeProperty, "amberSoftBrush");
            Children.Add(halo);
            var disc = new Ellipse
            {
                Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                Fill = Frozen(new LinearGradientBrush(PerdeColors.Rgb(255, 210, 122), PerdeColors.Rgb(240, 169, 44), new Point(0, 0), new Point(1, 1))),
            };
            Children.Add(disc);
            var check = StepTimeline.Check(size * 0.45, "onAmberBrush", 3.2);
            Children.Add(check);
            if (MotionGate.Reduced) return;
            var seat = new ScaleTransform(0.3, 0.3);
            check.RenderTransformOrigin = new Point(0.5, 0.5);
            check.RenderTransform = seat;
            check.Opacity = 0;
            var spring = new DoubleAnimation(0.3, 1, TimeSpan.FromMilliseconds(Palette.MotionMs("celebrate", 600))) { EasingFunction = Motion.Spring };
            seat.BeginAnimation(ScaleTransform.ScaleXProperty, spring);
            seat.BeginAnimation(ScaleTransform.ScaleYProperty, spring);
            check.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)));
        }
        catch (Exception error) { System.Diagnostics.Debug.WriteLine($"Başarı anı: {error.Message}"); }
    }

    /// <summary>Konik ışınlar (8° ışın / 24° adım), merkezden söner; yavaşça döner ve 1 sn içinde solar.</summary>
    private FrameworkElement Rays(Color amber)
    {
        var span = size * 3.2;
        var radius = span / 2;
        var figures = new PathGeometry();
        for (var index = 0; index < 15; index++)
        {
            var a = index * 24 * Math.PI / 180;
            var b = a + 8 * Math.PI / 180;
            var figure = new PathFigure { StartPoint = new Point(radius, radius), IsClosed = true };
            figure.Segments.Add(new LineSegment(new Point(radius + radius * Math.Cos(a), radius + radius * Math.Sin(a)), false));
            figure.Segments.Add(new ArcSegment(new Point(radius + radius * Math.Cos(b), radius + radius * Math.Sin(b)), new Size(radius, radius), 0, false,
                SweepDirection.Clockwise, false));
            figures.Figures.Add(figure);
        }
        figures.Freeze();
        var fill = new RadialGradientBrush { GradientStops = { new GradientStop(PerdeColors.WithAlpha(amber, 0.22), 0.25), new GradientStop(PerdeColors.WithAlpha(amber, 0), 1) } };
        fill.Freeze();
        var path = new Path
        {
            Data = figures, Fill = fill, Width = span, Height = span, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false, Opacity = 0, Margin = new Thickness(-span),
        };
        var rotate = new RotateTransform();
        path.RenderTransformOrigin = new Point(0.5, 0.5);
        path.RenderTransform = rotate;
        var total = TimeSpan.FromSeconds(1);
        rotate.BeginAnimation(RotateTransform.AngleProperty, Motion.Fps(new DoubleAnimation(0, 30, total), 30));
        var fade = new DoubleAnimationUsingKeyFrames { Duration = total };
        fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(200))));
        fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(700))));
        fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(total)));
        Motion.Fps(fade, 30);
        path.BeginAnimation(OpacityProperty, fade);
        return path;
    }

    private static T Frozen<T>(T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }
}

/// <summary>Başarı anı kartı (DSSuccessMoment): başarı anı + başlık (18) + kısa özet; ortalı.</summary>
public sealed class SuccessMoment : StackPanel
{
    public SuccessMoment(string title, string? message = null)
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        Children.Add(new Celebration());
        var heading = new TextBlock { Text = title, TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = Sp.T("0", "s", "0", "0"), TextWrapping = TextWrapping.Wrap };
        heading.SetResourceReference(TextBlock.FontSizeProperty, "h3FontSize");
        heading.FontWeight = FontWeights.Medium;
        heading.SetResourceReference(TextBlock.ForegroundProperty, "textBrush");
        Children.Add(heading);
        if (!string.IsNullOrEmpty(message))
        {
            var body = new TextBlock { Text = message, TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = Sp.T("0", "titleBody", "0", "0") };
            body.SetResourceReference(StyleProperty, "HintText");
            body.TextAlignment = TextAlignment.Center;
            Children.Add(body);
        }
        AutomationProperties.SetName(this, title);
    }
}

// ───────────── Altyazı plakası ve perde ─────────────

/// <summary>
/// Altyazı plakası (DSSubtitlePlate): her temada aynı koyu yarı saydam plaka, sıcak beyaz yarı kalın yazı, konuşan adı
/// renkli (varsayılan amber) ve kalın.
/// </summary>
public sealed class SubtitlePlate : Border
{
    private readonly TextBlock text = new() { FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight };

    public SubtitlePlate()
    {
        CornerRadius = new CornerRadius(10);
        Padding = Sp.T("s", "unitHint", "s", "unitHint");
        SetResourceReference(BackgroundProperty, "subtitlePlateBrush");
        HorizontalAlignment = HorizontalAlignment.Center;
        Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 6, Direction = 270, Opacity = 0.35, Color = Colors.Black };
        text.SetResourceReference(TextBlock.ForegroundProperty, "subtitleTextBrush");
        Child = text;
        Show(null, "", 17);
    }

    /// <summary>Satırı gösterir; <paramref name="speakerBrush"/> verilmezse ad amber.</summary>
    public void Show(string? speaker, string line, double size, Brush? speakerBrush = null)
    {
        text.FontSize = size;
        text.LineHeight = Math.Round(size * 1.3);
        text.Inlines.Clear();
        if (!string.IsNullOrEmpty(speaker))
        {
            var name = new Run(speaker + " ") { FontWeight = FontWeights.Bold };
            if (speakerBrush is not null) name.Foreground = speakerBrush;
            else name.SetResourceReference(TextElement.ForegroundProperty, "amberBrush");
            text.Inlines.Add(name);
        }
        text.Inlines.Add(new Run(line));
    }

    /// <summary>"Jason: Tamam." → ("Jason:", "Tamam."); adı olmayan satır olduğu gibi (Mac SpeakerSplit).</summary>
    public static (string? Speaker, string Line) Split(string text)
    {
        var at = text.IndexOf(": ", StringComparison.Ordinal);
        if (at > 0 && at <= 24 && text[..at].IndexOfAny(['.', '!', '?', '\n']) < 0) return (text[..(at + 1)], text[(at + 2)..]);
        return (null, text);
    }
}

/// <summary>Perdenin fırçaları: sıcak sahne (görüntü yokken) ve projeksiyon ışığı.</summary>
public static class PerdeBrushes
{
    /// <summary>
    /// Görüntü gelmeden önceki sahne (DSPerdeScene): özgün, soyut sinematik manzara (telifli görsel yok, tamamıyla çizim).
    /// Alacakaranlık göğü, ufukta batan güneş ve göğe vuran ışık hüzmeleri, katman katman tepeler, ufka koşan yol ve ince
    /// amber ufuk çizgisi. Durağan. 160 × 90 birimde çizilir, alana gerilir (perde hep 16:9).
    /// </summary>
    public static Brush Scene()
    {
        const double w = 160, h = 90;
        var horizon = h * 0.6;
        var sunX = w * 0.66;
        var amber = PerdeColors.Rgb(0xF5, 0xB8, 0x3D);
        var drawing = new DrawingGroup();
        var bounds = new RectangleGeometry(new Rect(0, 0, w, h));
        // Gök: üstte gece mavisi, ufka doğru kızıl-amber.
        var sky = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0), EndPoint = new Point(0, 1),
            GradientStops =
            {
                new GradientStop(C(0.067, 0.078, 0.122), 0), new GradientStop(C(0.188, 0.149, 0.188), 0.36), new GradientStop(C(0.62, 0.329, 0.231), 0.52),
                new GradientStop(C(0.937, 0.612, 0.29), 0.62), new GradientStop(C(0.937, 0.612, 0.29), 1),
            },
        };
        drawing.Children.Add(new GeometryDrawing(sky, null, bounds));
        // Işık hüzmeleri: güneşten göğe beş ince kama.
        var beams = new StreamGeometry();
        using (var g = beams.Open())
        {
            foreach (var (from, to) in new[] { (-0.8, -0.66), (-0.44, -0.33), (-0.1, 0.0), (0.2, 0.28), (0.52, 0.66) })
            {
                g.BeginFigure(new Point(sunX, horizon), true, true);
                g.LineTo(new Point(sunX + w * from, 0), false, false);
                g.LineTo(new Point(sunX + w * to, 0), false, false);
            }
        }
        var beamFill = new LinearGradientBrush(PerdeColors.WithAlpha(C(1, 0.85, 0.6), 0.2), Color.FromArgb(0, 255, 217, 153), new Point(0, horizon), new Point(0, 0))
        { MappingMode = BrushMappingMode.Absolute };
        drawing.Children.Add(new GeometryDrawing(beamFill, null, beams));
        // Güneş ve hâlesi.
        var halo = new RadialGradientBrush
        {
            MappingMode = BrushMappingMode.Absolute, Center = new Point(sunX, horizon), GradientOrigin = new Point(sunX, horizon), RadiusX = w * 0.42, RadiusY = w * 0.42,
            GradientStops =
            {
                new GradientStop(PerdeColors.WithAlpha(C(1, 0.78, 0.47), 0.8), 0), new GradientStop(PerdeColors.WithAlpha(C(0.95, 0.5, 0.25), 0.22), 0.5),
                new GradientStop(Color.FromArgb(0, 242, 128, 64), 1),
            },
        };
        drawing.Children.Add(new GeometryDrawing(halo, null, bounds));
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(C(1, 0.9, 0.72)), null, new EllipseGeometry(new Point(sunX, horizon), h * 0.08, h * 0.08)));
        // Uzak ve yakın tepeler (güneşin altını örter).
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(PerdeColors.WithAlpha(C(0.231, 0.153, 0.188), 0.92)), null, Ridge(w, h, horizon, h * 0.07, 0.2, 2.3)));
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(C(0.122, 0.09, 0.118)), null, Ridge(w, h, horizon + h * 0.035, h * 0.05, 1.4, 3.1)));
        var groundTop = horizon + h * 0.05;
        var ground = new LinearGradientBrush(C(0.122, 0.09, 0.118), C(0.035, 0.035, 0.043), new Point(0, groundTop), new Point(0, h)) { MappingMode = BrushMappingMode.Absolute };
        drawing.Children.Add(new GeometryDrawing(ground, null, new RectangleGeometry(new Rect(0, groundTop, w, h - groundTop))));
        // Ufka koşan yol (perspektif) ve ince amber ufuk çizgisi.
        var road = new StreamGeometry();
        using (var g = road.Open())
        {
            g.BeginFigure(new Point(sunX - 1.5 * w / 1000, groundTop), true, true);
            g.LineTo(new Point(sunX + 1.5 * w / 1000, groundTop), false, false);
            g.LineTo(new Point(sunX + w * 0.2, h), false, false);
            g.LineTo(new Point(sunX - w * 0.34, h), false, false);
        }
        var roadFill = new LinearGradientBrush(PerdeColors.WithAlpha(amber, 0.3), PerdeColors.WithAlpha(amber, 0.04), new Point(0, groundTop), new Point(0, h))
        { MappingMode = BrushMappingMode.Absolute };
        drawing.Children.Add(new GeometryDrawing(roadFill, null, road));
        var line = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0.5), EndPoint = new Point(1, 0.5),
            GradientStops = { new GradientStop(PerdeColors.WithAlpha(amber, 0), 0), new GradientStop(PerdeColors.WithAlpha(amber, 0.75), 0.5), new GradientStop(PerdeColors.WithAlpha(amber, 0), 1) },
        };
        drawing.Children.Add(new GeometryDrawing(line, null, new RectangleGeometry(new Rect(0, groundTop, w, 0.4))));
        drawing.ClipGeometry = bounds;
        var brush = new DrawingBrush(drawing) { Stretch = Stretch.Fill };
        brush.Freeze();
        return brush;
    }

    /// <summary>Yumuşak dalgalı tepe sırası (iki sinüsün toplamı), alta kadar dolu.</summary>
    private static Geometry Ridge(double w, double h, double baseline, double amplitude, double phase, double waves)
    {
        var geometry = new StreamGeometry();
        using (var g = geometry.Open())
        {
            g.BeginFigure(new Point(0, h), true, true);
            const int steps = 48;
            for (var index = 0; index <= steps; index++)
            {
                var t = (double)index / steps;
                var wave = 0.6 * Math.Sin(t * Math.PI * waves + phase) + 0.4 * Math.Sin(t * Math.PI * waves * 2.7 + phase * 1.7);
                g.LineTo(new Point(w * t, baseline - amplitude * wave - amplitude * 0.3), false, false);
            }
            g.LineTo(new Point(w, h), false, false);
        }
        geometry.Freeze();
        return geometry;
    }

    private static Color C(double r, double g, double b) => Color.FromRgb((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

    /// <summary>
    /// Projeksiyon ışığı (DSProjectorLight): üst kenardan düşen geniş, yumuşak amber ışık (koyuda %16, açıkta %22). Durağan.
    /// </summary>
    public static Brush ProjectorLight(bool dark)
    {
        var amber = PerdeColors.Get("amber", PerdeColors.Rgb(0xF5, 0xB8, 0x3D));
        var alpha = dark ? 0.16 : 0.22;
        var brush = new RadialGradientBrush
        {
            Center = new Point(0.5, -0.1), GradientOrigin = new Point(0.5, -0.1), RadiusX = 0.6, RadiusY = 0.6,
            GradientStops = { new GradientStop(PerdeColors.WithAlpha(amber, alpha), 0), new GradientStop(PerdeColors.WithAlpha(amber, 0), 1) },
        };
        brush.Freeze();
        return brush;
    }
}

/// <summary>Projeksiyon ışığı katmanı: temaya göre kendini yeniler, tıklamayı geçirir.</summary>
public sealed class ProjectorLight : Border
{
    public ProjectorLight()
    {
        IsHitTestVisible = false;
        Background = PerdeBrushes.ProjectorLight(ThemeManager.IsDark);
        void Refresh() => Background = PerdeBrushes.ProjectorLight(ThemeManager.IsDark);
        Loaded += (_, _) => { ThemeManager.Changed -= Refresh; ThemeManager.Changed += Refresh; Refresh(); };
        Unloaded += (_, _) => ThemeManager.Changed -= Refresh;
    }
}

/// <summary>Köşeleri yuvarlak kırpılan kap (WPF Border çocuklarını köşeden kırpmaz).</summary>
public sealed class RoundClip : Decorator
{
    public static readonly DependencyProperty RadiusProperty = DependencyProperty.Register(nameof(Radius), typeof(double), typeof(RoundClip),
        new FrameworkPropertyMetadata(20.0, FrameworkPropertyMetadataOptions.AffectsArrange));

    public double Radius { get => (double)GetValue(RadiusProperty); set => SetValue(RadiusProperty, value); }

    protected override Size ArrangeOverride(Size arrangeSize)
    {
        var size = base.ArrangeOverride(arrangeSize);
        var clip = new RectangleGeometry(new Rect(size), Radius, Radius);
        clip.Freeze();
        Clip = clip;
        return size;
    }
}

/// <summary>
/// Perde (DSPerdePreview; deneme adımı, altyazı görünümü önizlemesi): 16:9, 20 köşe; sıcak sahne, alttan hafif kararma,
/// durağan projeksiyon ışığı, isteğe bağlı kesikli amber "Okunan Alan", altta altyazı plakası ve sağ üstte haplar.
/// </summary>
public sealed class PerdePreview : ContentControl
{
    private readonly Grid stage = new();
    private readonly SubtitlePlate plate = new() { VerticalAlignment = VerticalAlignment.Bottom };
    private readonly Grid area = new() { VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly StackPanel pills = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };

    public PerdePreview()
    {
        Focusable = false;
        stage.Background = PerdeColors.Frozen(PerdeColors.Rgb(11, 11, 13));
        stage.Children.Add(new Border { Background = PerdeBrushes.Scene(), IsHitTestVisible = false });
        stage.Children.Add(new Border
        {
            IsHitTestVisible = false,
            Background = Bottom(0.35),
        });
        stage.Children.Add(new ProjectorLight());
        var dash = new Rectangle { StrokeThickness = 1.5, StrokeDashArray = [4, 2.67], RadiusX = 12, RadiusY = 12, Opacity = 0.7 };
        dash.SetResourceReference(Shape.StrokeProperty, "amberBrush");
        area.Children.Add(dash);
        area.Children.Add(AreaLabel());
        stage.Children.Add(area);
        stage.Children.Add(plate);
        pills.Margin = Sp.T("s");
        stage.Children.Add(pills);
        stage.SizeChanged += (_, _) => Layout();
        var frame = new Grid();
        frame.Children.Add(new RoundClip { Radius = Palette.Radius.GetValueOrDefault("preview", 20), Child = stage });
        frame.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(Palette.Radius.GetValueOrDefault("preview", 20)), BorderThickness = new Thickness(1),
            BorderBrush = PerdeColors.Frozen(Color.FromArgb(0x0F, 0xFF, 0xFF, 0xFF)), IsHitTestVisible = false,
        });
        Content = new Views.AspectBox { Child = frame };
    }

    internal static Brush Bottom(double alpha)
    {
        var brush = new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromArgb(0, 0, 0, 0), 0.55), new(Color.FromArgb((byte)(alpha * 255), 0, 0, 0), 1),
        }, 90);
        brush.Freeze();
        return brush;
    }

    internal static Border AreaLabel()
    {
        var label = new Border
        {
            Height = 22, CornerRadius = new CornerRadius(11), Padding = new Thickness(9, 0, 9, 0), HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(10, -11, 0, 0),
        };
        label.SetResourceReference(Border.BackgroundProperty, "amberBrush");
        var text = new TextBlock { Text = CouchSubs.Core.Localizer.Current["Area Read"], FontSize = 11, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        text.SetResourceReference(TextBlock.ForegroundProperty, "onAmberBrush");
        label.Child = text;
        return label;
    }

    /// <summary>Altyazı satırı (konuşan adı amber); boşsa plaka gizli.</summary>
    public void SetLine(string? speaker, string? line, double size = 15, Brush? speakerBrush = null)
    {
        plate.Visibility = string.IsNullOrEmpty(line) ? Visibility.Collapsed : Visibility.Visible;
        if (!string.IsNullOrEmpty(line)) plate.Show(speaker, line, size, speakerBrush);
        Layout();
    }

    public bool ShowArea
    {
        get => area.Visibility == Visibility.Visible;
        set
        {
            area.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
            Layout();
        }
    }

    /// <summary>Sağ üstteki haplar (ör. "Canlı Önizleme").</summary>
    public void SetPills(params UIElement[] items)
    {
        pills.Children.Clear();
        for (var i = 0; i < items.Length; i++)
        {
            if (items[i] is FrameworkElement element && i > 0) element.Margin = Sp.T("xs", "0", "0", "0");
            pills.Children.Add(items[i]);
        }
    }

    /// <summary>Hapları sol üste alır (altyazı görünümü önizlemesi).</summary>
    public void PillsLeft() => pills.HorizontalAlignment = HorizontalAlignment.Left;

    private void Layout()
    {
        var w = stage.ActualWidth;
        var h = stage.ActualHeight;
        if (w <= 0 || h <= 0) return;
        var areaHeight = Math.Max(h * 0.2, 40);
        area.Width = w * 0.76;
        area.Height = areaHeight;
        area.Margin = new Thickness(0, 0, 0, h * 0.05);
        plate.MaxWidth = w - 2 * Sp.V("m");
        plate.Margin = new Thickness(0, 0, 0, Math.Max(h * 0.05, 8) + (ShowArea ? areaHeight / 2 - 18 : 0));
    }
}

// ───────────── Oyun kapağı ─────────────

/// <summary>
/// Oyun kapağı (DSCoverArt): kapak görseli yoksa oyunun adından ÖZGÜN TİPOGRAFİK kapak (gerçek kapak/logo kullanılmaz;
/// telif ve mağaza riski). Her oyuna kararlı bir degrade (adın karmasından), köşe ışığı, çapraz ışık bandı ve oyunun
/// kısaltması (GTA, RD2) iri, sıkı aralıklı ağır yazıyla. Küçük boyda (72'den küçük; simge karesi) yalnız kısaltma ortada.
/// </summary>
public sealed class CoverArt : FrameworkElement
{
    /// <summary>(üst, alt, ışık, yazı) — Mac ile aynı sekiz palet.</summary>
    private static readonly (Color Top, Color Bottom, Color Light, Color Ink)[] Palettes =
    [
        (C(0.957, 0.6, 0.267), C(0.6, 0.157, 0.157), C(1, 0.851, 0.6), C(1, 0.957, 0.886)),
        (C(0.878, 0.243, 0.396), C(0.247, 0.071, 0.247), C(1, 0.616, 0.69), C(1, 0.925, 0.937)),
        (C(0.204, 0.431, 0.851), C(0.059, 0.098, 0.282), C(0.592, 0.792, 1), C(0.902, 0.949, 1)),
        (C(0.137, 0.682, 0.651), C(0.035, 0.184, 0.231), C(0.588, 0.969, 0.894), C(0.89, 1, 0.976)),
        (C(0.537, 0.333, 0.91), C(0.122, 0.075, 0.29), C(0.792, 0.69, 1), C(0.957, 0.937, 1)),
        (C(0.961, 0.749, 0.239), C(0.71, 0.31, 0.075), C(1, 0.941, 0.69), C(0.165, 0.086, 0.035)),
        (C(0.937, 0.4, 0.29), C(0.318, 0.094, 0.408), C(1, 0.749, 0.588), C(1, 0.937, 0.91)),
        (C(0.42, 0.455, 0.51), C(0.11, 0.122, 0.149), C(0.8, 0.82, 0.86), C(0.937, 0.945, 0.957)),
    ];

    private static Color C(double r, double g, double b) => Color.FromRgb((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

    public static readonly DependencyProperty SeedProperty = DependencyProperty.Register(nameof(Seed), typeof(string), typeof(CoverArt),
        new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.AffectsRender));

    public string Seed { get => (string)GetValue(SeedProperty); set => SetValue(SeedProperty, value); }

    /// <summary>Kararlı karma (Mac ile aynı: 7, ×31 + Unicode değeri).</summary>
    public static (Color Top, Color Bottom, Color Light, Color Ink) Palette(string seed)
    {
        uint sum = 7;
        foreach (var rune in seed.EnumerateRunes()) sum = unchecked(sum * 31 + (uint)rune.Value);
        return Palettes[(int)(sum % (uint)Palettes.Length)];
    }

    private static readonly CultureInfo English = CultureInfo.GetCultureInfo("en-US");

    /// <summary>
    /// Oyunun kısaltması (Mac DSCoverArt.monogram): baştaki büyük harf kısaltma (GTA V → GTA), yoksa ilk iki anlamlı sözcüğün
    /// baş harfi + sondaki sayı ya da Roma rakamı sığarsa (Red Dead Redemption 2 → RD2); tek sözcük → ilk iki harf (Mafia → Ma).
    /// </summary>
    public static string Monogram(string title)
    {
        var words = Words(title);
        if (words.Count == 0) return "?";
        var first = words[0];
        if (first.Length is >= 2 and <= 4 && first == first.ToUpper(English) && first.All(char.IsLetter) && !IsRoman(first)) return first[..Math.Min(3, first.Length)];
        string[] skip = ["the", "of", "a", "an", "and", "to", "in", "on", "for"];
        var significant = words.Where(w => !skip.Contains(w.ToLower(English)) && !IsNumeral(w)).ToList();
        if (significant.Count >= 2) return string.Concat(significant.Take(3).Select(w => w[..1].ToUpper(English)));
        var word = significant.FirstOrDefault() ?? first;
        return word[..1].ToUpper(English) + (word.Length > 1 ? word.Substring(1, 1).ToLower(English) : "");
    }

    /// <summary>Adın sonundaki sayı ya da Roma rakamı (Red Dead Redemption 2 → 2, Grand Theft Auto VI → VI); yoksa null.</summary>
    public static string? Numeral(string title)
    {
        var words = Words(title);
        return words.Count > 1 && IsNumeral(words[^1]) && words[^1].Length <= 4 ? words[^1] : null;
    }

    private static List<string> Words(string title)
    {
        var words = new List<string>();
        var current = new System.Text.StringBuilder();
        foreach (var ch in title + " ")
        {
            if (char.IsLetterOrDigit(ch)) current.Append(ch);
            else if (current.Length > 0)
            {
                words.Add(current.ToString());
                current.Clear();
            }
        }
        return words.Where(w => w.Length > 1 || char.IsUpper(w[0]) || char.IsDigit(w[0])).ToList();
    }

    private static bool IsNumeral(string word) => word.All(char.IsDigit) || IsRoman(word);

    private static bool IsRoman(string word) => word.Length is > 0 and <= 4 && word.All(ch => ch is 'I' or 'V' or 'X');

    protected override void OnRender(DrawingContext context)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0) return;
        var (top, bottom, light, ink) = Palette(Seed ?? "");
        var span = Math.Max(w, h);
        var rect = new Rect(0, 0, w, h);
        context.PushClip(new RectangleGeometry(rect));
        context.DrawRectangle(new LinearGradientBrush(top, bottom, new Point(0.15, 0), new Point(0.85, 1)), null, rect);
        var glow = new RadialGradientBrush(PerdeColors.WithAlpha(light, 0.7), PerdeColors.WithAlpha(light, 0))
        {
            MappingMode = BrushMappingMode.Absolute, Center = new Point(w * 0.9, h * 0.05), GradientOrigin = new Point(w * 0.9, h * 0.05), RadiusX = span * 0.7, RadiusY = span * 0.7,
        };
        context.DrawRectangle(glow, null, rect);
        // Çapraz ışık bandı (28°).
        context.PushTransform(new RotateTransform(28, w * 0.64, h * 0.4));
        var band = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0.5), EndPoint = new Point(1, 0.5),
            GradientStops = { new GradientStop(Color.FromArgb(0, 255, 255, 255), 0), new GradientStop(Color.FromArgb(0x29, 255, 255, 255), 0.5), new GradientStop(Color.FromArgb(0, 255, 255, 255), 1) },
        };
        context.DrawRectangle(band, null, new Rect(w * 0.64 - span * 0.15, h * 0.4 - span * 1.1, span * 0.3, span * 2.2));
        context.Pop();
        var mark = Monogram(Seed ?? "");
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var face = new Typeface(new FontFamily("Segoe UI Variable Display, Segoe UI"), FontStyles.Normal, FontWeights.Black, FontStretches.Normal);
        if (Math.Min(w, h) < 72)
        {
            var size = Math.Min(w, h) * (mark.Length > 2 ? 0.34 : 0.44);
            var text = new FormattedText(mark, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, new SolidColorBrush(ink), dpi);
            if (text.Width > w * 0.9) text.SetFontSize(size * w * 0.9 / text.Width);
            context.DrawText(text, new Point((w - text.Width) / 2, (h - text.Height) / 2));
        }
        else
        {
            // İri kısaltma üst bölgede; altında kısa çizgi. Başlık (GameCover) alttaki scrim'in üstünde kalır.
            var size = w * (mark.Length > 2 ? 0.42 : 0.56);
            var text = new FormattedText(mark, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, new SolidColorBrush(PerdeColors.WithAlpha(ink, 0.94)), dpi);
            var room = w * (1 - 0.09 - 0.06);
            if (text.WidthIncludingTrailingWhitespace > room) text.SetFontSize(size * room / text.WidthIncludingTrailingWhitespace);
            var origin = new Point(w * 0.09, h * 0.1);
            var shadow = new FormattedText(mark, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, text.Height > 0 ? size : size,
                new SolidColorBrush(PerdeColors.WithAlpha(bottom, 0.5)), dpi);
            if (shadow.WidthIncludingTrailingWhitespace > room) shadow.SetFontSize(size * room / shadow.WidthIncludingTrailingWhitespace);
            context.DrawText(shadow, new Point(origin.X, origin.Y + Math.Max(1, w * 0.015)));
            context.DrawText(text, origin);
            var lineY = origin.Y + text.Baseline + text.Height * 0.12;
            var lineHeight = Math.Max(2, w * 0.02);
            context.DrawRoundedRectangle(new SolidColorBrush(PerdeColors.WithAlpha(ink, 0.75)), null, new Rect(origin.X, lineY, w * 0.2, lineHeight), lineHeight / 2, lineHeight / 2);
            // Sıra numarası (V, VI, 2) çizginin yanında küçük: V ile VI karışmaz.
            if (Numeral(Seed ?? "") is { } numeral)
            {
                var number = new FormattedText(numeral, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, w * 0.13,
                    new SolidColorBrush(PerdeColors.WithAlpha(ink, 0.9)), dpi);
                context.DrawText(number, new Point(origin.X + w * 0.24, lineY + lineHeight / 2 - number.Height / 2));
            }
        }
        context.Pop();
    }
}

/// <summary>
/// Oyun kapağı kartı (DSGameCover): 3:4 kapak, alttan scrim üstünde kalın beyaz başlık, sol üstte isteğe bağlı cam durum
/// hapı. Seçiliyken amber halka ve arkasında kapağın renginden durağan ışıma (bulanık kopya). Tıklanabilir.
/// </summary>
public sealed class GameCover : ButtonBase
{
    private readonly Border ring = new() { BorderThickness = new Thickness(2), Margin = new Thickness(-4), IsHitTestVisible = false, Visibility = Visibility.Collapsed };
    private readonly Border glow = new() { IsHitTestVisible = false, Visibility = Visibility.Collapsed };
    private bool selected;

    public GameCover(string title, string? status, bool selected, double width = 112)
    {
        var height = Math.Round(width / Theme.Palette.Size.GetValueOrDefault("coverAspect", 0.75));
        var radius = Theme.Palette.Radius.GetValueOrDefault("cover", 16);
        Width = width;
        Height = height;
        Cursor = System.Windows.Input.Cursors.Hand;
        SetResourceReference(FocusVisualStyleProperty, "FocusRingTile");
        var root = new Grid();
        // Seçili kapağın arkasında kapağın kendi renginden yumuşak ışıma (bulanık kopya, durağan).
        glow.Child = new CoverArt { Seed = title };
        glow.Width = width * 0.84;
        glow.Height = height * 0.94;
        glow.Margin = new Thickness(0, height * 0.22, 0, 0);
        glow.HorizontalAlignment = HorizontalAlignment.Center;
        glow.Opacity = 0.55;
        glow.Effect = new BlurEffect { Radius = 18, RenderingBias = RenderingBias.Performance };
        root.Children.Add(glow);
        var stage = new Grid();
        stage.Children.Add(new CoverArt { Seed = title });
        var scrim = new LinearGradientBrush(new GradientStopCollection { new(Color.FromArgb(0, 0, 0, 0), 0.45), new(Color.FromArgb(0xB8, 0, 0, 0), 1) }, 90);
        scrim.Freeze();
        stage.Children.Add(new Border { Background = scrim });
        stage.Children.Add(new TextBlock
        {
            Text = title, Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = width < 110 ? 12 : 14, TextWrapping = TextWrapping.Wrap,
            MaxHeight = (width < 110 ? 12 : 14) * 2.8, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(10, 0, 10, 9), Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 0, Opacity = 0.5, Color = Colors.Black },
        });
        if (!string.IsNullOrEmpty(status))
            stage.Children.Add(new Chip
            {
                Text = status, Tone = ChipTone.Glass, ShowDot = false, Margin = new Thickness(6), VerticalAlignment = VerticalAlignment.Top,
                LayoutTransform = new ScaleTransform(0.85, 0.85),
            });
        root.Children.Add(new RoundClip { Radius = radius, Child = stage });
        ring.CornerRadius = new CornerRadius(radius + 4);
        ring.SetResourceReference(Border.BorderBrushProperty, "amberBrush");
        root.Children.Add(ring);
        Template = Plain();
        Content = root;
        AutomationProperties.SetName(this, title);
        Selected = selected;
    }

    public bool Selected
    {
        get => selected;
        set
        {
            selected = value;
            ring.Visibility = glow.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    /// <summary>İçeriği olduğu gibi çizen şablon; basılınca hafif soluklaşır.</summary>
    internal static ControlTemplate Plain()
    {
        var template = new ControlTemplate(typeof(ButtonBase));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        template.VisualTree = presenter;
        var pressed = new Trigger { Property = IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(OpacityProperty, 0.88));
        template.Triggers.Add(pressed);
        template.Seal();
        return template;
    }
}

// ───────────── Ortam ışığı ─────────────

/// <summary>
/// Ortam ışığı (DSAmbientGlow): amber, şeftali ve gök mavisi üç yumuşak (radyal) leke 24 sn'lik döngüde birkaç yüzde
/// süzülür. Bulanıklık süzgeci yok; lekeler bit eşlem önbelleğinde (BitmapCache) taşınır, en çok 15 kare/sn: boşta işlemci
/// yükü çok düşük. Kapı kapalıyken (çeviri, hareketi azalt, arka plan) ya da <see cref="Animated"/> kapalıyken durağan.
/// </summary>
public sealed class AmbientGlow : Canvas
{
    private static readonly (string Name, double X, double Y, double Scale, double Alpha, double Dx, double Dy)[] Blobs =
    [
        ("amber", 0.25, 0.2, 0.42, 0.18, 0.04, 0.03),
        ("peach", 0.8, 0.1, 0.36, 0.12, -0.04, 0.03),
        ("sky", 0.7, 0.9, 0.42, 0.06, 0.04, -0.03),
    ];

    public static readonly DependencyProperty AnimatedProperty = DependencyProperty.Register(nameof(Animated), typeof(bool), typeof(AmbientGlow),
        new FrameworkPropertyMetadata(true, (d, _) => ((AmbientGlow)d).OnGateChanged()));

    private readonly Ellipse[] ellipses = new Ellipse[Blobs.Length];
    private readonly TranslateTransform[] drifts = new TranslateTransform[Blobs.Length];
    private bool running;

    public AmbientGlow()
    {
        IsHitTestVisible = false;
        ClipToBounds = true;
        for (var i = 0; i < Blobs.Length; i++)
        {
            drifts[i] = new TranslateTransform();
            ellipses[i] = new Ellipse { RenderTransform = drifts[i], CacheMode = new BitmapCache(0.5) };
            Children.Add(ellipses[i]);
        }
        SizeChanged += (_, _) => Layout();
        Paint();
        void Refresh() => Paint();
        Loaded += (_, _) => { ThemeManager.Changed -= Refresh; ThemeManager.Changed += Refresh; Paint(); };
        Unloaded += (_, _) => ThemeManager.Changed -= Refresh;
        Motion.Gated(this, () => MotionGate.Ambient && Animated && Hardware, Start, Stop);
    }

    /// <summary>Süzülme açık mı (Geçmiş ve Ayarlar'da durağan; Mac ile aynı: yalnız Ana Ekran'da süzülür).</summary>
    public bool Animated { get => (bool)GetValue(AnimatedProperty); set => SetValue(AnimatedProperty, value); }

    public double Intensity { get; set; } = 0.8;

    /// <summary>
    /// Süzülme yalnız ekran kartıyla çizimde (WPF çizim katmanı 2) ve uzak masaüstünde değilken. Yazılımla çizimde bütün
    /// pencere her karede işlemcide yeniden çizilir (CI'daki sanal makinede boşta %90'a çıktı); orada lekeler durağan.
    /// </summary>
    public static bool Hardware => (RenderCapability.Tier >> 16) >= 2 && !SystemParameters.IsRemoteSession && !throttled;

    /// <summary>
    /// Boşta işlemci koruması (Perde hedefi ≤ %2): süzülme sürerken sürecin işlemci payı 4 sn'lik iki ölçümde üst üste %2'yi
    /// geçerse (ekran kartı aslında yazılımla çiziyor: sürücüsüz sanal makine, Temel Görüntü Bağdaştırıcısı) süzülme bu
    /// oturumda kapanır, lekeler durağan kalır. Ölçüm Process.TotalProcessorTime farkıdır, kendisi yük getirmez.
    /// </summary>
    private static bool throttled;
    private readonly System.Windows.Threading.DispatcherTimer guard = new() { Interval = TimeSpan.FromSeconds(4) };
    private TimeSpan guardCpu;
    private DateTime guardAt;
    private int guardStrikes;

    private void Guard()
    {
        try
        {
            using var process = System.Diagnostics.Process.GetCurrentProcess();
            var cpu = process.TotalProcessorTime;
            var now = DateTime.UtcNow;
            var share = (cpu - guardCpu).TotalSeconds / Math.Max(0.001, (now - guardAt).TotalSeconds) / Environment.ProcessorCount * 100;
            guardCpu = cpu;
            guardAt = now;
            guardStrikes = share > 2 ? guardStrikes + 1 : 0;
            if (guardStrikes < 2) return;
            throttled = true;
            Stop();
        }
        catch (Exception error) { System.Diagnostics.Debug.WriteLine($"Ortam ışığı ölçümü: {error.Message}"); }
    }

    private void OnGateChanged()
    {
        // Kapı yeniden değerlendirilsin diye görünürlük olayı yerine doğrudan.
        if (MotionGate.Ambient && Animated && Hardware && IsLoaded && IsVisible) { if (!running) Start(); }
        else if (running) Stop();
    }

    private void Paint()
    {
        for (var i = 0; i < Blobs.Length; i++)
        {
            var color = PerdeColors.Get(Blobs[i].Name, Colors.Orange);
            var brush = new RadialGradientBrush(PerdeColors.WithAlpha(color, Blobs[i].Alpha * Intensity), PerdeColors.WithAlpha(color, 0));
            brush.Freeze();
            ellipses[i].Fill = brush;
        }
    }

    private void Layout()
    {
        var w = ActualWidth;
        var h = ActualHeight;
        var span = Math.Max(w, h);
        for (var i = 0; i < Blobs.Length; i++)
        {
            var radius = span * Blobs[i].Scale;
            ellipses[i].Width = ellipses[i].Height = radius * 2;
            SetLeft(ellipses[i], w * Blobs[i].X - radius);
            SetTop(ellipses[i], h * Blobs[i].Y - radius);
        }
        if (running)
        {
            Stop();
            Start();
        }
    }

    private void Start()
    {
        if (throttled) return;
        running = true;
        guardStrikes = 0;
        using (var process = System.Diagnostics.Process.GetCurrentProcess()) guardCpu = process.TotalProcessorTime;
        guardAt = DateTime.UtcNow;
        guard.Tick -= OnGuard;
        guard.Tick += OnGuard;
        guard.Start();
        var half = TimeSpan.FromMilliseconds(Palette.MotionMs("ambient", 24000) / 2);
        for (var i = 0; i < Blobs.Length; i++)
        {
            DoubleAnimation Drift(double to) => Motion.Fps(new DoubleAnimation(0, to, half)
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = Motion.InOut, BeginTime = TimeSpan.FromMilliseconds(-half.TotalMilliseconds * i * 0.66),
            }, 10);
            drifts[i].BeginAnimation(TranslateTransform.XProperty, Drift(ActualWidth * Blobs[i].Dx));
            drifts[i].BeginAnimation(TranslateTransform.YProperty, Drift(ActualHeight * Blobs[i].Dy));
        }
    }

    private void OnGuard(object? sender, EventArgs e) => Guard();

    private void Stop()
    {
        running = false;
        guard.Stop();
        for (var i = 0; i < Blobs.Length; i++)
        {
            drifts[i].BeginAnimation(TranslateTransform.XProperty, null);
            drifts[i].BeginAnimation(TranslateTransform.YProperty, null);
        }
    }
}

// ───────────── TV kartı ─────────────

/// <summary>
/// TV kartı (DSTVCard): simge karesi, ad + mono ayrıntı (marka · adres), sağda durum hapı ve isteğe bağlı eylem (ör. küçük
/// "Bağlan"). Her zaman kıl çizgi; üzerine gelince güçlü kenar; seçiliyken 2 px amber kenar + amber yumuşak dolgu + ışıma,
/// simge amber. Görünümü Theme/Styles.xaml'da.
/// </summary>
public class TvCard : Button
{
    public static readonly DependencyProperty TvNameProperty = DependencyProperty.Register(nameof(TvName), typeof(string), typeof(TvCard));
    public static readonly DependencyProperty DetailProperty = DependencyProperty.Register(nameof(Detail), typeof(string), typeof(TvCard));
    public static readonly DependencyProperty StatusProperty = DependencyProperty.Register(nameof(Status), typeof(string), typeof(TvCard));
    public static readonly DependencyProperty StatusToneProperty = DependencyProperty.Register(nameof(StatusTone), typeof(ChipTone), typeof(TvCard),
        new FrameworkPropertyMetadata(ChipTone.Ok));
    public static readonly DependencyProperty SelectedProperty = DependencyProperty.Register(nameof(Selected), typeof(bool), typeof(TvCard));
    public static readonly DependencyProperty TrailingProperty = DependencyProperty.Register(nameof(Trailing), typeof(object), typeof(TvCard));

    static TvCard() => DefaultStyleKeyProperty.OverrideMetadata(typeof(TvCard), new FrameworkPropertyMetadata(typeof(TvCard)));

    public string? TvName { get => (string?)GetValue(TvNameProperty); set => SetValue(TvNameProperty, value); }
    public string? Detail { get => (string?)GetValue(DetailProperty); set => SetValue(DetailProperty, value); }
    public string? Status { get => (string?)GetValue(StatusProperty); set => SetValue(StatusProperty, value); }
    public ChipTone StatusTone { get => (ChipTone)GetValue(StatusToneProperty); set => SetValue(StatusToneProperty, value); }
    public bool Selected { get => (bool)GetValue(SelectedProperty); set => SetValue(SelectedProperty, value); }
    public object? Trailing { get => GetValue(TrailingProperty); set => SetValue(TrailingProperty, value); }
}
