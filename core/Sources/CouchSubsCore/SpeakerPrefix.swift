// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Altyazının başındaki konuşan adı ("ARTHUR: We need to go.", "Dutch：Easy."). Ad çeviriye gitmez: motorlar adı
/// çeviriyor ya da cümlenin içine katıyordu, paket anahtarı da çoğu zaman adsız tutuluyor. Hat önce adlı satırı, sonra
/// adsız cümleyi pakette arar; motora yalnız cümle gider, ad gösterirken geri eklenir ya da (ayar kapalıysa) atılır.
/// Android (SpeakerPrefix.kt) ve Windows (SpeakerPrefix.cs) aynı kuralları uygular.
public enum SpeakerPrefix {
    public struct Split: Equatable, Sendable {
        public var name: String
        public var body: String
        public init(name: String, body: String) {
            self.name = name
            self.body = body
        }
    }

    /// En çok üç sözcük, her sözcük büyük harfle başlar (BÜYÜK HARF ya da Baş Harf Büyük), rakam yok; ardından ":" ya da "：".
    private static let pattern = try! NSRegularExpression(pattern:
        #"^(\p{Lu}[\p{L}'’.\-]*(?: \p{Lu}[\p{L}'’.\-]*){0,2}) ?[:：]\s*"#)
    public static let maxNameLength = 24

    /// Baştaki konuşan adı ve cümle; ad yoksa (saat "10:30", adres "https://", oran "16:9", "Note:" gibi başlıklar) nil.
    public static func split(_ text: String) -> Split? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let found = pattern.firstMatch(in: trimmed, range: range),
              let whole = Range(found.range, in: trimmed),
              let nameRange = Range(found.range(at: 1), in: trimmed) else { return nil }
        let name = String(trimmed[nameRange])
        let body = String(trimmed[whole.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= maxNameLength,
              !(!name.contains(" ") && SubtitleSegmenter.notNames.contains(name.lowercased())),
              body.contains(where: \.isLetter),
              !body.hasPrefix("/") else { return nil }
        return Split(name: name, body: body)
    }

    /// Gösterilecek metin: çeviri `source`'un baştaki adıyla başlar ("ARTHUR: Gitmeliyiz."); `show` kapalıysa
    /// İngilizcede konuşan adı olan satır başları atılır, yalnız Türkçe cümle kalır ("Hedef: …" gibi Türkçe başlık kalır).
    public static func present(_ translation: String, source: String, show: Bool) -> String {
        var text = translation
        if let prefix = split(source), split(text)?.name != prefix.name { text = "\(prefix.name): \(text)" }
        guard !show else { return text }
        let names = Set(source.components(separatedBy: "\n").compactMap { split($0)?.name } + [split(source)?.name].compactMap { $0 })
        return text.components(separatedBy: "\n").map { line in
            guard let found = split(line), names.contains(found.name) else { return line }
            return found.body
        }.joined(separator: "\n")
    }

    /// Cümlenin seslendirme satırları adı taşımıyorsa konuşan, baştaki addır.
    public static func voiced(_ lines: [SpokenLine], prefix: Split?) -> [SpokenLine] {
        guard let prefix else { return lines }
        var result = lines
        for index in result.indices {
            if result[index].speaker != nil || (index > 0 && result[index].newTurn) { break }
            result[index].speaker = prefix.name
        }
        return result
    }
}
