// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Hattın karara bağladığı (atılan ya da gösterilen) satırlar, ekranda durdukları sürece. PS5'in Türkçe ana ekranında
/// (beta.89, Mac) alandaki satırlar her karede okunuyor, seçilen blok ise her iki üç saniyede bir değişiyordu ("One [Ikan
/// Ipufl", "Yakin zamanda olu...", "e [Ikan Ipuflari Yakin zamanda olu..."): doğru okunan Türkçe satır "zaten hedef
/// dilde" diye atılıyor, bozuk okunan parçası İngilizce sanılıp çevriliyor ve TV'de altyazı olarak beliriyordu; aynı
/// döngü ekran değişmeden her 2,5 sn'de bir yineleniyordu. Üç kural:
///  1. Kaynağı zaten hedef dilde olan bloğun (`target`) aynı yerdeki bozuk okunmuş parçası (`isTargetFragment`) altyazı
///     adayı değildir.
///  2. Karara bağlanmış satır (`isSettled`) ekranda durdukça yeniden işlenmez, günlüğe de yeniden yazılmaz.
///  3. Satır karenin okunan yazısında artık yoksa unutulur: atılan satır `droppedAbsentMs` sonra, gösterilen satır ilk
///     yokluğunda (aynı satır gerçekten yeniden gelirse her zamanki gibi çevrilir).
/// Windows (SettledText.cs) ve Android (SettledText.kt) aynı kuralları uygular; ortak deneme dosyası settled-text.json.
struct SettledText {
    /// Atılan satır bu süre boyunca karede okunmazsa unutulur (yazı tanımanın tek tük kaçırdığı kareler sayılmaz).
    static let droppedAbsentMs = 1500
    /// Parçanın büyük yazıda kesintisiz geçen en uzun bölümü, parçanın en az bu oranı olmalı.
    static let coverage = 0.7
    /// Aynı satırın yeniden okuması sayılan benzerlik (Levenshtein oranı).
    static let similarity = 0.8
    /// Bundan kısa (sadeleştirilmiş) satır akılda tutulmaz ("No.", "Go!" yeniden söylenebilir).
    static let minLength = 6
    static let capacity = 16

    struct Entry: Equatable {
        let text: String
        let top: Double?
        let bottom: Double?
        /// Kaynağı zaten hedef dildeydi.
        let target: Bool
        /// Çevirisi TV'ye gitti.
        let shown: Bool
        /// Altyazı adayı sayılmadan atıldı (Türkçe, Türkçe bloğun parçası, çöp okuma): yazı tanıma farkı kadar değişmiş
        /// okuması da aynı satırdır. Çevirisi aslıyla aynı çıkan satırda yalnız aynı metin sayılır (düzelen okuma, ör.
        /// "I can do" → "I can't do", yeniden çevrilir).
        let loose: Bool
        var seenAt: Int
    }

    private(set) var entries: [Entry] = []

    /// Karenin bütün okunan satırları: ekranda duran kayıtların görüldüğü an yenilenir, ekrandan kalkanlar unutulur.
    mutating func observe(_ lines: [String], at time: Int) {
        guard !entries.isEmpty else { return }
        let frame = TextMatch.normalize(lines.joined(separator: " "))
        entries = entries.compactMap { entry in
            var entry = entry
            if Self.covered(entry.text, by: frame) { entry.seenAt = time }
            return time - entry.seenAt > (entry.shown ? 0 : Self.droppedAbsentMs) ? nil : entry
        }
    }

    /// Satır karara bağlandı (atıldı ya da gösterildi).
    mutating func settle(_ source: String, box: TextBox?, target: Bool, shown: Bool, loose: Bool = false, at time: Int) {
        let text = TextMatch.normalize(source)
        guard text.count >= Self.minLength else { return }
        entries.removeAll { $0.text == text }
        entries.append(Entry(text: text, top: box?.top, bottom: box?.bottom, target: target, shown: shown,
                             loose: loose && !shown, seenAt: time))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// Satır karara bağlanmış ve hâlâ ekranda. Altyazı adayı sayılmadan atılan satırın (`loose`) yazı tanıma farkı kadar
    /// değişmiş okuması da sayılır; öbürlerinde yalnız aynı metin (uzamış ya da düzelmiş okuması her zamanki gibi gider).
    func isSettled(_ source: String) -> Bool {
        let text = TextMatch.normalize(source)
        guard text.count >= Self.minLength else { return false }
        return entries.contains { $0.text == text || ($0.loose && TextMatch.isSimilar(text, $0.text, threshold: Self.similarity)) }
    }

    /// Satır, aynı yerde duran ve kaynağı zaten hedef dilde olan bir bloğun bozuk okunmuş parçası mı ("One [Ikan Ipufl"
    /// ⊂ "e [Ikan Ipuflari Yakin zamanda olu..."). Yerler biliniyorsa dikeyde örtüşmeleri gerekir. Türkçe olduğu burada
    /// anlaşılan (`loose`) bloğun parçası okuma farkıyla biraz uzun da olabilir; çevirmenin aslıyla aynı döndürdüğü bloğun
    /// parçası ondan kısa olmalı ve cümle gibi bitmemeli (tam cümle, ör. "I said that I would help you.", altyazıdır).
    func isTargetFragment(_ source: String, box: TextBox?) -> Bool {
        let text = TextMatch.normalize(source)
        guard text.count >= Self.minLength else { return false }
        let sentence = SubtitleStabilizer.endsSentence(source)
        return entries.contains { entry in
            guard entry.target, entry.loose ? text.count <= entry.text.count + 2 : text.count < entry.text.count && !sentence,
                  Self.covered(text, by: entry.text) else { return false }
            guard let box, let top = entry.top, let bottom = entry.bottom else { return true }
            return box.top < bottom && top < box.bottom
        }
    }

    mutating func reset() { entries.removeAll() }

    /// `part`ın `whole` içinde kesintisiz geçen en uzun bölümü `part`ın en az `coverage` oranı mı.
    static func covered(_ part: String, by whole: String) -> Bool {
        let a = Array(part), b = Array(whole)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(longestRun(a, b)) >= coverage * Double(a.count)
    }

    /// İki metnin ortak en uzun kesintisiz bölümünün uzunluğu (karakter).
    static func longestRun(_ a: [Character], _ b: [Character]) -> Int {
        var previous = [Int](repeating: 0, count: b.count + 1)
        var best = 0
        for i in 1...a.count {
            var row = [Int](repeating: 0, count: b.count + 1)
            for j in 1...b.count where a[i - 1] == b[j - 1] {
                row[j] = previous[j - 1] + 1
                best = max(best, row[j])
            }
            previous = row
        }
        return best
    }
}
