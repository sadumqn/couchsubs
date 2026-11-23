// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// GTA 6 telefonunun mesajları (Mac: GamePhoneBlocks): her çeviri kendi balonunun yerinde, balonun zemin ve yazı
/// renginde. Koordinatlar oyun karesindeki kutularla aynı (sol üst köşeye göre 0…1); yayın penceresinde pencerenin
/// tamamına, saydam altyazı penceresinde telefona ayrılan alana yerleşir. Türkçe uzunsa yazı en çok %45 küçülür, yine
/// sığmazsa balon aşağı uzar (TV gibi; yazı kesilmez). Bildirim (X, Windows 11, beta.81/82): bütün mesajlar tek yığın
/// olarak ortada ya da solda çıkıyor, kimin ne yazdığı belli olmuyordu (eskiden bloklar alt alta tek kutuya diziliyordu).
/// </summary>
internal sealed class PhoneBlocksCanvas : Canvas
{
    /// <summary>Sığmayan Türkçe için yazının en çok küçüleceği oran (Mac minimumScaleFactor ile aynı).</summary>
    private const double MinScale = 0.55;

    private IReadOnlyList<ScreenTranslation.Item> items = [];

    public PhoneBlocksCanvas()
    {
        IsHitTestVisible = false;
        ClipToBounds = true;
        SizeChanged += (_, _) => Layout();
    }

    public bool HasItems => items.Count > 0;

    /// <summary>
    /// Verilirse (saydam pencere: alan oyun karesi değil, kullanıcının seçtiği altyazı yeri) sohbet paneli alanın telefon
    /// tarafındaki kenarına yaslanır, yazısı bu boydadır (altyazı boyutundan; Mac GamePhoneBlocks panelFont ile aynı).
    /// </summary>
    public double? PanelFont { get; set; }

    public void Show(IReadOnlyList<ScreenTranslation.Item>? blocks)
    {
        items = blocks ?? [];
        Layout();
    }

    private void Layout()
    {
        Children.Clear();
        double width = ActualWidth, height = ActualHeight;
        if (width <= 0 || height <= 0) return;
        // Yanda Panel: telefonun mesajları sohbet panelinde (PhonePanelView), panel dışındaki yazılar kendi yerinde.
        var panel = ScreenPhoneCard.PanelOf(items);
        if (panel is not null) AddPanel(panel, width, height);
        foreach (var item in panel?.Outside ?? items)
        {
            if (ScreenPhoneCard.IsBackdrop(item) || item.Translation.Length == 0) continue;
            var (left, top, boxWidth, boxHeight) = Frame(item.Box, width, height);
            if (boxWidth <= 0) continue;
            var surface = item.Style ?? TextStyleSampler.Neutral;
            var size = Math.Max(1, item.LineHeight * height * 0.85);
            var text = new TextBlock
            {
                Text = item.Translation,
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Parse(surface.Foreground, Colors.White)),
                TextWrapping = TextWrapping.Wrap,
            };
            text.FontSize = Fit(text, size, boxWidth, boxHeight);
            var block = new Border
            {
                Width = boxWidth,
                MinHeight = boxHeight,
                Background = new SolidColorBrush(Parse(surface.Background, Colors.Black)),
                Child = text,
            };
            SetLeft(block, left);
            SetTop(block, top);
            Children.Add(block);
        }
    }

    private void AddPanel(ScreenPhoneCard.ChatPanel panel, double width, double height)
    {
        FrameworkElement view;
        double left, top;
        if (PanelFont is { } font)
        {
            var panelWidth = Math.Min(width * 0.45, font * 20);
            view = PhonePanelView.Make(panel, panelWidth, height, font, Math.Max(8, font * 0.7));
            left = (panel.Card.Box.Left + panel.Card.Box.Right) / 2 > 0.5 ? width - panelWidth : 0;
            top = 0;
        }
        else
        {
            var (x, y, w, h) = Frame(panel.Card.Box, width, height);
            view = PhonePanelView.Make(panel, w, h, panel.Card.LineHeight * height * 0.85,
                                       Math.Max(6, ScreenPhoneCard.PanelRadius * height / 1080));
            (left, top) = (x, y);
        }
        SetLeft(view, left);
        SetTop(view, top);
        Children.Add(view);
    }

    /// <summary>Kutunun alandaki yeri ve boyu (piksel); Mac GamePhoneBlocks ile aynı dönüşüm.</summary>
    private static (double Left, double Top, double Width, double Height) Frame(CouchSubs.Core.TextBox box, double width, double height) =>
        (box.Left * width, box.Top * height, Math.Max(0, box.Right - box.Left) * width, Math.Max(0, box.Bottom - box.Top) * height);

    /// <summary>Yazı boyu: balona sığana kadar en çok <see cref="MinScale"/> oranına küçülür.</summary>
    private static double Fit(TextBlock text, double size, double width, double height)
    {
        var floor = size * MinScale;
        for (var current = size; ; current = Math.Max(floor, current * 0.92))
        {
            text.FontSize = current;
            text.LineHeight = current * 1.15;
            text.Measure(new Size(width, double.PositiveInfinity));
            if (text.DesiredSize.Height <= height + 1 || current <= floor) return current;
        }
    }

    private static Color Parse(string? hex, Color fallback) =>
        hex is { Length: 7 } && hex[0] == '#'
        && int.TryParse(hex.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out var rgb)
            ? Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)
            : fallback;
}
