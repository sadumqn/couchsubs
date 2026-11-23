// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Otomatik ekran yazısının türleri; Ayarlar'da her biri ayrı açılıp kapanır (kullanıcı isteği, X: "telefon, eylemler
/// çevirisini kullanmak istiyorum, menülerde olmasını istemiyorum"). Sıra ve adlar dört platformda aynıdır (Mac/iPhone:
/// ScreenTextKind.swift, Android: ScreenTextKind.kt). "Ekranı çevir" (elle) türlerden etkilenmez, her şeyi çevirir.
/// </summary>
public enum ScreenTextKind
{
    /// <summary>GTA 6 telefonu (telefon okuyucusu) ve hazır mesaj kartı alanı.</summary>
    Phone,
    /// <summary>
    /// Görev ve hedef yazısı (altyazıdan ayrılan görev satırı, <see cref="MissionLine"/>) ve haritada basılan görevin/konumun
    /// bilgi kartı (<see cref="MissionCard"/>; menüde açılsa da bu türdendir, ayrı anahtarı yoktur).
    /// </summary>
    Mission,
    /// <summary>Yardım ve ipucu kutuları, eylemler: tuş ipuçları, etkileşim istemleri; hazır yardım kutusu alanı.</summary>
    Help,
    /// <summary>Menüler (duraklatma, harita, ayarlar): dedektörün menü durumunda bulduğu alanlar.</summary>
    Menu,
    /// <summary>Diğer ekran yazıları (kısa başlık, yer adı, bildirim).</summary>
    Other,
}

public static class ScreenTextKinds
{
    /// <summary>Kısa etiketten uzun sayılan yazı (yardım kutusu cümlesi) en az bu kadar sözcük.</summary>
    public const int HelpWords = 8;

    /// <summary>
    /// Alanın türü yerinden belli mi: hazır alanlar, görev satırı ve menü alanları. Kullanıcının kendi ek alanı ve telefon
    /// okuyucusunun paneli null (her zaman okunur; telefon kendi ayarıyla açılır); menü dışındaki otomatik alanın türü
    /// okunan yazıdan çıkar (<see cref="Of(IReadOnlyList{string})"/>).
    /// </summary>
    public static ScreenTextKind? Of(WatchedArea area) => area.Id switch
    {
        GameAreaPresets.PhoneId => ScreenTextKind.Phone,
        GameAreaPresets.HelpId => ScreenTextKind.Help,
        MissionLine.AreaId => ScreenTextKind.Mission,
        _ => area.Auto && area.Menu ? ScreenTextKind.Menu : null,
    };

    /// <summary>
    /// Pas turunda alan okunur mu: türü açık ya da yerinden belli değil. Menüler kapalıyken de kart boyundaki menü alanı
    /// (en çok <see cref="MissionCard.MaxWidth"/> genişlik, ekranın yarısı yükseklik) "Görev ve hedef yazısı" açıksa okunur:
    /// haritada açılan görev kartı menü sayılan ekranda durur; kart değilse çizilmez (bkz. RegionWatcher.Kind).
    /// </summary>
    public static bool Reads(WatchedArea area, Func<ScreenTextKind, bool> allows)
    {
        if (Of(area) is not { } kind || allows(kind)) return true;
        var region = area.Region;
        return kind == ScreenTextKind.Menu && allows(ScreenTextKind.Mission)
               && region.Right - region.Left <= MissionCard.MaxWidth && region.Bottom - region.Top <= 0.5;
    }

    /// <summary>
    /// Menü dışındaki otomatik alanın türü: tuş simgesi ya da tuş ipucu ("Press ✕ to jump", "R2 Aim") taşıyan, birden çok
    /// parçalı ya da uzun (en az <see cref="HelpWords"/> sözcük) yazı yardım/eylemdir; noktalamayla biten kısa tek cümle
    /// ("Follow Paulie to the car.") görev/hedeftir; kısa başlık (yer adı) diğerdir.
    /// </summary>
    public static ScreenTextKind Of(IReadOnlyList<string> paragraphs)
    {
        if (paragraphs.Any(item => item.Contains(ButtonIcons.Marker) || ButtonPrompts.IsPrompt(IconText.Plain(item))))
            return ScreenTextKind.Help;
        var words = paragraphs.Sum(item => IconText.Plain(item).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length);
        if (paragraphs.Count >= 2 || words >= HelpWords) return ScreenTextKind.Help;
        var last = IconText.Plain(paragraphs.Count == 1 ? paragraphs[0] : "").TrimEnd(' ', '"', '\'', '\u201D', '\u2019');
        return words >= 2 && last.Length > 0 && ".!?".Contains(last[^1]) ? ScreenTextKind.Mission : ScreenTextKind.Other;
    }
}
