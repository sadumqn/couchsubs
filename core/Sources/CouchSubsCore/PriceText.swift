// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// "Ekranı çevir"de fiyat ve sayılar (GTA 6 dükkânı, bahşiş menüsü): yazı tanıma "$" işaretini "S" okuyor ("$200" →
/// "S200", "$$$$" → "SSSS"); bozuk okuma harf sayılıp çevirmene gidiyor, ekranda anlamsız bir yazı çıkıyordu. Burada
/// rakam bağlamındaki "S" ve yalnız "S"/"$"den oluşan sözcük "$"a döner (`repair`); para ve ayraçlı sayılar ("$1,250",
/// "2.5") çevirmene uydurma bir adla gider ve çeviriden sonra olduğu gibi yerine konur (`protect`/`restore`): çevirmen
/// "$200"ü "200 dolar" ya da "1,250"yi "1.250" yapamaz. Kurallar ortak deneme dosyasıyla sınanır
/// (Tests/Fixtures/price-text.json; Windows: PriceText.cs, Android: PriceText.kt).
public enum PriceText {
    /// Korunmuş metin: çevirmene gidecek metin ve sırayla kullanılan (ad, değer) çiftleri.
    public struct Protected: Equatable, Sendable {
        public var text: String
        public var values: [Value]

        public struct Value: Equatable, Sendable {
            public var name: String
            public var value: String
        }
    }

    /// "S" + rakamla başlayan fiyat ("S200", "S1,250", "S2OO", "S5K"); "S"den sonra ilk karakter rakam olmalı.
    private static let misreadPrice = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}$])[S$](?=[0-9])([0-9OoIl.,]*[0-9OoIl])([KkMm]?)(?![\p{L}\p{N}])"#)
    /// Yalnız "S" ve "$"den oluşan sözcük ("SSSS", "$$S"): fiyat düzeyi ya da okunamayan fiyat.
    private static let dollarRun = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])[S$]{2,}(?![\p{L}\p{N}])"#)
    /// Korunacak sayılar: para ("$200", "$1,250.50", "$5K", "$$$") ve ayraçlı sayı ("1,250", "2.5", "10:30").
    private static let protectedNumber = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:\$+(?:[0-9][0-9.,]*[0-9]|[0-9])?[KkMm]?|[0-9]+(?:[.,:][0-9]+)+)(?![\p{L}\p{N}])"#)

    /// Terim ve simge korumasıyla aynı adlar (çevirmenler özel adı olduğu gibi bırakır); metinde geçen ad kullanılmaz.
    private static let names = TermProtector.placeholders

    /// Yazı tanımanın bozduğu fiyatları düzeltir; uzunluk değişmez (sözcük kutuları geçerli kalır).
    public static func repair(_ text: String) -> String {
        guard text.contains("S") || text.contains("$") else { return text }
        var result = text
        // "S200", "S2OO" → "$200": "S" ve içindeki O/I/l harfleri rakam bağlamında.
        for match in misreadPrice.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result),
                  let suffix = Range(match.range(at: 2), in: result) else { continue }
            let fixed = "$" + result[digits].map { c -> String in
                switch c {
                case "O", "o": "0"
                case "I", "l": "1"
                default: String(c)
                }
            }.joined() + result[suffix]
            result.replaceSubrange(whole, with: fixed)
        }
        // "SSSS" → "$$$$"; iki harflik "SS" ancak içinde "$" varsa ("$S").
        for match in dollarRun.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let run = result[whole]
            guard run.count >= 3 || run.contains("$") else { continue }
            result.replaceSubrange(whole, with: String(repeating: "$", count: run.count))
        }
        return result
    }

    /// Sözcük fiyat ya da yalnız "$" mı ("$200", "$$$$"; düzeltilmiş okumada).
    public static func isMoney(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[].,:;!?"))
        guard core.hasPrefix("$") else { return false }
        let range = NSRange(core.startIndex..., in: core)
        return protectedNumber.firstMatch(in: core, range: range)?.range == range
    }

    /// Para ve ayraçlı sayıları adlarla değiştirir. Ad kalmazsa kalan sayılar olduğu gibi gider.
    public static func protect(_ text: String) -> Protected {
        let matches = protectedNumber.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return Protected(text: text, values: []) }
        var free = names.filter { text.range(of: $0, options: .caseInsensitive) == nil }
        var values: [Protected.Value] = []
        var result = text
        var picked: [(NSRange, String)] = []
        for match in matches {
            guard !free.isEmpty, let range = Range(match.range, in: text) else { break }
            let name = free.removeFirst()
            values.append(.init(name: name, value: String(text[range])))
            picked.append((match.range, name))
        }
        for (range, name) in picked.reversed() {
            if let swiftRange = Range(range, in: result) { result.replaceSubrange(swiftRange, with: name) }
        }
        return Protected(text: result, values: values)
    }

    /// Çevirideki adları değerlerine döndürür; adın Türkçe eki kesme işaretiyle korunur ("Zarmon'a" → "$200'a",
    /// "Zarmona" → "$200'a"). Çeviride bulunmayan değer sona eklenir (fiyat kaybolmasın).
    public static func restore(_ translation: String, _ values: [Protected.Value]) -> String {
        var text = translation
        var missing: [String] = []
        for value in values {
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: value.name)
                + #"(?:\s?['’`´](\p{L}+)|(\p{L}+))?(?![\p{L}\p{N}])"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            guard !matches.isEmpty else {
                missing.append(value.value)
                continue
            }
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: text) else { continue }
                let suffix = [1, 2].compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }.first
                text.replaceSubrange(whole, with: value.value + (suffix.map { "'" + $0 } ?? ""))
            }
        }
        return missing.isEmpty ? text : ([text] + missing).joined(separator: " ")
    }
}
