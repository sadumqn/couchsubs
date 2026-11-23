// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Bir telefon yazı bloğunun oyundan örneklenen opak zemin ve yazı renkleri.</summary>
public sealed record PhoneTextStyle(string Background, string Foreground);

internal static class GamePhonePalette
{
    internal static readonly PhoneTextStyle Neutral = new("#24272A", "#FFFFFF");

    private readonly record struct Rgb(byte R, byte G, byte B) : IComparable<Rgb>
    {
        internal int Tone => 77 * R + 150 * G + 29 * B;
        public int CompareTo(Rgb other) => Tone.CompareTo(other.Tone);
        internal bool Near(Rgb other, int tolerance) =>
            Math.Abs(R - other.R) <= tolerance && Math.Abs(G - other.G) <= tolerance && Math.Abs(B - other.B) <= tolerance;

        // Akış sıkıştırmasının aynı yüzeyde yarattığı birkaç tonluk oynamayı bastır.
        internal Rgb Shift(int delta) => new((byte)Math.Clamp(R + delta, 0, 255), (byte)Math.Clamp(G + delta, 0, 255),
            (byte)Math.Clamp(B + delta, 0, 255));
        internal string Hex => $"#{Round(R):X2}{Round(G):X2}{Round(B):X2}";
        private static int Round(byte value) => Math.Min(255, (value + 4) / 8 * 8);
    }

    internal static PhoneTextStyle Sample(Frame frame, TextBox box)
    {
        if (frame.Width < 1 || frame.Height < 1 || !(box.Left < box.Right && box.Top < box.Bottom)) return Neutral;
        int left = (int)(Math.Clamp(box.Left, 0, 1) * frame.Width);
        int top = (int)(Math.Clamp(box.Top, 0, 1) * frame.Height);
        int width = (int)Math.Ceiling(Math.Clamp(box.Right, 0, 1) * frame.Width) - left;
        int height = (int)Math.Ceiling(Math.Clamp(box.Bottom, 0, 1) * frame.Height) - top;
        if (width < 3 || height < 2) return Neutral;

        const int rows = 5, cols = 9, count = rows * cols;
        Span<Rgb> colors = stackalloc Rgb[count];

        for (int row = 0; row < rows; row++)
        {
            int y = top + (2 * row + 1) * height / (2 * rows);
            for (int col = 0; col < cols; col++)
            {
                // Satırlar şaşırtmalı; harflerin aynı dikey çizgisine üst üste örnek düşmesin.
                int x = left + (4 * col + 1 + 2 * (row % 2)) * width / (4 * cols);
                int index = y * frame.Stride + 4 * x;
                int i = row * cols + col;
                colors[i] = new Rgb(frame.Pixels[index + 2], frame.Pixels[index + 1], frame.Pixels[index]);
            }
        }
        // Küçük harflerde kenar yumuşatma pikselleri salt kanal medyanını yanıltır. Aynı renkteki en geniş
        // kümeyi kullan; komşu yüzey veya videodan gelen dağınık renkler zemini boyamasın.
        Rgb center = default;
        int most = 0;
        foreach (var candidate in colors)
        {
            int neighbors = 0;
            foreach (var pixel in colors)
                if (candidate.Near(pixel, 20)) neighbors++;
            if (neighbors > most) (center, most) = (candidate, neighbors);
        }
        if (most * 100 < count * 45) return Neutral;
        int r = 0, g = 0, b = 0;
        foreach (var pixel in colors)
            if (center.Near(pixel, 20)) { r += pixel.R; g += pixel.G; b += pixel.B; }
        var surface = new Rgb((byte)(r / most), (byte)(g / most), (byte)(b / most));

        colors.Sort();
        var dark = colors[2];
        var light = colors[^3];
        var ink = surface.Tone - dark.Tone > light.Tone - surface.Tone ? dark : light;
        // Zemin az farkla çoğunluktaysa diğer piksellerin çoğu harf kenarındaki ara tonlar olmalı.
        if (most * 5 < count * 3 && !TwoColorSurface(colors, surface, ink)) return Neutral;
        string background = surface.Hex;
        string foreground = ink.Hex;
        int inkSamples = 0;
        foreach (var pixel in colors)
            if (ink.Near(pixel, 24)) inkSamples++;
        if (inkSamples < 3 || DesignTokens.Contrast(background, foreground) < 4.5)
        {
            foreground = ink.Tone > surface.Tone ? "#FFFFFF" : "#000000";
            if (DesignTokens.Contrast(background, foreground) < 4.5)
            {
                // Aynı mavi balondaki beyaz harfler renk eşiğinde siyaha dönmesin. Bir renk kademesi yeterliyse
                // yüzeyin tonunu hafifçe düzelt; yetmezse karşıt yazı rengini kullan.
                string adjusted = surface.Shift(foreground == "#FFFFFF" ? -8 : 8).Hex;
                if (DesignTokens.Contrast(adjusted, foreground) >= 4.5) background = adjusted;
                else foreground = foreground == "#FFFFFF" ? "#000000" : "#FFFFFF";
            }
        }
        return new PhoneTextStyle(background, foreground);
    }

    private static bool TwoColorSurface(ReadOnlySpan<Rgb> colors, Rgb surface, Rgb ink)
    {
        int r = ink.R - surface.R, g = ink.G - surface.G, b = ink.B - surface.B;
        int lengthSquared = r * r + g * g + b * b;
        if (lengthSquared == 0) return false;
        int matching = 0;
        foreach (var c in colors)
        {
            double t = Math.Clamp(((c.R - surface.R) * r + (c.G - surface.G) * g + (c.B - surface.B) * b)
                / (double)lengthSquared, 0, 1);
            if (Math.Abs(c.R - surface.R - t * r) <= 24 && Math.Abs(c.G - surface.G - t * g) <= 24
                && Math.Abs(c.B - surface.B - t * b) <= 24) matching++;
        }
        return matching * 5 >= colors.Length * 4;
    }
}