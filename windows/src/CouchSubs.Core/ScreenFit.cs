// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde ve boyunda çizilsin, simgeleri örtmesin
/// (Mac: CouchSubsCore/ScreenFit.swift, Android: ScreenFit.kt; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
/// <list type="bullet">
/// <item><see cref="ScreenTranslation.Item.Room"/>: kutunun genişleyebileceği yatay alan. Özgün yazının iki yanında, zeminden
/// belirgin ayrılan ilk noktaya (kumanda simgesi, menü simgesi, fotoğraf, başka yazı) kadar, araya satır yüksekliğinin çeyreği
/// boşluk bırakılarak; aynı satırdaki komşu öğeyle arası ortadan bölünür. Kutu bu alanın dışına hiç taşmaz.</item>
/// <item>Kutu yalnız yazının noktalarını kapsar: ucundaki ayrı duran küçük leke simgedir, kutunun dışında kalır.</item>
/// <item>Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa hepsi sağa yaslı, sol kenarları aynıysa sola; aynı
/// satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalı.</item>
/// <item>Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda (#859).</item>
/// </list>
/// </summary>
public static class ScreenFit
{
    public const double GapLines = 0.25;
    public const double GrowLines = 8.0;
    public const double SameLine = 0.15;
    public const int InkDistance = 56;

    /// <summary>Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi.</summary>
    public static IReadOnlyList<ScreenTranslation.Item> Fitted(IReadOnlyList<ScreenTranslation.Item> items, Frame? frame)
    {
        if (frame is null || frame.Width <= 0 || frame.Height <= 0 || !frame.IsConsistent) return items;
        var aspect = (double)frame.Width / frame.Height;
        var laid = Uniform(Aligned(Tightened(items, frame, aspect), aspect), aspect);
        return WithRoom(laid, aspect, (x, y) =>
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2], frame.Pixels[p + 1], frame.Pixels[p]);
        }, frame.Width, frame.Height);
    }

    internal static bool TakesPart(ScreenTranslation.Item item) =>
        item.Look is not null && !ScreenTranslation.IsCardPart(item) && !item.Bubble;

    private static double Height(TextBox box) => box.Bottom - box.Top;

    private static double RowOverlap(TextBox a, TextBox b) =>
        Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Top, b.Top)) / Math.Max(1e-9, Math.Min(Height(a), Height(b)));

    internal static List<ScreenTranslation.Item> Tightened(IReadOnlyList<ScreenTranslation.Item> items, Frame frame, double aspect)
    {
        var result = items.ToList();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (!TakesPart(item) || item.Icons is { Count: > 0 }) continue;
            var box = item.Box;
            var lineX = item.LineHeight / aspect;
            var spans = ScreenTranslation.InkSpans(frame, box, 0.6 * lineX);
            if (spans.Count < 2) continue;
            double left = box.Left, right = box.Right;
            if (spans[^1].Right - spans[^1].Left <= 1.5 * lineX) right = spans[^2].Right;
            if (spans[0].Right - spans[0].Left <= 1.5 * lineX && (spans.Count >= 3 || right == box.Right)) left = spans[1].Left;
            if (right - left < 0.5 * (box.Right - box.Left)) continue;
            result[i] = item with { Box = new TextBox(left, box.Top, right, box.Bottom) };
        }
        return result;
    }

    internal static List<ScreenTranslation.Item> Aligned(IReadOnlyList<ScreenTranslation.Item> items, double aspect)
    {
        var labels = Enumerable.Range(0, items.Count).Where(i => TakesPart(items[i]) && items[i].Rows <= 1).ToList();
        var result = items.ToList();
        foreach (var i in labels)
        {
            var box = items[i].Box;
            var tolerance = 0.5 * items[i].LineHeight / aspect;
            var column = labels.Where(j => j != i && RowOverlap(box, items[j].Box) == 0
                && Math.Abs((box.Top + box.Bottom) - (items[j].Box.Top + items[j].Box.Bottom)) / 2 <= 8 * items[i].LineHeight).ToList();
            var rights = column.Count(j => Math.Abs(items[j].Box.Right - box.Right) <= tolerance && Math.Abs(items[j].Box.Left - box.Left) > tolerance);
            var lefts = column.Count(j => Math.Abs(items[j].Box.Left - box.Left) <= tolerance && Math.Abs(items[j].Box.Right - box.Right) > tolerance);
            var row = labels.Count(j => j != i && RowOverlap(box, items[j].Box) >= 0.5);
            var align = rights >= 2 && rights > lefts ? "right" : lefts >= 2 ? "left" : row >= 2 ? "center" : null;
            if (align is not null) result[i] = result[i] with { Look = result[i].Look! with { Align = align } };
        }
        return result;
    }

    internal static List<ScreenTranslation.Item> Uniform(IReadOnlyList<ScreenTranslation.Item> items, double aspect)
    {
        var labels = Enumerable.Range(0, items.Count).Where(i => TakesPart(items[i]) && items[i].Rows <= 1).ToList();
        var parent = labels.ToDictionary(i => i, i => i);
        int Root(int i) { while (parent[i] != i) i = parent[i]; return i; }
        foreach (var a in labels)
            foreach (var b in labels.Where(b => b > a))
            {
                var x = items[a];
                var y = items[b];
                if (x.Look!.Upper != y.Look!.Upper || x.Look.Bold != y.Look.Bold
                    || Math.Abs(x.LineHeight - y.LineHeight) > SameLine * Math.Max(x.LineHeight, y.LineHeight)) continue;
                var tolerance = 0.5 * Math.Max(x.LineHeight, y.LineHeight) / aspect;
                var sameRow = RowOverlap(x.Box, y.Box) >= 0.5;
                var sameColumn = (Math.Abs(x.Box.Left - y.Box.Left) <= tolerance || Math.Abs(x.Box.Right - y.Box.Right) <= tolerance)
                    && Math.Abs(x.Box.Top - y.Box.Top) <= 3 * Math.Max(x.LineHeight, y.LineHeight);
                if (sameRow || sameColumn) parent[Root(a)] = Root(b);
            }
        var result = items.ToList();
        foreach (var members in labels.GroupBy(Root).Where(g => g.Count() >= 2))
        {
            var lines = members.Select(i => items[i].LineHeight).Order().ToList();
            var median = lines[lines.Count / 2];
            foreach (var i in members) result[i] = result[i] with { LineHeight = median };
        }
        return result;
    }

    /// <summary>Her öğenin genişleyebileceği yatay alan. <paramref name="color"/>: karenin noktası (kırmızı, yeşil, mavi).</summary>
    internal static List<ScreenTranslation.Item> WithRoom(IReadOnlyList<ScreenTranslation.Item> items, double aspect,
        Func<int, int, (int R, int G, int B)> color, int frameWidth, int frameHeight)
    {
        var result = items.ToList();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (!TakesPart(item)) continue;
            var box = item.Box;
            var lineX = item.LineHeight / aspect;
            var gap = GapLines * lineX;
            double left = Math.Max(0, box.Left - (GrowLines * lineX)), right = Math.Min(1, box.Right + (GrowLines * lineX));
            for (var j = 0; j < items.Count; j++)
            {
                var other = items[j].Box;
                if (j == i || RowOverlap(box, other) < 0.3) continue;
                if (other.Left >= box.Right - 1e-9) right = Math.Min(right, (box.Right + other.Left) / 2);
                if (other.Right <= box.Left + 1e-9) left = Math.Max(left, (other.Right + box.Left) / 2);
            }
            if (item.Style is { } style && DesignTokens.Rgb(style.Background) is { } rgb)
            {
                var background = ((int)(rgb.R * 255), (int)(rgb.G * 255), (int)(rgb.B * 255));
                var y0 = (int)Math.Round((box.Top + (0.2 * Height(box))) * frameHeight, MidpointRounding.AwayFromZero);
                var y1 = (int)Math.Round((box.Bottom - (0.2 * Height(box))) * frameHeight, MidpointRounding.AwayFromZero);
                var rows = new List<int>();
                for (var y = y0; y <= Math.Max(y0, y1); y += Math.Max(1, (y1 - y0) / 6)) rows.Add(Math.Clamp(y, 0, frameHeight - 1));
                double? Scan(double start, double end)
                {
                    int a = (int)Math.Round(start * frameWidth, MidpointRounding.AwayFromZero), b = (int)Math.Round(end * frameWidth, MidpointRounding.AwayFromZero);
                    if (a == b) return null;
                    var step = b > a ? 1 : -1;
                    var ground = background;
                    for (var x = a; x != b; x += step)
                    {
                        if (x < 0 || x >= frameWidth) continue;
                        var far = 0;
                        int r = 0, g = 0, bl = 0;
                        foreach (var y in rows)
                        {
                            var c = color(x, y);
                            far = Math.Max(far, Math.Max(Math.Abs(c.R - ground.Item1), Math.Max(Math.Abs(c.G - ground.Item2), Math.Abs(c.B - ground.Item3))));
                            r += c.R; g += c.G; bl += c.B;
                        }
                        if (far > InkDistance) return (double)x / frameWidth;
                        var n = rows.Count;
                        ground = (((ground.Item1 * 7) + (r / n)) / 8, ((ground.Item2 * 7) + (g / n)) / 8, ((ground.Item3 * 7) + (bl / n)) / 8);
                    }
                    return null;
                }
                var edge = 2.0 / frameWidth;
                if (Scan(box.Right + edge, right) is { } inkRight) right = Math.Min(right, inkRight - gap);
                if (Scan(box.Left - edge, left) is { } inkLeft) left = Math.Max(left, inkLeft + gap);
            }
            result[i] = item with { Room = new TextBox(Math.Min(box.Left, left), box.Top, Math.Max(box.Right, right), box.Bottom) };
        }
        return result;
    }

    // --- Çizicilerin ortak satır yerleşimi (TV fitStyled ile aynı sıra; Mac/iPhone ve Android ile aynı) ---

    /// <summary>Bir çevirinin çizimi: satırları, yalnız yatay ölçeği ve yazının alanının yeri (piksel).</summary>
    public sealed record Lines(IReadOnlyList<string> Rows, double Squeeze, double Left, double Width);

    public const double FirstSqueeze = 0.8;
    public const double MinSqueeze = 0.7;

    /// <summary>
    /// Çeviriyi özgün yazının alanına yerleştirir; yazı boyu hiç değişmez. <paramref name="measure"/>: yazının çizicinin
    /// kendi yazı tipiyle, sabit boyda genişliği (piksel). <paramref name="room"/>: genişleyebileceği alan (piksel), yoksa
    /// kutunun kendisi. <paramref name="rows"/>: özgün satır sayısı; tek satırlık uzun yazı son çare olarak satıra iner.
    /// </summary>
    public static Lines Layout(string text, double left, double width, (double Left, double Right)? room, int rows, string align,
                               Func<string, double> measure)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        IReadOnlyList<string> lines = text.Split('\n');
        var count = Math.Max(rows, lines.Count);
        if (lines.Count == 1 && (count > 1 || (words.Length > 2 && measure(text) > width / MinSqueeze)))
        {
            var cap = count > 1 ? count : int.MaxValue;
            var target = Math.Max(width / FirstSqueeze, measure(text) / Math.Max(1, count));
            var made = new List<string>();
            var current = "";
            foreach (var word in words)
            {
                var next = current.Length == 0 ? word : current + " " + word;
                if (current.Length > 0 && measure(next) > target && made.Count < cap - 1) { made.Add(current); current = word; }
                else current = next;
            }
            if (current.Length > 0) made.Add(current);
            lines = made;
        }
        var widest = lines.Count == 0 ? 0 : lines.Max(measure);
        double a = left, b = left + width;
        var r0 = Math.Min(left, room?.Left ?? left);
        var r1 = Math.Max(left + width, room?.Right ?? left + width);
        var squeeze = widest > 0 ? Math.Min(1, (b - a) / widest) : 1;
        if (squeeze < FirstSqueeze)
        {
            var extra = (widest * FirstSqueeze) - (b - a);
            var l = align == "right" ? extra : align == "center" ? extra / 2 : 0;
            var r = extra - l;
            double freeL = a - r0, freeR = r1 - b;
            if (r > freeR) { l += r - freeR; r = freeR; }
            if (l > freeL) { r = Math.Min(freeR, r + l - freeL); l = freeL; }
            a -= l;
            b += r;
            squeeze = Math.Max(MinSqueeze, Math.Min(1, (b - a) / widest));
        }
        return new Lines(lines, squeeze, a, b - a);
    }
}
