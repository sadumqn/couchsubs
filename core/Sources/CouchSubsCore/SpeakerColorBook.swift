// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Konuşana göre renk (v2): oturum boyunca (çeviri başlayınca sıfırlanır) her kişiye bir renk. Yazı tanımanın yakın
/// okuması aynı kişidir ("Mattia", "Mattla", "Mattia." aynı renk); yeni kişi, mümkünse başka kişilerin renginden ve renk
/// ailesinden ayrı bir renk alır (iki mavi tonlu kişi yan yana karışmasın). Kurallar ve ortak test vektörü:
/// scripts/speaker_colors_ref.py, docs/speaker-colors-vectors.json (Windows ve Android aynı sırada aynı rengi verir).
public final class SpeakerColorBook: @unchecked Sendable {
    /// Palet renklerinin aileleri: aynı ailedeki iki renk ekranda birbirine benzer.
    public static let families: [String: Character] = [
        "#FFD54F": "A", "#FFB74D": "A", "#FF8A65": "A",
        "#4FC3F7": "B", "#4DD0E1": "B", "#90CAF9": "B",
        "#81C784": "C", "#AED581": "C",
        "#CE93D8": "D", "#F06292": "D",
    ]

    private let lock = NSLock()
    private var people: [(key: String, color: String)] = []

    /// Altyazı Görünümü › Karakter Adı: "Tek Renk"te herkesin rengi (`fixed`), "Karaktere Göre"de kullanıcının seçtiği
    /// kişi renkleri (`overrides`, anahtar küçük harfli ad). Seçilmeyen kişilere sırayla palet rengi verilir.
    private var fixed: String?
    private var overrides: [String: String] = [:]

    public init() {}

    public func configure(fixed: String?, overrides: [String: String]) {
        let normalized = Dictionary(overrides.map { (Self.key($0.key), $0.value) }, uniquingKeysWith: { $1 })
        lock.withLock {
            self.fixed = fixed
            self.overrides = normalized
        }
    }

    /// Bu oturumda rengi verilmiş kişiler (adın anahtarı ve rengi), ilk görülen önce.
    public var known: [(key: String, color: String)] { lock.withLock { people } }

    /// Adın rengi; bilinmeyen kişi eklenir. Ad boşsa nil.
    public func color(_ name: String) -> String? {
        let key = Self.key(name)
        guard !key.isEmpty else { return nil }
        return lock.withLock {
            if let fixed { return fixed }
            if let chosen = overrides[key] ?? overrides.first(where: { Self.samePerson($0.key, key) })?.value {
                if !people.contains(where: { Self.samePerson($0.key, key) }) { people.append((key, chosen)) }
                return chosen
            }
            if let known = people.first(where: { Self.samePerson($0.key, key) }) { return known.color }
            let palette = SpeakerColors.palette
            let base = Int(SpeakerColors.hash(key) % UInt32(palette.count))
            let used = Set(people.map(\.color))
            let usedFamilies = Set(used.compactMap { Self.families[$0] })
            let order = (0..<palette.count).map { palette[(base + $0) % palette.count] }
            let pick = order.first { !used.contains($0) && !usedFamilies.contains(Self.families[$0]!) }
                ?? order.first { !used.contains($0) } ?? palette[base]
            people.append((key, pick))
            return pick
        }
    }

    /// Çeviri yeniden başladı: kişiler unutulur.
    public func reset() {
        lock.withLock { people.removeAll() }
    }

    /// Ad anahtarı: kırpılmış, sondaki noktalaması atılmış, küçük harf.
    static func key(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespaces)
        while let last = text.last, ".,!?;:…".contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func samePerson(_ a: String, _ b: String) -> Bool {
        a == b || confusable(a) == confusable(b) || (min(a.utf16.count, b.utf16.count) >= 5 && distance(a, b) <= 1)
    }

    /// Yazı tanımanın karıştırdığı harfler eşitlenir: l/1/| → i, 0 → o, rn → m.
    private static func confusable(_ key: String) -> String {
        String(key.replacingOccurrences(of: "rn", with: "m").map { c -> Character in
            switch c {
            case "l", "1", "|": "i"
            case "0": "o"
            default: c
            }
        })
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.utf16), b = Array(b.utf16)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where i <= a.count {
            let previous = row
            row[0] = i
            for j in 1...max(1, b.count) where j <= b.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
        }
        return row[b.count]
    }
}
