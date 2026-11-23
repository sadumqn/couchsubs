// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// Konuşan adını renklendir (bilgisayar ekranındaki pencere ve yayın penceresi): "Mattia: …" satırında yalnız ad o
/// konuşanın renginde, cümle yazı renginde (<see cref="SpeakerColors"/>; TV'deki ile aynı). Ad yoksa ya da ayar kapalıysa düz metin.
/// </summary>
internal static class SpeakerText
{
    /// <param name="shown">Ekrana yazılacak (sarılmış) metin.</param>
    /// <param name="source">Satırın özgün metni; konuşan adları buradan çıkarılır.</param>
    /// <param name="alpha">Renkli parçaların saydamlığı (yayın penceresinde soluk üst satırlar için).</param>
    /// <param name="nameOnly">Konuşan rengi yalnız adı boyar (yeni arayüz, <c>style.nameOnly</c>); satırın geri kalanı yazı renginde.</param>
    public static void Fill(TextBlock block, string shown, string source, bool enabled, SpeakerColorBook book, byte alpha = 255, bool nameOnly = false)
    {
        var names = enabled ? SpeakerColors.Speakers(source) : [];
        if (names.Count == 0)
        {
            block.Text = shown;
            return;
        }
        block.Inlines.Clear();
        foreach (var segment in SpeakerColors.Segments(shown, names, book.Color))
        {
            var brush = segment.Color is { } hex ? new SolidColorBrush(Parse(hex, alpha)) : null;
            if (nameOnly && brush is not null && names.FirstOrDefault(name => segment.Text.StartsWith(name, StringComparison.Ordinal)) is { } speaker)
            {
                // Yalnız ad (ve ardındaki iki nokta) renkli.
                var end = speaker.Length;
                while (end < segment.Text.Length && segment.Text[end] is ':' or '：') end++;
                block.Inlines.Add(new Run(segment.Text[..end]) { Foreground = brush });
                AddPlain(block, segment.Text[end..]);
                continue;
            }
            var parts = segment.Text.Split('\n');
            for (var index = 0; index < parts.Length; index++)
            {
                if (index > 0) block.Inlines.Add(new LineBreak());
                if (parts[index].Length == 0) continue;
                var run = new Run(parts[index]);
                if (brush is not null) run.Foreground = brush;
                block.Inlines.Add(run);
            }
        }
    }

    private static void AddPlain(TextBlock block, string text)
    {
        var parts = text.Split('\n');
        for (var index = 0; index < parts.Length; index++)
        {
            if (index > 0) block.Inlines.Add(new LineBreak());
            if (parts[index].Length > 0) block.Inlines.Add(new Run(parts[index]));
        }
    }

    /// <summary>"#RRGGBB" → renk (bozuksa beyaz).</summary>
    public static Color Rgb(string hex, byte alpha = 255) => hex is { Length: 7 } && hex[0] == '#' ? Parse(hex, alpha) : Color.FromArgb(alpha, 255, 255, 255);

    private static Color Parse(string hex, byte alpha) => Color.FromArgb(alpha,
        Convert.ToByte(hex.Substring(1, 2), 16), Convert.ToByte(hex.Substring(3, 2), 16), Convert.ToByte(hex.Substring(5, 2), 16));
}
