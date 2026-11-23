// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// GTA 6 telefonunun yanındaki sohbet paneli (Mac/iPhone PhonePanelView, Android PhonePanel, TV app.js placePanel aynı
/// çizim): yuvarlak köşeli, yarı saydam koyu kart; üstte kişinin adı, altında mesajlar sırayla (karşı taraf solda krem,
/// oyuncu sağda amber balon, not ortada). Sığmayan en eski mesajlar üstten kırpılır, son mesajlar görünür kalır. Sağ altta
/// sade kanepe simgesi.
/// </summary>
internal static class PhonePanelView
{
    public static FrameworkElement Make(ScreenPhoneCard.ChatPanel panel, double width, double height, double fontSize, double radius)
    {
        fontSize = Math.Max(8, fontSize);
        var cardStyle = panel.Card.Style;
        var foreground = Parse(cardStyle?.Foreground, Colors.White);
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        if (panel.Title is { } title)
        {
            var name = new TextBlock
            {
                Text = title.Translation,
                FontSize = fontSize * 1.05,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Parse(title.Style?.Foreground, foreground)),
                TextAlignment = TextAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(0, 0, 0, fontSize * 0.5),
            };
            Grid.SetRow(name, 0);
            grid.Children.Add(name);
        }
        var list = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
        foreach (var message in panel.Messages) list.Children.Add(Message(message, width, fontSize));
        // Sığmayan en eski mesajlar üstten kırpılır: liste alta yaslı, alan kırpılmış.
        var clip = new Border { ClipToBounds = true, Child = list };
        Grid.SetRow(clip, 1);
        grid.Children.Add(clip);
        var couch = Couch(fontSize, foreground);
        var root = new Grid();
        root.Children.Add(new Border
        {
            Width = width,
            Height = height,
            CornerRadius = new CornerRadius(radius),
            Background = new SolidColorBrush(Parse(cardStyle?.Background, Colors.Black)) { Opacity = ScreenPhoneCard.PanelOpacity },
            Padding = new Thickness(fontSize * 0.6, fontSize * 0.55, fontSize * 0.6, fontSize * 1.3),
            Child = grid,
        });
        root.Children.Add(couch);
        root.IsHitTestVisible = false;
        return root;
    }

    private static FrameworkElement Message(ScreenTranslation.Item item, double width, double fontSize)
    {
        var note = item.Panel == ScreenPhoneCard.PanelPart.Note;
        var mine = item.Panel == ScreenPhoneCard.PanelPart.Mine;
        var text = new TextBlock
        {
            Text = item.Translation,
            FontSize = note ? fontSize * 0.8 : fontSize,
            FontWeight = note ? FontWeights.Medium : FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Parse(item.Style?.Foreground, Colors.White)),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = note ? TextAlignment.Center : TextAlignment.Left,
        };
        if (note) return new Border { Margin = new Thickness(0, fontSize * 0.45, 0, 0), Child = text };
        return new Border
        {
            HorizontalAlignment = mine ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            MaxWidth = width * 0.84,
            Margin = new Thickness(0, fontSize * 0.45, 0, 0),
            Padding = new Thickness(fontSize * 0.6, fontSize * 0.32, fontSize * 0.6, fontSize * 0.32),
            CornerRadius = new CornerRadius(fontSize * 0.75),
            Background = new SolidColorBrush(Parse(item.Style?.Background, Colors.Gray)),
            Child = text,
        };
    }

    /// <summary>Sağ alttaki sade kanepe (<see cref="ScreenPhoneCard.CouchGlyph"/>, 24×16 ızgara).</summary>
    private static FrameworkElement Couch(double fontSize, Color color)
    {
        double w = fontSize * 0.9, h = fontSize * 0.6, sx = w / 24, sy = h / 16;
        var geometry = new GeometryGroup();
        foreach (var part in ScreenPhoneCard.CouchGlyph)
            geometry.Children.Add(new RectangleGeometry(new Rect(part.X * sx, part.Y * sy, part.Width * sx, part.Height * sy),
                                                        part.Radius * sx, part.Radius * sy));
        return new Path
        {
            Data = geometry,
            Fill = new SolidColorBrush(color) { Opacity = 0.35 },
            Width = w,
            Height = h,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, fontSize * 0.45, fontSize * 0.45),
        };
    }

    internal static Color Parse(string? hex, Color fallback) =>
        hex is { Length: 7 } && hex[0] == '#'
        && int.TryParse(hex.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out var rgb)
            ? Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)
            : fallback;
}
