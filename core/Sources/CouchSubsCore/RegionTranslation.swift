// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Bir alanın tek seferlik çevirisi: kısayolla okunan ek alan ve serbest alan (Windows: CouchSubs.Core/RegionTranslation.cs;
/// aynı blok kuralları, aynı gösterim süresi).
public enum RegionTranslation {
    public struct Result: Equatable, Sendable {
        /// Okunan yazı (bloklara ayrılmış, her blok ayrı satırda).
        public var source: String
        /// Aynı blokların çevirisi; madde işaretli bloklar "• " ile başlar.
        public var translation: String
        /// Yazının karedeki yeri, kenarlara oranla; TV çeviriyi buraya yerleştirir.
        public var box: TextBox
        /// Birden çok blok var (başlık, maddeler …): çeviri satır satır, sola yaslı gösterilmelidir.
        public var structured: Bool
    }

    /// Panelde bir paragraf, başlık ya da madde. `bullet`: madde işaretiyle başlıyor (işaret metinden çıkarılır).
    public struct Block: Equatable, Sendable {
        public var text: String
        public var bullet: Bool
    }

    /// Kısayolla bir kez okunan alanın ne olduğu (Windows: ExtraRegionOutcome).
    public enum Outcome: Equatable, Sendable {
        case shown, noText, notConfigured, notRunning, busy, translatorUnavailable, failed
    }

    /// Madde işareti olarak kullanılan simgeler.
    private static let bulletChars: Set<Character> = Set("◇◆◈◊♦♢•●○◦▪■□▫►▶‣∙·*-–—✓✔✦❖◉⬥")

    /// Bölgede yazı yoksa nil. "Derin" okuma açıktır: tek okuma olduğu için boş görünen bölgede büyütülmüş okuma da denenir.
    public static func translateOnce(_ frame: CGImage, region: CropRegion, reader: TextReader,
                                     translator: TextTranslator) async throws -> Result? {
        let area = RegionCropper.crop(frame, to: region)
        let reading = try await ReadQueue.shared.run(priority: .background, detail: ReadQueue.detail("alanı çevir", area)) {
            try reader.readLines(area, deep: true)
        }.withoutButtonPrompts()
        guard !reading.lines.isEmpty else { return nil }
        let whole = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        let box = reading.box?.placed(in: whole) ?? whole
        let blocks = blocks(reading, width: Double(area.width), height: Double(area.height))
        var translated: [String] = []
        for block in blocks {
            let text = try await translator.translate(block.text)
            translated.append(block.bullet ? "• " + text : text)
        }
        return Result(source: blocks.map(\.text).joined(separator: "\n"), translation: translated.joined(separator: "\n"),
                      box: box, structured: blocks.count > 1)
    }

    /// Satırları bloklara toplar; görev panelindeki başlık, açıklama ve maddeler ayrı ayrı çevrilir. Yeni blok başlar:
    /// satır madde işaretiyle başlıyorsa; önceki satır cümleyi bitirdiyse; satırlar arasında belirgin boşluk varsa;
    /// satır soldan belirgin biçimde dışarı çıkıyorsa. Küçük harfle başlayan satır, önceki cümle bitmediyse devamdır.
    /// `width`/`height`: okunan alanın piksel ölçüsü (kutular oransal; yatay ve dikey ölçü aynı birime gelir).
    public static func blocks(_ reading: Reading, width: Double = 1, height: Double = 1) -> [Block] {
        let heights = reading.lines.compactMap(\.box).map { ($0.bottom - $0.top) * height }.sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        var result: [Block] = []
        var current = ""
        var currentBullet = false
        var previous: TextLine?
        for line in reading.lines {
            let (bullet, text) = stripBullet(line.text.trimmingCharacters(in: .whitespaces))
            guard !text.isEmpty else { continue }
            if let upper = previous, !current.isEmpty {
                if bullet || startsNewBlock(upper, line, text, typical: typical, width: width, height: height) {
                    result.append(Block(text: current, bullet: currentBullet))
                    current = ""
                    currentBullet = bullet
                } else {
                    current += " "
                }
            } else {
                currentBullet = bullet
            }
            current += text
            previous = line
        }
        if !current.isEmpty { result.append(Block(text: current, bullet: currentBullet)) }
        return result
    }

    private static func startsNewBlock(_ upper: TextLine, _ lower: TextLine, _ lowerText: String, typical: Double,
                                       width: Double, height: Double) -> Bool {
        let finished = SubtitleStabilizer.endsSentence(upper.text)
        if !finished, lowerText.first?.isLowercase == true { return false }
        if finished { return true }
        guard let a = upper.box, let b = lower.box, typical > 0 else { return false }
        // Satırlar arasındaki boşluk satır yüksekliğinin %40'ından büyükse ayrı bloklardır.
        if (b.top - a.bottom) * height > typical * 0.4 { return true }
        // Soldan yarım satır yüksekliğinden fazla dışarı çıkıyorsa (girintili devam satırından sonra yeni madde) yeni bloktur.
        return (a.left - b.left) * width > typical * 0.5
    }

    /// Satırın başındaki madde işaretini ayırır. Yazı tanıma ◇ simgesini çoğu zaman "<>" ya da tek başına "o"/"0" okur.
    private static func stripBullet(_ text: String) -> (Bool, String) {
        let characters = Array(text)
        if characters.count >= 2, bulletChars.contains(characters[0]) {
            return (true, String(characters[1...]).trimmingCharacters(in: .whitespaces))
        }
        if text.hasPrefix("<>") { return (true, String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)) }
        if characters.count > 2, characters[1] == " ", characters[0] == "o" || characters[0] == "0", characters[2].isUppercase {
            return (true, String(characters[2...]))
        }
        return (false, text)
    }

    /// Çevirinin TV'de kalma süresi (ms): uzun panel yazısı okunacak kadar durur.
    public static func displayMilliseconds(_ text: String) -> Int {
        min(max(4000 + text.count * 70, 6000), 25000)
    }
}
