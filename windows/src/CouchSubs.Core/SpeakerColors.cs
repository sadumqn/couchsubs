// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Konuşan adını renklendir: "Mattia: …" satırında yalnız ad ("Mattia:") o konuşana özgü renkte görünür, cümle
/// kullanıcının seçtiği yazı renginde kalır; aynı ad hep aynı renktir. Renk addan hesaplanır (büyük/küçük harf fark
/// etmez): FNV-1a (32 bit, UTF-16 birimleri) → 10 renklik palet. Mac/iPhone (SpeakerColors.swift), Android
/// (SpeakerColors.kt) ve TV uygulaması aynı paleti ve aynı hesabı kullanır. TV'ye <c>subtitle</c> olayının
/// <c>speakerNames</c> alanıyla gider (0.9.79'dan eski TV uygulamaları eski <c>speakers</c> alanıyla bütün satırı boyuyordu;
/// yeni alanı tanımaz, tek renk gösterir).
/// </summary>
public static class SpeakerColors
{
    /// <summary>Koyu zeminde okunaklı, birbirinden ayrılan renkler (beyaz yok: renksiz satır beyazdır).</summary>
    public static readonly IReadOnlyList<string> Palette =
    [
        "#FFD54F", "#4FC3F7", "#81C784", "#FF8A65", "#CE93D8", "#F06292", "#4DD0E1", "#AED581", "#FFB74D", "#90CAF9",
    ];

    /// <summary>Adın rengi ("#RRGGBB").</summary>
    public static string Color(string name) => Palette[(int)(Hash(name.Trim().ToLowerInvariant()) % (uint)Palette.Count)];

    /// <summary>FNV-1a (32 bit), UTF-16 birimleri üzerinde.</summary>
    public static uint Hash(string key)
    {
        var hash = 2166136261u;
        foreach (var unit in key)
        {
            hash ^= unit;
            hash = unchecked(hash * 16777619u);
        }
        return hash;
    }

    /// <summary>Metnin satır başlarındaki konuşan adları (<see cref="SpeakerPrefix.Parse"/>), ilk görülme sırasıyla, tekrarsız.</summary>
    public static IReadOnlyList<string> Speakers(string text) =>
        [.. text.Split('\n').Select(line => SpeakerPrefix.Parse(line)?.Name).OfType<string>().Distinct()];

    /// <summary>Gösterilecek metnin bir parçası; <see cref="Color"/> null ise öntanımlı renkte.</summary>
    public readonly record struct Segment(string Text, string? Color);

    /// <summary>
    /// Bölünmüş (satırlara sarılmış) metni parçalara ayırır: <paramref name="names"/>'ten biri satır başında "Ad:" ile
    /// başlıyorsa yalnız "Ad:" o adın rengindedir; cümle ve devam satırları renksizdir, kullanıcının seçtiği yazı renginde
    /// kalır (önceden bütün satır renkleniyor, "Yazı rengi" beyazken altyazı renkli görünüyordu). Ad yoksa tek renksiz parça.
    /// </summary>
    /// <param name="colorOf">Adın rengi (oturumun <see cref="SpeakerColorBook"/>'u); verilmezse <see cref="Color"/>.</param>
    public static IReadOnlyList<Segment> Segments(string text, IReadOnlyList<string> names, Func<string, string?>? colorOf = null)
    {
        if (names.Count == 0) return [new Segment(text, null)];
        var result = new List<Segment>();
        var start = 0;
        var lineStart = 0;
        while (lineStart <= text.Length)
        {
            var found = names.Where(name => NameEnd(text, lineStart, name) > 0).OrderByDescending(name => name.Length).FirstOrDefault();
            if (found is not null)
            {
                var end = NameEnd(text, lineStart, found);
                if (lineStart > start) result.Add(new Segment(text[start..lineStart], null));
                result.Add(new Segment(text[lineStart..end], colorOf is null ? Color(found) : colorOf(found)));
                start = end;
            }
            var next = text.IndexOf('\n', lineStart);
            if (next < 0) break;
            lineStart = next + 1;
        }
        if (start < text.Length) result.Add(new Segment(text[start..], null));
        return result;
    }

    /// <summary>Satır <paramref name="at"/>'te "Ad:" ile başlıyorsa iki noktadan sonraki konum; değilse 0.</summary>
    private static int NameEnd(string text, int at, string name)
    {
        if (string.CompareOrdinal(text, at, name, 0, name.Length) != 0) return 0;
        var rest = at + name.Length;
        if (rest < text.Length && text[rest] == ' ') rest++;
        return rest < text.Length && text[rest] is ':' or '：' ? rest + 1 : 0;
    }
}
