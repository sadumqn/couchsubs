// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using CouchSubs.App.Controls;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;
using Frame = CouchSubs.Core.Frame;

namespace CouchSubs.App.Views;

// Ana ekranın parçaları (Perde; Mac HomeView): durum karosu, perde (oyun görüntüsü önizlemesi), Canlı Akış satırı ve küçük
// grafikler.

/// <summary>
/// Durum karosu (Mac HomeTile): e1 yüzey, 16 köşe, en az 64 yüksek; solda 36'lık renkli simge karesi (oyun karosunda kapak),
/// üstte 12 anahtar + durum noktası, altında 15 yarı kalın değer ve mono ek bilgi. Üzerine gelince güçlü kenar; tıklanınca
/// ilgili ayara gider.
/// </summary>
public sealed class HomeTile : Button
{
    private readonly Border frame = new() { CornerRadius = new CornerRadius(16), BorderThickness = new Thickness(1), MinHeight = 64, Padding = Sp.T("s", "xs", "s", "xs") };
    private readonly ContentControl icon = new() { Width = 36, Height = 36, Focusable = false, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock key = new() { FontSize = 12, TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly Ellipse dot = new() { Width = 6, Height = 6, VerticalAlignment = VerticalAlignment.Center, Margin = Sp.T("xxs", "0", "0", "0") };
    private readonly TextBlock value = new() { FontSize = 15, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis, MaxHeight = 40 };
    private readonly TextBlock detail = new() { FontSize = 11, FontWeight = FontWeights.Medium, TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis };
    /// <summary>Dikkat isteyen karo (Xbox'ta oyun seçilmedi): amber halka (Mac HomeTile highlighted).</summary>
    private bool highlighted;

    public HomeTile()
    {
        Cursor = System.Windows.Input.Cursors.Hand;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        SetResourceReference(FocusVisualStyleProperty, "FocusRingTile");
        Template = GameCover.Plain();
        frame.SetResourceReference(Border.BackgroundProperty, "surfaceBrush");
        frame.SetResourceReference(Border.BorderBrushProperty, "cardEdgeBrush");
        key.SetResourceReference(TextBlock.ForegroundProperty, "mutedBrush");
        value.SetResourceReference(TextBlock.ForegroundProperty, "textBrush");
        detail.SetResourceReference(TextBlock.ForegroundProperty, "mutedBrush");
        System.Windows.Documents.Typography.SetNumeralAlignment(detail, FontNumeralAlignment.Tabular);
        var head = new StackPanel { Orientation = Orientation.Horizontal };
        head.Children.Add(key);
        head.Children.Add(dot);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = Sp.T("s", "0", "0", "0") };
        texts.Children.Add(head);
        value.Margin = Sp.T("0", "line", "0", "0");
        texts.Children.Add(value);
        detail.Margin = Sp.T("0", "line", "0", "0");
        texts.Children.Add(detail);
        var row = new DockPanel();
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        row.Children.Add(texts);
        frame.Child = row;
        Content = frame;
        MouseEnter += (_, _) => { if (!highlighted) frame.SetResourceReference(Border.BorderBrushProperty, "borderStrongBrush"); };
        MouseLeave += (_, _) => ShowEdge();
    }

    private void ShowEdge()
    {
        frame.SetResourceReference(Border.BorderBrushProperty, highlighted ? "amberBrush" : IsMouseOver ? "borderStrongBrush" : "cardEdgeBrush");
        frame.BorderThickness = new Thickness(highlighted ? 1.5 : 1);
    }

    /// <summary>Karoyu doldurur. <paramref name="cover"/> verilirse simge karesi yerine oyunun kapağı (adından degrade).</summary>
    public void Show(string name, string text, string? more, StatusTone tone, string glyph, IconTone iconTone, string? cover = null, bool highlight = false)
    {
        if (highlighted != highlight)
        {
            highlighted = highlight;
            ShowEdge();
        }
        key.Text = name;
        value.Text = text;
        value.ToolTip = text;
        detail.Text = more ?? "";
        detail.Visibility = string.IsNullOrEmpty(more) ? Visibility.Collapsed : Visibility.Visible;
        dot.SetResourceReference(Shape.FillProperty, tone switch
        {
            StatusTone.Good => "successBrush",
            StatusTone.Warning => "liveBrush",
            _ => "faintBrush",
        });
        if (cover is not null)
        {
            if (icon.Content is not RoundClip { Child: CoverArt art } clip || art.Seed != cover)
                icon.Content = new RoundClip { Radius = 11, Child = new CoverArt { Seed = cover } };
        }
        else if (icon.Content is IconSquare square)
        {
            square.Glyph = glyph;
            square.Tone = iconTone;
        }
        else icon.Content = new IconSquare { Glyph = glyph, Tone = iconTone, Size = 36 };
        AutomationProperties.SetName(this, string.IsNullOrEmpty(more) ? $"{name}: {text}" : $"{name}: {text} · {more}");
    }
}

/// <summary>Canlı Akış satırı: konuşan (amber, küçük), çeviri (kalın), İngilizcesi (gri); yaşı 0 en yeni (eski satırlar solar).</summary>
public sealed record FeedLine(string? Speaker, string Line, string Source, int Age)
{
    public bool HasSpeaker => !string.IsNullOrEmpty(Speaker);
}

/// <summary>İçeriği sığan en büyük 16:9 dikdörtgene yerleştirir (oyun görüntüsü hep 16:9).</summary>
public sealed class AspectBox : Decorator
{
    public double Ratio { get; set; } = 16.0 / 9.0;

    private Size Fit(Size available)
    {
        var width = double.IsInfinity(available.Width) ? available.Height * Ratio : available.Width;
        var height = width / Ratio;
        if (!double.IsInfinity(available.Height) && height > available.Height)
        {
            height = available.Height;
            width = height * Ratio;
        }
        return double.IsNaN(width) || double.IsInfinity(width) ? new Size(0, 0) : new Size(width, height);
    }

    protected override Size MeasureOverride(Size constraint)
    {
        var size = Fit(constraint);
        Child?.Measure(size);
        return size;
    }

    protected override Size ArrangeOverride(Size arrangeSize)
    {
        var size = Fit(arrangeSize);
        Child?.Arrange(new Rect((arrangeSize.Width - size.Width) / 2, (arrangeSize.Height - size.Height) / 2, size.Width, size.Height));
        return arrangeSize;
    }
}

/// <summary>
/// Perde (Mac HomePerde): oyunun son karesi (yoksa sıcak sahne), alttan hafif kararma, durağan projeksiyon ışığı, okunan alan
/// (kesikli amber, "Okunan Alan" etiketi; durağan), son çeviri altyazı plakasında (konuşan adı amber; okunan alanın ortasında),
/// sağ üstte cam haplar (CANLI nabız + kare hızı). Kart çerçevesi yok; 20 köşe, ince beyaz kıl çizgi, altına düşen yumuşak
/// amber yansıma. Kare saniyede en çok 4 kez çizilir (WriteableBitmap yeniden kullanılır).
/// </summary>
public sealed class GamePreview : ContentControl
{
    private readonly Image image = new() { Stretch = Stretch.UniformToFill };
    private readonly Grid stage = new();
    private readonly Grid area = new() { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    private readonly SubtitlePlate plate = new() { VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed };
    private readonly StackPanel pills = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top };
    private readonly Chip rateChip = new() { Tone = ChipTone.Glass, ShowDot = false, Height = 28 };
    private readonly Border reflection = new() { CornerRadius = new CornerRadius(20) };
    private WriteableBitmap? bitmap;
    private long lastDraw;
    private CropRegion region = new();
    private bool live = true;

    public GamePreview()
    {
        Focusable = false;
        var radius = Palette.Radius.GetValueOrDefault("preview", 20);
        stage.Background = PerdeColors.Frozen(PerdeColors.Rgb(11, 11, 13));
        stage.Children.Add(new Border { Background = PerdeBrushes.Scene(), IsHitTestVisible = false });
        stage.Children.Add(image);
        // Alt yarı hafif kararır (plaka okunur kalsın).
        stage.Children.Add(new Border { Background = PerdePreview.Bottom(0.4), IsHitTestVisible = false });
        stage.Children.Add(new ProjectorLight());
        var dash = new Rectangle { StrokeThickness = 1.5, StrokeDashArray = [4, 2.67], RadiusX = 12, RadiusY = 12, Opacity = 0.75 };
        dash.SetResourceReference(Shape.StrokeProperty, "amberBrush");
        area.Children.Add(dash);
        area.Children.Add(PerdePreview.AreaLabel());
        area.IsHitTestVisible = false;
        stage.Children.Add(area);
        stage.Children.Add(plate);
        pills.Children.Add(rateChip);
        pills.Margin = Sp.T("s");
        stage.Children.Add(pills);
        stage.SizeChanged += (_, _) => Layout();
        // Perdenin altına düşen yumuşak amber yansıma (durağan gölge; canlıyken biraz güçlü).
        reflection.Background = PerdeColors.Frozen(PerdeColors.Rgb(11, 11, 13));
        reflection.Effect = PerdeEffects.AmberGlow(52, 14, 0.16);
        var frame = new Grid();
        frame.Children.Add(reflection);
        frame.Children.Add(new RoundClip { Radius = radius, Child = stage });
        frame.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(radius), BorderThickness = new Thickness(1), IsHitTestVisible = false,
            BorderBrush = PerdeColors.Frozen(Color.FromArgb(0x0F, 0xFF, 0xFF, 0xFF)),
        });
        Content = new AspectBox { Child = frame };
        SetLive(false);
    }

    /// <summary>
    /// Çeviri durumu: perdede CANLI hapı yok (durum tek yerde, üst çubuktaki "Çeviri Açık"); canlıyken alttaki amber yansıma
    /// güçlenir, boşta görüntü yoksa örnek altyazı plakası altyazının nerede ve nasıl görüneceğini gösterir.
    /// </summary>
    public void SetLive(bool running)
    {
        if (live == running && reflection.Effect is not null) return;
        live = running;
        reflection.Effect = PerdeEffects.AmberGlow(52, 14, running ? 0.28 : 0.16);
        ShowSample();
    }

    /// <summary>Boşta (çeviri durmuş, görüntü yok, gösterilen satır yok) örnek plaka.</summary>
    private void ShowSample()
    {
        if (lastLine is not null) return;
        if (!live && image.Source is null)
        {
            plate.Show(null, Localizer.Current["Subtitles will appear here while you play."], 17);
            plate.Visibility = Visibility.Visible;
            Layout();
        }
        else plate.Visibility = Visibility.Collapsed;
    }

    private string? lastLine;

    /// <summary>Sağ üstteki cam hap: kaynak + kare hızı ("PS5 · Saniyede 10 Kare"; sans, sabit genişlikte rakam); boşsa gizli.</summary>
    public void SetRate(string? text)
    {
        if (rateChip.Text != (text ?? "")) rateChip.Text = text ?? "";
        rateChip.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
        if (rateChip.Child is StackPanel row && row.Children.OfType<TextBlock>().LastOrDefault() is { } label)
            System.Windows.Documents.Typography.SetNumeralAlignment(label, FontNumeralAlignment.Tabular);
    }

    /// <summary>Son çeviri (konuşanın adı amber); boşsa plaka gizli. Yeni satır kısaca aşağıdan gelir (hareket kapısına göre).</summary>
    public void SetLine(string? line)
    {
        lastLine = string.IsNullOrWhiteSpace(line) ? null : line;
        if (lastLine is null)
        {
            plate.Visibility = Visibility.Collapsed;
            ShowSample();
            return;
        }
        var (speaker, body) = SubtitlePlate.Split(line!);
        plate.Show(speaker, body, 17);
        plate.Visibility = Visibility.Visible;
        Layout();
        Motion.EnterFrom(plate, 8);
    }

    public void SetRegion(CropRegion value)
    {
        region = value;
        Layout();
    }

    /// <summary>Kareyi çizer (saniyede en çok 4 kez); null ise sıcak sahne görünür.</summary>
    public void SetFrame(Frame? frame)
    {
        if (frame is null)
        {
            image.Source = null;
            bitmap = null;
            ShowSample();
            return;
        }
        var now = Environment.TickCount64;
        if (now - lastDraw < 250 && image.Source is not null) return;
        lastDraw = now;
        if (bitmap is null || bitmap.PixelWidth != frame.Width || bitmap.PixelHeight != frame.Height)
            bitmap = new WriteableBitmap(frame.Width, frame.Height, 96, 96, PixelFormats.Bgr32, null);
        bitmap.WritePixels(new Int32Rect(0, 0, frame.Width, frame.Height), frame.Pixels, frame.Stride, 0);
        if (image.Source != bitmap)
        {
            image.Source = bitmap;
            ShowSample();
        }
    }

    private void Layout()
    {
        var width = stage.ActualWidth;
        var height = stage.ActualHeight;
        if (width <= 0 || height <= 0) return;
        var rect = new Rect(width * region.Left, height * region.Top, Math.Max(0, width * (region.Right - region.Left)), Math.Max(0, height * (region.Bottom - region.Top)));
        area.Margin = new Thickness(rect.Left, rect.Top, 0, 0);
        area.Width = rect.Width;
        area.Height = rect.Height;
        // Plaka okunan alanın ortasında; alan çok inceyse perdenin alt beşte birinde (Mac plateY).
        plate.MaxWidth = width * 0.78;
        plate.Measure(new Size(plate.MaxWidth, double.PositiveInfinity));
        var center = rect.Height > 24 ? Math.Min(Math.Max(rect.Top + rect.Height / 2, height * 0.12), height * 0.9) : height * 0.82;
        plate.Margin = new Thickness(0, Math.Max(0, center - plate.DesiredSize.Height / 2), 0, 0);
    }
}

/// <summary>Satır kıvılcım çizgisi: amber çizgi, altında solan dolgu, sonda nokta (tasarım: Durum › Satır).</summary>
public sealed class Sparkline : FrameworkElement
{
    private IReadOnlyList<double> values = [];

    public Sparkline() => ThemeManager.Changed += InvalidateVisual;

    public IReadOnlyList<double> Values
    {
        get => values;
        set
        {
            values = value;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (values.Count < 2 || ActualWidth <= 0 || ActualHeight <= 0) return;
        var max = Math.Max(1, values.Max());
        var points = values.Select((v, i) => new Point(i * ActualWidth / (values.Count - 1), ActualHeight - 4 - v / max * (ActualHeight - 8))).ToList();
        var line = new StreamGeometry();
        using (var ctx = line.Open())
        {
            ctx.BeginFigure(points[0], false, false);
            ctx.PolyLineTo(points.Skip(1).ToList(), true, true);
        }
        var fill = new StreamGeometry();
        using (var ctx = fill.Open())
        {
            ctx.BeginFigure(new Point(0, ActualHeight), true, true);
            ctx.PolyLineTo(points.Append(new Point(ActualWidth, ActualHeight)).ToList(), false, true);
        }
        var accent = (Color)(TryFindResource("accentColor") ?? Colors.Orange);
        var deep = (Color)(TryFindResource("accentDeepColor") ?? Colors.DarkOrange);
        dc.DrawGeometry(new LinearGradientBrush(Color.FromArgb(0x59, accent.R, accent.G, accent.B), Color.FromArgb(0, accent.R, accent.G, accent.B), 90), null, fill);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(deep), 1.6) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, line);
        dc.DrawEllipse(new SolidColorBrush(deep), null, points[^1], 2.4, 2.4);
    }
}

/// <summary>Halka gösterge (paketten gelen satırların oranı).</summary>
public sealed class Ring : FrameworkElement
{
    private double fraction;

    public Ring() => ThemeManager.Changed += InvalidateVisual;

    public double Fraction
    {
        get => fraction;
        set
        {
            fraction = Math.Clamp(value, 0, 1);
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        var size = Math.Min(ActualWidth, ActualHeight);
        if (size <= 0) return;
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var radius = size / 2 - 4;
        var track = new Pen((Brush)(TryFindResource("borderBrush") ?? Brushes.LightGray), 5);
        dc.DrawEllipse(null, track, center, radius, radius);
        if (fraction <= 0) return;
        var pen = new Pen((Brush)(TryFindResource("accentDeepBrush") ?? Brushes.Orange), 5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        if (fraction >= 0.999)
        {
            dc.DrawEllipse(null, pen, center, radius, radius);
            return;
        }
        var angle = fraction * 2 * Math.PI;
        var start = new Point(center.X, center.Y - radius);
        var end = new Point(center.X + radius * Math.Sin(angle), center.Y - radius * Math.Cos(angle));
        var arc = new StreamGeometry();
        using (var ctx = arc.Open())
        {
            ctx.BeginFigure(start, false, false);
            ctx.ArcTo(end, new Size(radius, radius), 0, fraction > 0.5, SweepDirection.Clockwise, true, true);
        }
        dc.DrawGeometry(null, pen, arc);
    }
}

/// <summary>Son gecikmelerin çubukları (en yenisi koyu).</summary>
public sealed class Bars : FrameworkElement
{
    private IReadOnlyList<double> values = [];

    public Bars() => ThemeManager.Changed += InvalidateVisual;

    public IReadOnlyList<double> Values
    {
        get => values;
        set
        {
            values = value;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (values.Count == 0 || ActualWidth <= 0) return;
        const double gap = 3;
        var width = (ActualWidth - gap * (values.Count - 1)) / values.Count;
        var max = Math.Max(1, values.Max());
        var normal = (Brush)(TryFindResource("scrollThumbBrush") ?? Brushes.LightGray);
        var last = (Brush)(TryFindResource("charcoalBrush") ?? Brushes.Black);
        for (var i = 0; i < values.Count; i++)
        {
            var height = Math.Max(4, values[i] / max * ActualHeight);
            var rect = new Rect(i * (width + gap), ActualHeight - height, Math.Max(1, width), height);
            dc.DrawRoundedRectangle(i == values.Count - 1 ? last : normal, null, rect, 2, 2);
        }
    }
}
