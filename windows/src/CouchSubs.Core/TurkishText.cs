// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Ekranda zaten Türkçe olan satır (PS5'in Türkçe arayüzü): hedef dil Türkçeyken çevirmene gönderilmez (#289). Yazı
/// tanıma Türkçe harfleri bozduğu için ("Sistem Yazillml Güncellem€") çeviriden sonraki "aslıyla aynı" denetimi bu satırları
/// kaçırıyordu: motor bozuk harfleri düzeltip farklı bir metin döndürünce satır yeniden gösteriliyordu. Ölçüt temkinlidir:
/// Türkçe harf ve bilinen bir Türkçe sözcük birlikte bulunmalı; içinde Türkçe ad geçen İngilizce satır ("Atatürk said...")
/// çevrilir. Mac'teki CouchSubsCore/TurkishText.swift ve Android'deki TurkishText.kt ile aynı kurallar.
/// </summary>
public static class TurkishText
{
    /// <summary>Türkçe harfler (ü, ö, ç İngilizce satırda ancak yabancı adda geçer; tek başına yetmez).</summary>
    private const string Letters = "ğĞşŞıİüÜöÖçÇ";

    /// <summary>
    /// Havuz süzgecinin sözcüklerine ek, Türkçe arayüzde sık geçen ve İngilizcede olmayan sözcükler (katlanmış hâlleriyle
    /// karşılaştırılır; "sistem" yok: katlanınca İngilizce "system" ile bir harf farklı). Ardından oyunun kendi Türkçe
    /// altyazısında sık geçen konuşma sözcükleri (GitHub #337: "Yardımcı olabilir miyim, efendim?" çevrilmeye gidiyordu).
    /// </summary>
    internal static readonly string[] CommonWords = new[]
    {
        "daha", "sonra", "simdi", "degil", "haydi", "tamam", "evet", "hayir", "devam", "iptal", "giris", "guncelle",
        "guncellemesi", "yazilimi", "kurulum", "sirasinda", "sisteminizi", "sistemindeki", "kapatmayin", "baglanti",
        "baglantinizi", "uzaktan", "oynama", "dosyasi", "gostergesi", "kablosunu", "bir",
        "efendim", "yardimci", "olabilir", "miyim", "misin", "musun", "nasil", "neden", "burada", "tesekkurler", "merhaba",
        "gibi", "kadar", "belki", "hemen", "benim", "senin",
    }.Select(word => string.Concat(PoolFilter.Fold(word))).ToArray();

    /// <summary>
    /// PS5'in Türkçe ana ekranı ve oyun kartı menüsünün sözcükleri ("Öne Çıkan İpuçları", "Yakın zamanda oluşturulanlar",
    /// "Oyunlarınızdan 7 hikâye", "Resmi haberler"). Yazı tanıma Türkçe harfleri düz harfe çevirince ("Yakin zamanda olu...")
    /// satır İngilizce sanılıp paketle eşleşiyor ya da çevriliyordu (beta.89, Mac).
    /// </summary>
    internal static readonly string[] MenuWords = new[]
    {
        "yakin", "zamanda", "olusturulanlar", "ipuclari", "cikan", "ogrenin", "kullanmayi", "hikaye", "haberler",
        "oyunlarinizdan", "secenekler", "resmi", "yeni",
    }.Select(word => string.Concat(PoolFilter.Fold(word))).ToArray();

    private static readonly string[] Known = [.. PoolFilter.TurkishWords, .. CommonWords, .. MenuWords];

    /// <summary>Satır yüksek güvenle Türkçe mi: en az bir Türkçe harf ve en az bir bilinen Türkçe sözcük.</summary>
    public static bool IsSure(string text)
    {
        if (!text.Any(c => Letters.Contains(c))) return false;
        return PoolFilter.Fold(text).Any(word => Known.Any(known => PoolFilter.IsClose(word, known)));
    }

    /// <summary>
    /// Türkçe harfleri yazı tanımada düz harfe dönmüş Türkçe satır mı ("Yakin zamanda olu...", "e [Ikan Ipuflari Yakin
    /// zamanda olu..."): en az iki bilinen Türkçe sözcük, ve iki ya da daha çok harfli sözcüklerin en az yarısı bilinen
    /// Türkçe sözcük. İçinde tek Türkçe sözcük geçen İngilizce satır çevrilir.
    /// </summary>
    public static bool IsFolded(string text)
    {
        var words = PoolFilter.Fold(text).Where(word => word.Length >= 2 && word.Any(char.IsLetter)).ToList();
        var hits = words.Count(word => Known.Any(known => PoolFilter.IsClose(word, known)));
        return hits >= 2 && hits * 2 >= words.Count;
    }

    /// <summary>Satır Türkçe mi (<see cref="IsSure"/> ya da <see cref="IsFolded"/>).</summary>
    public static bool LooksTurkish(string text) => IsSure(text) || IsFolded(text);
}
