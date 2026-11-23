// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Ekranda zaten Türkçe olan satır (PS5'in Türkçe arayüzü): hedef dil Türkçeyken çevirmene gönderilmez (#289). Yazı
/// tanıma Türkçe harfleri bozduğu için ("Sistem Yazillml Güncellem€") çeviriden sonraki "aslıyla aynı" denetimi bu
/// satırları kaçırıyordu: motor bozuk harfleri düzeltip farklı bir metin döndürünce satır yeniden gösteriliyordu. Ölçüt
/// temkinlidir: Türkçe harf ve bilinen bir Türkçe sözcük birlikte bulunmalı; içinde Türkçe ad geçen İngilizce satır
/// ("Atatürk said...") çevrilir. Windows'taki CouchSubs.Core/TurkishText.cs ve Android'deki TurkishText.kt ile aynı kurallar.
public enum TurkishText {
    /// Türkçe harfler (ü, ö, ç İngilizce satırda ancak yabancı adda geçer; tek başına yetmez).
    static let letters: Set<Character> = ["ğ", "Ğ", "ş", "Ş", "ı", "İ", "ü", "Ü", "ö", "Ö", "ç", "Ç"]

    /// Havuz süzgecinin sözcüklerine ek, Türkçe arayüzde sık geçen ve İngilizcede olmayan sözcükler (katlanmış hâlleriyle
    /// karşılaştırılır; "sistem" yok: katlanınca İngilizce "system" ile bir harf farklı). Ardından oyunun kendi Türkçe
    /// altyazısında sık geçen konuşma sözcükleri (GitHub #337: "Yardımcı olabilir miyim, efendim?" çevrilmeye gidiyordu).
    static let commonWords: [String] = [
        "daha", "sonra", "simdi", "degil", "haydi", "tamam", "evet", "hayir", "devam", "iptal", "giris", "guncelle",
        "guncellemesi", "yazilimi", "kurulum", "sirasinda", "sisteminizi", "sistemindeki", "kapatmayin", "baglanti",
        "baglantinizi", "uzaktan", "oynama", "dosyasi", "gostergesi", "kablosunu", "bir",
        "efendim", "yardimci", "olabilir", "miyim", "misin", "musun", "nasil", "neden", "burada", "tesekkurler", "merhaba",
        "gibi", "kadar", "belki", "hemen", "benim", "senin",
    ].map { PoolFilter.fold($0).joined() }

    /// PS5'in Türkçe ana ekranı ve oyun kartı menüsünün sözcükleri ("Öne Çıkan İpuçları", "Yakın zamanda oluşturulanlar",
    /// "Oyunlarınızdan 7 hikâye", "Resmi haberler"). Yazı tanıma Türkçe harfleri düz harfe çevirince ("Yakin zamanda olu...")
    /// satır İngilizce sanılıp paketle eşleşiyor ya da çevriliyordu (beta.89, Mac).
    static let menuWords: [String] = [
        "yakin", "zamanda", "olusturulanlar", "ipuclari", "cikan", "ogrenin", "kullanmayi", "hikaye", "haberler",
        "oyunlarinizdan", "secenekler", "resmi", "yeni",
    ].map { PoolFilter.fold($0).joined() }

    private static let known = PoolFilter.turkishWords + commonWords + menuWords

    /// Satır yüksek güvenle Türkçe mi: en az bir Türkçe harf ve en az bir bilinen Türkçe sözcük.
    public static func isSure(_ text: String) -> Bool {
        guard text.contains(where: letters.contains) else { return false }
        return PoolFilter.fold(text).contains { word in known.contains { PoolFilter.isClose(word, $0) } }
    }

    /// Türkçe harfleri yazı tanımada düz harfe dönmüş Türkçe satır mı ("Yakin zamanda olu...", "e [Ikan Ipuflari Yakin
    /// zamanda olu..."): en az iki bilinen Türkçe sözcük, ve iki ya da daha çok harfli sözcüklerin en az yarısı bilinen
    /// Türkçe sözcük. İçinde tek Türkçe sözcük geçen İngilizce satır çevrilir.
    public static func isFolded(_ text: String) -> Bool {
        let words = PoolFilter.fold(text).filter { $0.count >= 2 && $0.contains(where: \.isLetter) }
        let hits = words.filter { word in known.contains { PoolFilter.isClose(word, $0) } }.count
        return hits >= 2 && hits * 2 >= words.count
    }

    /// Satır Türkçe mi (`isSure` ya da `isFolded`).
    public static func looksTurkish(_ text: String) -> Bool { isSure(text) || isFolded(text) }
}
