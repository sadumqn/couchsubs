// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using CouchSubs.Core;
using Frame = CouchSubs.Core.Frame;
using Handle = CouchSubs.Core.RegionEdit.Handle;

namespace CouchSubs.App.Controls;

/// <summary>
/// Son karenin üstünde bir bölgeyi gösteren ve fareyle çizilen çerçeve: boş yerde sürükleyince yeni bölge çizilir,
/// sekiz tutamaçtan (köşeler ve kenar ortaları) tutunca boyutu, içinden tutunca yeri değişir. Bölgenin dışı karartılır;
/// okunacak yer belirgin olur. <see cref="Centered"/> açıksa (altyazı alanında "Ortada tut") yatay boyut ortadan değişir. Kurallar
/// <see cref="RegionEdit"/>'tedir (Mac, iPhone ve Android ile aynı).
/// </summary>
public sealed class RegionPicker : UserControl
{
    /// <summary>Kenara bu kadar piksel yaklaşınca kenar tutulur.</summary>
    private const double Grab = 10;
    private const double HandleSize = 10;

    private enum Drag { None, Draw, Edit }

    private readonly Grid preview = new() { Height = 281, ClipToBounds = true, Background = Brushes.Transparent };
    private readonly Image image = new() { Stretch = Stretch.Fill, IsHitTestVisible = false };
    private readonly TextBlock placeholder = new()
    {
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        TextAlignment = TextAlignment.Center,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(24),
        IsHitTestVisible = false,
    };
    /// <summary>Bölgenin dışını karartan yarı saydam örtü (bölgenin içi boş kalır).</summary>
    private readonly Path shade = new() { Fill = new SolidColorBrush(Color.FromArgb(128, 0, 0, 0)), IsHitTestVisible = false };
    private readonly Rectangle frameBox = new() { StrokeThickness = 2, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false };
    private readonly Rectangle[] handles = [.. Enumerable.Range(0, 8).Select(_ => MakeHandle())];
    private CropRegion region = new();
    private readonly TextBlock overlayText = new() { Foreground = Brushes.White, TextWrapping = TextWrapping.Wrap };
    private readonly Border overlay = new()
    {
        Background = new SolidColorBrush(Color.FromArgb(0xE6, 0, 0, 0)),
        CornerRadius = new CornerRadius(6),
        Padding = new Thickness(8, 5, 8, 5),
        HorizontalAlignment = HorizontalAlignment.Left,
        VerticalAlignment = VerticalAlignment.Top,
        Visibility = Visibility.Collapsed,
        IsHitTestVisible = false,
    };

    /// <summary>Seçilen alanın hemen altına (sığmıyorsa üstüne) bir metin koyar; null ya da boşsa kaldırır.</summary>
    public void ShowOverlay(string? text)
    {
        overlayText.Text = text ?? "";
        overlay.Visibility = string.IsNullOrWhiteSpace(text) ? Visibility.Collapsed : Visibility.Visible;
        Layout();
    }
    /// <summary>Görüntünün en/boy oranı; önizleme genişliğe göre bu oranla boy alır (pencere büyüdükçe büyür).</summary>
    private double aspect = 16.0 / 9;
    private Drag drag = Drag.None;
    private Handle dragHandle;
    private Point anchor;
    private CropRegion dragStart = new();

    public event EventHandler<CropRegion>? RegionChanged;

    /// <summary>Çerçeve şu an fareyle çiziliyor ya da taşınıyor (önizleme bu sırada yenilenmez).</summary>
    public bool IsDragging => drag != Drag.None;

    /// <summary>"Alanı sıfırla" düğmesinin döneceği bölge (ek bölgelerin varsayılanı altyazınınkinden farklıdır).</summary>
    public CropRegion DefaultRegion { get; set; } = new();

    /// <summary>
    /// Yatay boyut ortadan değişir: sağ kenar çekilince sol kenar da aynı kadar açılır (altyazı alanında "Ortada tut"
    /// açıkken; oyunların çoğu altyazıyı ortalar). Kapalıyken ve ek alanlarda yalnız tutulan kenar oynar.
    /// </summary>
    public bool Centered { get; set; }

    public RegionPicker()
    {
        frameBox.SetResourceReference(Shape.StrokeProperty, "accentBrush");
        foreach (var handle in handles) handle.SetResourceReference(Shape.FillProperty, "accentBrush");
        placeholder.Text = Localizer.Current["The game picture appears here once translating starts."];
        placeholder.SetResourceReference(StyleProperty, "CaptionText");
        preview.Children.Add(image);
        preview.Children.Add(placeholder);
        preview.Children.Add(shade);
        preview.Children.Add(frameBox);
        foreach (var handle in handles) preview.Children.Add(handle);
        overlay.Child = overlayText;
        preview.Children.Add(overlay);
        preview.SizeChanged += (_, _) => Layout();
        SizeChanged += (_, _) => FitHeight();
        preview.MouseLeftButtonDown += OnDown;
        preview.MouseMove += OnMove;
        preview.MouseLeftButtonUp += OnUp;
        preview.LostMouseCapture += (_, _) => drag = Drag.None;

        var panel = new StackPanel();
        var border = new Border { Child = preview, ClipToBounds = true };
        border.SetResourceReference(Border.CornerRadiusProperty, "radius.inner");
        border.SetResourceReference(Border.BackgroundProperty, "backgroundBrush");
        panel.Children.Add(border);

        var reset = new Button { Content = Localizer.Current["Reset area"], Margin = new Thickness(0, 12, 0, 0) };
        reset.Click += (_, _) => Region = DefaultRegion;
        panel.Children.Add(reset);
        Content = panel;
        Frame = null;
    }

    private static Rectangle MakeHandle() => new()
    {
        Width = HandleSize,
        Height = HandleSize,
        HorizontalAlignment = HorizontalAlignment.Left,
        VerticalAlignment = VerticalAlignment.Top,
        IsHitTestVisible = false,
    };

    public CropRegion Region
    {
        get => region;
        set
        {
            region = value;
            Layout();
            RegionChanged?.Invoke(this, value);
        }
    }

    /// <summary>Bölgeyi olay göndermeden değiştirir (sekme değişirken ayar kaydedilmesin diye).</summary>
    public void ShowRegion(CropRegion value)
    {
        region = value;
        Layout();
    }

    /// <summary>Çeviri başlayınca oyun görüntüsü burada görünür (yalnız resim değişir; çerçeve ve tutamaçlar yerinde kalır).</summary>
    public Frame? Frame
    {
        set
        {
            aspect = value is { Height: > 0 } ? (double)value.Width / value.Height : 16.0 / 9;
            FitHeight();
            image.Source = value is null ? null
                : BitmapSource.Create(value.Width, value.Height, 96, 96, PixelFormats.Bgra32, null, value.Pixels, value.Stride);
            placeholder.Visibility = value is null ? Visibility.Visible : Visibility.Collapsed;
            Layout();
        }
    }

    // --- Fare ---

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        var point = e.GetPosition(preview);
        ShowOverlay(null);
        anchor = point;
        dragStart = region;
        var handle = HandleAt(point);
        drag = handle is null ? Drag.Draw : Drag.Edit;
        dragHandle = handle ?? Handle.None;
        preview.CaptureMouse();
        e.Handled = true;
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        var point = e.GetPosition(preview);
        if (drag == Drag.None)
        {
            preview.Cursor = CursorFor(HandleAt(point));
            return;
        }
        if (preview.ActualWidth <= 0 || preview.ActualHeight <= 0) return;
        var (x, y) = (Clamp01(point.X / preview.ActualWidth), Clamp01(point.Y / preview.ActualHeight));
        var (startX, startY) = (Clamp01(anchor.X / preview.ActualWidth), Clamp01(anchor.Y / preview.ActualHeight));
        region = drag == Drag.Draw
            ? new CropRegion(Math.Min(startY, y), Math.Max(startY, y), Math.Min(startX, x), Math.Max(startX, x))
            : RegionEdit.Dragged(dragStart, dragHandle, x - startX, y - startY, Centered);
        Layout();
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        if (drag == Drag.None) return;
        var finished = drag;
        drag = Drag.None;
        preview.ReleaseMouseCapture();
        // Tıklamak ya da çok küçük çizmek bölgeyi bozmasın: önceki bölge kalır.
        if (finished == Drag.Draw
            && (region.Right - region.Left < RegionEdit.MinimumSize || region.Bottom - region.Top < RegionEdit.MinimumSize))
            region = dragStart;
        Layout();
        if (region != dragStart) RegionChanged?.Invoke(this, region);
    }

    private static double Clamp01(double value) => Math.Clamp(value, 0, 1);

    /// <summary>İmlecin altındaki tutamaç; çerçevenin içiyse taşıma, dışıysa null (yeni bölge çizilir).</summary>
    private Handle? HandleAt(Point point)
    {
        var (width, height) = (preview.ActualWidth, preview.ActualHeight);
        if (width <= 0 || height <= 0) return null;
        return RegionEdit.HandleAt(region, point.X / width, point.Y / height, Grab / width, Grab / height);
    }

    private static Cursor CursorFor(Handle? handle) => handle switch
    {
        null => Cursors.Cross,
        Handle.Left or Handle.Right => Cursors.SizeWE,
        Handle.Top or Handle.Bottom => Cursors.SizeNS,
        Handle.Left | Handle.Top or Handle.Right | Handle.Bottom => Cursors.SizeNWSE,
        Handle.Right | Handle.Top or Handle.Left | Handle.Bottom => Cursors.SizeNESW,
        _ => Cursors.SizeAll,
    };

    /// <summary>Önizlemenin boyu, genişliğe ve görüntünün oranına göre ayarlanır.</summary>
    private void FitHeight()
    {
        if (ActualWidth <= 0) return;
        var height = Math.Max(120, ActualWidth / aspect);
        if (Math.Abs(preview.Height - height) > 0.5) preview.Height = height;
    }

    private void Layout()
    {
        var (width, height) = (preview.ActualWidth, preview.ActualHeight);
        var bounds = new Rect(width * region.Left, height * region.Top, width * (region.Right - region.Left), height * (region.Bottom - region.Top));
        frameBox.Margin = new Thickness(bounds.X, bounds.Y, 0, 0);
        frameBox.Width = Math.Max(0, bounds.Width);
        frameBox.Height = Math.Max(0, bounds.Height);
        shade.Data = new GeometryGroup
        {
            FillRule = FillRule.EvenOdd,
            Children = { new RectangleGeometry(new Rect(0, 0, Math.Max(0, width), Math.Max(0, height))), new RectangleGeometry(bounds) },
        };
        var spots = RegionEdit.Handles(region);
        for (var i = 0; i < handles.Length; i++)
            handles[i].Margin = new Thickness((spots[i].X * width) - (HandleSize / 2), (spots[i].Y * height) - (HandleSize / 2), 0, 0);

        if (overlay.Visibility != Visibility.Visible || width <= 0) return;
        overlayText.FontSize = Math.Clamp(height * 0.045, 11, 22);
        overlay.MaxWidth = Math.Max(120, width * 0.7);
        overlay.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = overlay.DesiredSize;
        var y = bounds.Bottom + 4;
        if (y + size.Height > height) y = bounds.Top - 4 - size.Height;
        y = Math.Clamp(y, 0, Math.Max(0, height - size.Height));
        var x = Math.Clamp(bounds.Left, 0, Math.Max(0, width - size.Width));
        overlay.Margin = new Thickness(x, y, 0, 0);
    }
}
