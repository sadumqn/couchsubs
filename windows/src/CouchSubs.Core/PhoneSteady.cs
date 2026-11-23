// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Otomatik telefon okumasında çevirinin kararlılığı. Aynı mesajın OCR'la bir iki harfi farklı okunuşu yeni mesaj
/// sayılıyor, balon bir an özgün diline dönüp yeniden çevriliyor, çeviri her seferinde biraz değişiyordu; telefon tek
/// karede bulunamayınca da bütün çeviriler silinip geri geliyordu ("sürekli git gel yapıyor", X'teki bildirim). Mac/iPhone
/// (PhoneSteady.swift) ve Android (PhoneSteady.kt) aynı eşikleri kullanır.
/// </summary>
internal static class PhoneSteady
{
    /// <summary>Telefon art arda bu kadar turda bulunamazsa ya da okuma doğrulanamazsa çeviriler silinir.</summary>
    internal const int MissTurns = 3;
    /// <summary>Tek turluk OCR sapması (düşen balon, yan yana bozuk harfler) en çok bu kadar tur bekletilir.</summary>
    internal const int HoldTurns = 2;
    /// <summary>Aynı mesaj sayılmak için sadeleştirilmiş iki okumanın benzerliği (Levenshtein oranı) en az bu.</summary>
    internal const double SameMessage = 0.9;
    /// <summary>Kısa satırda bir harf anlamı değiştirir ("Ok" / "On"): benzer okuma yalnız bu kadar harften uzun mesajda kullanılır.</summary>
    internal const int MinimumLetters = 8;

    /// <summary>
    /// Mesajın bilinen çevirisi: birebir aynı okunuşunki, yoksa aynı mesajın OCR'la biraz farklı okunuşununki. Sayı ya da
    /// olumsuzluk ekleyen/düşüren okuma ("at 5" / "at 6", "can" / "can't") aynı mesaj sayılmaz. Birden çok aday varsa
    /// uzunluğu en yakın olan, eşitlikte sıralamada önce gelen (her platformda aynı sonuç).
    /// </summary>
    internal static string? Translation(string source, IReadOnlyDictionary<string, string> known)
    {
        if (known.TryGetValue(source, out var exact)) return exact;
        var text = TextMatch.Normalize(source);
        (int Distance, string Source, string Translation)? best = null;
        foreach (var (old, translation) in known)
        {
            if (!SameReading(source, old)) continue;
            var distance = Math.Abs(text.Length - TextMatch.Normalize(old).Length);
            if (best is not { } current || distance < current.Distance
                || (distance == current.Distance && string.CompareOrdinal(old, current.Source) < 0))
                best = (distance, old, translation);
        }
        return best?.Translation;
    }

    /// <summary>
    /// İki okuma aynı mesaj mı: birebir aynı, sadeleştirilmiş hali aynı (soru işareti ikisinde de ya da hiçbirinde; "Ok." /
    /// "ok" kısa satırda da aynı mesaj) ya da (en az <see cref="MinimumLetters"/> harfli iki uzun mesajda, "rn" / "m"
    /// birleştirilerek) Levenshtein oranı en az <see cref="SameMessage"/>; sayı ya da olumsuzluk ekleyen/düşüren okuma aynı
    /// sayılmaz (Mac ile aynı).
    /// </summary>
    internal static bool SameReading(string a, string b)
    {
        if (a == b) return true;
        string x = TextMatch.Normalize(a), y = TextMatch.Normalize(b);
        if (x.Length == 0 || y.Length == 0 || TextMatch.AddsMeaning(a, b) || TextMatch.AddsMeaning(b, a)) return false;
        if (x == y) return a.Contains('?') == b.Contains('?');
        return x.Count(char.IsLetter) >= MinimumLetters && y.Count(char.IsLetter) >= MinimumLetters
            && TextMatch.IsSimilar(x.Replace("rn", "m"), y.Replace("rn", "m"), SameMessage);
    }

    // Ekrandaki balonların kararlılığı (X, 22 Kas, GTA 6 telefonu: "yazılar sürekli oynuyor okumak çok zor, balonların
    // içinde de aynı hata var"). Her OCR turunda balon kutuları birkaç piksel oynuyor, telefonun bulunan yeri titriyordu;
    // her turda yeni kutular gönderiliyor, TV paneli ve balonları yeniden diziyordu. Mac/iPhone ve Android aynı kural.

    /// <summary>Aynı balonun yeri, satır yüksekliğinin bu payından az oynadıysa son çizilen yerde kalır (histerezis).</summary>
    internal const double PositionShare = 0.25;
    /// <summary>Yanda Panel'in dayandığı telefon yeri, kutusunun her kenarı bu kadardan (kareye oranla) az oynadıysa sabit kalır.</summary>
    internal const double PoseSlack = 0.015;

    /// <summary>
    /// Balonların yeri: önceki gönderiyle eşleşen balonlar (<see cref="Match"/>) küçük oynamada (satır yüksekliğinin
    /// <see cref="PositionShare"/>'i; yatayda kare oranıyla) son çizilen yerde kalır. Eşleşenlerin yarısından çoğu eşiği aşarsa
    /// (telefon kıpırdadı, sohbet kaydı) hepsi birlikte, tek seferde yeni yerine geçer; tek başına eşiği aşan balon kendi
    /// yerine geçer. Boyu değişmeyen balonun kutusu birebir öncekidir. <paramref name="aspect"/>: karenin eni / boyu.
    /// </summary>
    internal static IReadOnlyList<ScreenTranslation.Item> SteadyPositions(IReadOnlyList<ScreenTranslation.Item> items,
        IReadOnlyList<ScreenTranslation.Item> previous, double aspect)
    {
        double ratio = Math.Max(0.1, aspect);
        bool Still(TextBox box, ScreenTranslation.Item old)
        {
            double limit = PositionShare * old.LineHeight;
            return Math.Abs(box.Top - old.Box.Top) <= limit && Math.Abs(box.Left - old.Box.Left) <= limit / ratio;
        }
        var pairs = new List<(int Index, ScreenTranslation.Item Old)>();
        for (int i = 0; i < items.Count; i++)
            if (Match(items[i], previous) is { } old) pairs.Add((i, old));
        int moved = pairs.Count(pair => !Still(items[pair.Index].Box, pair.Old));
        if (pairs.Count == 0 || 2 * moved > pairs.Count) return items;
        var result = items.ToList();
        foreach (var (index, old) in pairs)
        {
            var box = items[index].Box;
            if (!Still(box, old)) continue;
            double width = box.Right - box.Left, height = box.Bottom - box.Top;
            double oldWidth = old.Box.Right - old.Box.Left, oldHeight = old.Box.Bottom - old.Box.Top;
            result[index] = items[index] with
            {
                Box = new TextBox(old.Box.Left, old.Box.Top,
                    Math.Abs(width - oldWidth) < 1e-9 ? old.Box.Right : Math.Min(1, old.Box.Left + width),
                    Math.Abs(height - oldHeight) < 1e-9 ? old.Box.Bottom : Math.Min(1, old.Box.Top + height))
            };
        }
        return result;
    }

    /// <summary>İki yazı rengi zeminin aynı yanında mı (ikisi de zeminden koyu ya da ikisi de açık; algılanan parlaklıkla).</summary>
    internal static bool SameInk(string a, string b, string background)
    {
        static int? Brightness(string hex)
        {
            if (hex.Length != 7 || hex[0] != '#' || !int.TryParse(hex.AsSpan(1), System.Globalization.NumberStyles.HexNumber, null, out var value))
                return null;
            return (((value >> 16) & 0xFF) * 299 + ((value >> 8) & 0xFF) * 587 + (value & 0xFF) * 114) / 1000;
        }
        if (Brightness(a) is not { } x || Brightness(b) is not { } y || Brightness(background) is not { } z) return false;
        return (x < z) == (y < z);
    }

    /// <summary>
    /// Önceki gönderide bu balonun eşi: aynı çeviri ve parça, aynı okuma (<see cref="SameReading"/>), sol üst köşesi 0,05
    /// içinde. Aynı yerde iki eş varsa null.
    /// </summary>
    internal static ScreenTranslation.Item? Match(ScreenTranslation.Item item, IReadOnlyList<ScreenTranslation.Item> previous)
    {
        ScreenTranslation.Item? found = null;
        foreach (var old in previous)
        {
            if (old.Translation != item.Translation || old.Panel != item.Panel || Math.Abs(old.Box.Left - item.Box.Left) > .05
                || Math.Abs(old.Box.Top - item.Box.Top) > .05 || !SameReading(old.Source, item.Source)) continue;
            if (found is not null) return null;
            found = old;
        }
        return found;
    }

    /// <summary>Yanda Panel'in dayandığı telefon: yeni yerin kutusu öncekinden her kenarda <see cref="PoseSlack"/>'ten az oynadıysa önceki yer.</summary>
    internal static GamePhoneGeometry.Pose SteadyPose(GamePhoneGeometry.Pose pose, GamePhoneGeometry.Pose? anchor)
    {
        if (anchor is not { } previous) return pose;
        CropRegion a = pose.Bounds, b = previous.Bounds;
        bool still = Math.Abs(a.Left - b.Left) <= PoseSlack && Math.Abs(a.Right - b.Right) <= PoseSlack
            && Math.Abs(a.Top - b.Top) <= PoseSlack && Math.Abs(a.Bottom - b.Bottom) <= PoseSlack;
        return still ? previous : pose;
    }

    /// <summary>
    /// İki gönderi TV'de ve masaüstünde aynı görünür mü. Panelin mesajları, kişi adı ve notları akışla çizilir: yalnız sırası,
    /// yazısı ve rengi önemlidir; panelin zemini ve panel dışındaki her öğe yeriyle aynı olmalıdır.
    /// </summary>
    internal static bool SamePicture(IReadOnlyList<ScreenTranslation.Item> a, IReadOnlyList<ScreenTranslation.Item> b)
    {
        if (a.Count != b.Count) return false;
        for (int i = 0; i < a.Count; i++)
        {
            var (x, y) = (a[i], b[i]);
            bool icons = x.Icons is null ? y.Icons is null : y.Icons is not null && x.Icons.SequenceEqual(y.Icons);
            if (x.Panel != y.Panel || x.Translation != y.Translation || x.Style != y.Style || x.Look != y.Look || !icons
                || x.Bubble != y.Bubble || x.LineHeight != y.LineHeight) return false;
            if (x.Panel is null or ScreenPhoneCard.PanelPart.Card && x.Box != y.Box) return false;
        }
        return true;
    }
}
