// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;
using CouchSubs.Core;

namespace CouchSubs.Translation;

/// <summary>
/// Satırı oyun paketinde arar (Mac: CouchSubsCore/GamePacks.swift, PackLookup). Sırayla: satırın tamamı; konuşmacı
/// etiketi ("ENZO: ") ya da diyalog tiresi varsa onsuz hâli (etiket çeviriye eklenir); birden çok satırsa her satır ayrı
/// ayrı; birden çok cümleyse her cümle ayrı ayrı. Parçalı aramada parçaların hepsi bulunmalıdır, yoksa satır motorla
/// çevrilir. Etiket ve ayraçlar ücretli motorlardaki gibi korunur (<see cref="SubtitleSegmenter"/>). Tam anahtarla hiçbir
/// yol tutmazsa aynı sıra bir kez daha denenir; bu kez her parça önce tam, sonra <c>nearest</c> ile (OCR hatalarına
/// dayanıklı) aranır.
/// </summary>
public static class PackLookup
{
    /// <summary>Kütüphanedeki paketlerde arar (bulanık arama oynanan oyunun paketinde).</summary>
    public static PackMatch? Match(GamePackLibrary library, string text)
    {
        // Aynı parça bir aramada birkaç yoldan sorulabilir (etiketli/etiketsiz gövde aynı); bulanık sonuç bir kez hesaplanır.
        var asked = new Dictionary<string, string?>();
        return Match(text, library.Find, line => asked.TryGetValue(line, out var known) ? known : asked[line] = library.Nearest(line));
    }

    /// <param name="find">Tek bir metnin (tamamının) paketteki Türkçesi.</param>
    /// <param name="nearest">Tam anahtar yoksa en benzer satırın Türkçesi (bulanık arama); verilmezse yapılmaz.</param>
    public static PackMatch? Match(string text, Func<string, string?> find, Func<string, string?>? nearest = null)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return null;
        if (Phase(trimmed, find) is { } exact) return exact;
        return nearest is null ? null : Phase(trimmed, line => find(line) ?? nearest(line));
    }

    private static PackMatch? Phase(string trimmed, Func<string, string?> find)
    {
        if (Single(trimmed, find) is { } whole) return Result(whole.Pieces, whole.Translations);

        // Her satır ayrı bir altyazı olabilir (iki konuşmacı alt alta).
        var lines = trimmed.Replace("\r\n", "\n").Split('\n').Select(line => line.Trim()).Where(line => line.Length > 0).ToList();
        if (lines.Count > 1)
        {
            var pieces = new List<SubtitleSegmenter.Piece>();
            var translations = new List<string?>();
            var all = true;
            foreach (var line in lines)
            {
                if (Single(line, find) is not { } found) { all = false; break; }
                if (pieces.Count > 0)
                {
                    pieces.Add(new SubtitleSegmenter.Piece("\n", false));
                    translations.Add(null);
                }
                pieces.AddRange(found.Pieces);
                translations.AddRange(found.Translations);
            }
            if (all) return Result(pieces, translations);
        }

        // Cümle cümle (etiket, tire ve ayraçlar olduğu gibi kalır).
        var split = SubtitleSegmenter.Split(trimmed);
        if (split.Count(piece => piece.Translate) <= 1) return null;
        var sentences = new List<string?>(split.Count);
        foreach (var piece in split)
        {
            if (!piece.Translate) { sentences.Add(null); continue; }
            if (find(piece.Text) is not { } turkish) return null;
            sentences.Add(turkish);
        }
        return Result(split, sentences);
    }

    /// <summary>
    /// Tek satır: başında konuşmacı etiketi ya da diyalog tiresi varsa ("- ENZO: ") önce onlarsız hâli, sonra tamamı,
    /// sonra OCR'ın bozduğu etiketsiz hâli (<see cref="LooseLabel"/>).
    /// </summary>
    private static (List<SubtitleSegmenter.Piece> Pieces, List<string?> Translations)? Single(string line, Func<string, string?> find)
    {
        var split = SubtitleSegmenter.Split(line);
        var lead = split.TakeWhile(piece => !piece.Translate).ToList();
        if (lead.Count > 0 && lead.Count < split.Count && !split.Any(piece => piece.Text == "\n"))
        {
            var body = string.Concat(split.Skip(lead.Count).Select(piece => piece.Text));
            if (find(body) is { } turkish)
                return ([.. lead, new(body, true)], [.. Enumerable.Repeat<string?>(null, lead.Count), turkish]);
        }
        if (find(line) is { } whole) return ([new(line, true)], [whole]);
        if (LooseLabel(line) is not { } loose || find(loose.Body) is not { } found) return null;
        return ([new(loose.Label, false), new(loose.Body, true)], [null, found]);
    }

    /// <summary>
    /// OCR'ın bozduğu konuşmacı etiketi: "-GAETANO:", "M]:", "li LUCA:", "MİNE GUARD•" (ilk 32 karakterde iki nokta ya da
    /// • ve önündeki sözcükte küçük harf yok) ya da iki noktasız "SEBASTIAN Where…" (en çok üç büyük harfli sözcük, ardından
    /// büyük harfle başlayan küçük harfli sözcük). (ekranda kalacak etiket, aranacak gövde) ya da null. Yalnız paket
    /// aramasında yeniden deneme içindir.
    /// </summary>
    internal static (string Label, string Body)? LooseLabel(string line)
    {
        var runes = line.EnumerateRunes().ToList();
        string Text(int start, int end)
        {
            var builder = new StringBuilder();
            for (var index = start; index < end; index++) builder.Append(runes[index].ToString());
            return builder.ToString();
        }
        static bool NameLike(string token, int minimum)
        {
            var letters = token.EnumerateRunes().Where(Rune.IsLetter).ToList();
            return letters.Count >= minimum && !letters.Any(Rune.IsLower);
        }
        for (var index = 1; index < Math.Min(runes.Count, 33); index++)
        {
            if (runes[index].Value is not (':' or '•')) continue;
            var tokens = Text(0, index).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (tokens.Length == 0 || !NameLike(tokens[^1], 1)) continue;
            var start = index + 1;
            while (start < runes.Count && !Rune.IsLetter(runes[start]) && !Rune.IsNumber(runes[start])) start++;
            var body = Text(start, runes.Count).Trim();
            if (!body.EnumerateRunes().Any(Rune.IsLetter)) return null;
            return (Text(0, index + 1).Trim() + " ", body);
        }
        var position = 0;
        while (position < runes.Count && !Rune.IsLetter(runes[position])) position++;
        for (var word = 0; word < 3; word++)
        {
            var end = position;
            while (end < runes.Count && !Rune.IsWhiteSpace(runes[end])) end++;
            if (end >= runes.Count || !Rune.IsUpper(runes[position]) || !NameLike(Text(position, end), 2)) break;
            while (end < runes.Count && Rune.IsWhiteSpace(runes[end])) end++;
            position = end;
            if (position + 1 < runes.Count && Rune.IsUpper(runes[position]) && Rune.IsLower(runes[position + 1]))
                return (Text(0, position).Trim() + " ", Text(position, runes.Count).Trim());
        }
        return null;
    }

    private static PackMatch Result(IReadOnlyList<SubtitleSegmenter.Piece> pieces, IReadOnlyList<string?> translations)
    {
        var text = string.Concat(pieces.Select((piece, index) => translations[index] ?? piece.Text));
        return new PackMatch(text, SpeechScript.Lines(pieces, translations));
    }
}
