// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Bir bölgeyi tek seferlik okuyup çevirir. Görev ya da bilgi paneli gibi, altyazı gibi akıp gitmeyen
/// yazılar içindir: bölge sürekli taranmaz, kullanıcı bir tuşa basınca bir kez okunur.
/// </summary>
public static class RegionTranslation
{
    /// <param name="Source">Okunan yazı (paragraflara ayrılmış).</param>
    /// <param name="Translation">Aynı paragrafların çevirisi.</param>
    /// <param name="Box">Yazının karedeki yeri, kenarlara oranla; TV çeviriyi buraya yerleştirir.</param>
    public sealed record Result(string Source, string Translation, TextBox Box);

    /// <summary>Bölgede yazı yoksa null döner. Çevirmen kullanılamıyorsa <see cref="TranslatorException"/> fırlatır.</summary>
    public static async Task<Result?> TranslateOnceAsync(
        Frame frame, CropRegion region, ITextReader reader, ITextTranslator translator, CancellationToken cancellationToken = default)
    {
        var area = RegionCropper.Crop(frame, region);
        // Tek okuma olduğu için "derin" okuma açık: boş görünen bölgede büyütülmüş okuma da denenir.
        var reading = (await Task.Run(() => reader.ReadLines(area, true), cancellationToken).ConfigureAwait(false)).WithoutButtonPrompts();
        if (reading.Lines.Count == 0) return null;

        var whole = new TextBox(region.Left, region.Top, region.Right, region.Bottom);
        var box = reading.Box?.PlacedIn(whole) ?? whole;
        var paragraphs = Paragraphs(reading);
        var translated = new List<string>(paragraphs.Count);
        foreach (var paragraph in paragraphs)
            translated.Add(await translator.TranslateAsync(paragraph, cancellationToken).ConfigureAwait(false));
        return new Result(string.Join('\n', paragraphs), string.Join('\n', translated), box);
    }

    /// <summary>
    /// Satırları paragraflara toplar. Bir cümle iki satıra bölünmüş olabilir; noktalamayla bitmeyen satır
    /// bir sonrakiyle birleşir. Satırlar arasında belirgin bir boşluk varsa ya da önceki satır cümleyi bitirdiyse yeni paragraf başlar.
    /// </summary>
    public static IReadOnlyList<string> Paragraphs(Reading reading)
    {
        var result = new List<string>();
        TextLine? previous = null;
        var current = new System.Text.StringBuilder();
        foreach (var line in reading.Lines)
        {
            var text = line.Text.Trim();
            if (text.Length == 0) continue;
            if (previous is not null && current.Length > 0)
            {
                if (SubtitleStabilizer.EndsSentence(previous.Text) || GapBetween(previous, line))
                {
                    result.Add(current.ToString());
                    current.Clear();
                }
                else
                {
                    current.Append(' ');
                }
            }
            current.Append(text);
            previous = line;
        }
        if (current.Length > 0) result.Add(current.ToString());
        return result;
    }

    /// <summary>İki satır arasındaki boşluk satır yüksekliğinden belirgin büyükse (kutular biliniyorsa) ayrı paragraflardır.</summary>
    private static bool GapBetween(TextLine upper, TextLine lower)
    {
        if (upper.Box is not { } a || lower.Box is not { } b) return false;
        var height = a.Bottom - a.Top;
        return height > 0 && (b.Top - a.Bottom) > height * 0.8;
    }

    /// <summary>Çevirinin TV'de kalma süresi (ms): uzun panel yazısı okunacak kadar durur.</summary>
    public static int DisplayMilliseconds(string text) => Math.Clamp(4000 + (text.Length * 70), 6000, 25000);
}
