// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreText
import Foundation

/// "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde ve boyunda çizilsin, simgeleri örtmesin
/// (Windows: ScreenFit.cs, Android: ScreenFit.kt; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
/// - `Item.room`: kutunun genişleyebileceği yatay alan. Özgün yazının iki yanında, zeminden belirgin ayrılan ilk noktaya
///   (kumanda simgesi, menü simgesi, fotoğraf, başka yazı) kadar, araya satır yüksekliğinin çeyreği boşluk bırakılarak;
///   aynı satırdaki komşu öğeyle arası ortadan bölünür. Kutu bu alanın dışına hiç taşmaz (kenar payı da).
/// - Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa (sağdaki tuş simgelerine yaslı ipuçları) hepsi sağa
///   yaslıdır, sol kenarları aynıysa sola; aynı satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalıdır. Tek
///   kutudan hiza çıkmıyordu, çeviri simgeye doğru uzuyordu.
/// - Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda: satır yükseklikleri ortancaya çekilir.
///   Önceden sığmayan sekme küçülüyor, şerit iki ayrı boyda görünüyordu (#859).
public enum ScreenFit {
    /// Simgeyle (ya da komşu yazıyla) çeviri kutusu arasında bırakılan boşluk, satır yüksekliğinin katı.
    public static let gapLines = 0.25
    /// Kutu her yana en çok bu kadar satır yüksekliği genişleyebilir.
    public static let growLines = 8.0
    /// Eş öğelerin satır yükseklikleri en çok bu oranda farklıysa aynı boya çekilir.
    public static let sameLine = 0.15
    /// Bir sütunda zeminden bu kadar (en büyük renk bileşeni farkı) ayrılan nokta varsa orada simge/yazı başlar.
    public static let inkDistance = 56

    /// Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi.
    public static func fitted(_ items: [ScreenTranslation.Item], frame: CGImage?) -> [ScreenTranslation.Item] {
        guard let frame, frame.width > 0, frame.height > 0, let pixels = GamePhonePixels(frame) else { return items }
        let aspect = Double(frame.width) / Double(frame.height)
        let laid = uniform(aligned(tightened(items, frame: frame, aspect: aspect), aspect: aspect), aspect: aspect)
        return withRoom(laid, aspect: aspect) { x, y in
            let p = pixels.offset(x, y)
            return (Int(pixels.bytes[p]), Int(pixels.bytes[p + 1]), Int(pixels.bytes[p + 2]))
        } size: { (pixels.width, pixels.height) }
    }

    /// Yerleşime giren öğe: özgün stilli, telefon kartının ya da balonun parçası değil.
    public static func takesPart(_ item: ScreenTranslation.Item) -> Bool {
        item.look != nil && !ScreenTranslation.isCardPart(item) && !item.bubble
    }

    /// Kutu yalnız yazının noktalarını kapsar: kutunun ucunda, yazıdan satır yüksekliğinin %60'ından geniş boşlukla ayrılmış
    /// küçük (en çok bir buçuk satır yüksekliği genişliğinde) bir leke varsa o simgedir (yazı tanıma kutusu simgenin kenarını
    /// da alıyordu), kutunun dışında kalır. Simgesi çeviride yerinde gösterilen öğeye dokunulmaz.
    static func tightened(_ items: [ScreenTranslation.Item], frame: CGImage, aspect: Double) -> [ScreenTranslation.Item] {
        var result = items
        for i in items.indices where takesPart(items[i]) && (items[i].icons ?? []).isEmpty {
            let box = items[i].box, lineX = items[i].lineHeight / aspect
            let spans = ScreenTranslation.inkSpans(frame, box, gap: 0.6 * lineX)
            guard spans.count >= 2 else { continue }
            var left = box.left, right = box.right
            if spans[spans.count - 1].right - spans[spans.count - 1].left <= 1.5 * lineX { right = spans[spans.count - 2].right }
            if spans[0].right - spans[0].left <= 1.5 * lineX, spans.count >= 3 || right == box.right { left = spans[1].left }
            guard right - left >= 0.5 * (box.right - box.left) else { continue }
            result[i].box = TextBox(left: left, top: box.top, right: right, bottom: box.bottom)
        }
        return result
    }

    private static func height(_ box: TextBox) -> Double { box.bottom - box.top }

    private static func rowOverlap(_ a: TextBox, _ b: TextBox) -> Double {
        max(0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(height(a), height(b)))
    }

    /// Alt alta dizilmiş (aynı sütundaki) tek satırlık etiketlerin ortak hizası.
    static func aligned(_ items: [ScreenTranslation.Item], aspect: Double) -> [ScreenTranslation.Item] {
        let labels = items.indices.filter { takesPart(items[$0]) && items[$0].rows <= 1 }
        var result = items
        for i in labels {
            let box = items[i].box, tolerance = 0.5 * items[i].lineHeight / aspect
            let column = labels.filter { j in
                j != i && rowOverlap(box, items[j].box) == 0
                    && abs((box.top + box.bottom) - (items[j].box.top + items[j].box.bottom)) / 2 <= 8 * items[i].lineHeight
            }
            let rights = column.filter { abs(items[$0].box.right - box.right) <= tolerance && abs(items[$0].box.left - box.left) > tolerance }
            let lefts = column.filter { abs(items[$0].box.left - box.left) <= tolerance && abs(items[$0].box.right - box.right) > tolerance }
            // Aynı satırda en az iki eşi olan etiket şeridin sekmesidir: sekme yazısı kendi yerinin ortasındadır.
            let row = labels.filter { j in j != i && rowOverlap(box, items[j].box) >= 0.5 }
            if rights.count >= 2, rights.count > lefts.count { result[i].look?.align = .right }
            else if lefts.count >= 2 { result[i].look?.align = .left }
            else if row.count >= 2 { result[i].look?.align = .center }
        }
        return result
    }

    /// Eş öğeler (aynı satırda ya da aynı sütunda, BÜYÜK HARF/kalınlık aynı, satır yüksekliği yakın) aynı boyda.
    static func uniform(_ items: [ScreenTranslation.Item], aspect: Double) -> [ScreenTranslation.Item] {
        let labels = items.indices.filter { takesPart(items[$0]) && items[$0].rows <= 1 }
        var parent = Dictionary(uniqueKeysWithValues: labels.map { ($0, $0) })
        func root(_ i: Int) -> Int { var i = i; while parent[i]! != i { i = parent[i]! }; return i }
        for a in labels {
            for b in labels where b > a {
                let x = items[a], y = items[b]
                guard x.look?.upper == y.look?.upper, x.look?.bold == y.look?.bold,
                      abs(x.lineHeight - y.lineHeight) <= sameLine * max(x.lineHeight, y.lineHeight) else { continue }
                let tolerance = 0.5 * max(x.lineHeight, y.lineHeight) / aspect
                let sameRow = rowOverlap(x.box, y.box) >= 0.5
                let sameColumn = (abs(x.box.left - y.box.left) <= tolerance || abs(x.box.right - y.box.right) <= tolerance)
                    && abs(x.box.top - y.box.top) <= 3 * max(x.lineHeight, y.lineHeight)
                if sameRow || sameColumn { parent[root(a)] = root(b) }
            }
        }
        var result = items
        for members in Dictionary(grouping: labels, by: root).values where members.count >= 2 {
            let lines = members.map { items[$0].lineHeight }.sorted()
            let median = lines[lines.count / 2]
            for i in members { result[i].lineHeight = median }
        }
        return result
    }

    /// Her öğenin genişleyebileceği yatay alan (`Item.room`). `color(x, y)`: karenin noktası (piksel), `size`: kare boyu.
    static func withRoom(_ items: [ScreenTranslation.Item], aspect: Double, color: (Int, Int) -> (Int, Int, Int),
                         size: () -> (Int, Int)) -> [ScreenTranslation.Item] {
        let (frameWidth, frameHeight) = size()
        var result = items
        for i in items.indices where takesPart(items[i]) {
            let item = items[i], box = item.box
            let lineX = item.lineHeight / aspect
            let gap = gapLines * lineX
            var left = max(0, box.left - growLines * lineX), right = min(1, box.right + growLines * lineX)
            // Aynı satırdaki komşu öğeyle arası ortadan bölünür: iki çeviri birbirine doğru büyüse de binmez.
            for (j, other) in items.enumerated() where j != i && rowOverlap(box, other.box) >= 0.3 {
                if other.box.left >= box.right - 1e-9 { right = min(right, (box.right + other.box.left) / 2) }
                if other.box.right <= box.left + 1e-9 { left = max(left, (other.box.right + box.left) / 2) }
            }
            let background = item.style.flatMap { SpeakerColors.rgb($0.background) }
                .map { (Int($0.red * 255), Int($0.green * 255), Int($0.blue * 255)) }
            if let background {
                let y0 = Int(((box.top + 0.2 * height(box)) * Double(frameHeight)).rounded())
                let y1 = Int(((box.bottom - 0.2 * height(box)) * Double(frameHeight)).rounded())
                let rows = stride(from: y0, through: max(y0, y1), by: max(1, (y1 - y0) / 6)).map { min(frameHeight - 1, max(0, $0)) }
                func scan(from start: Double, to end: Double) -> Double? {
                    let a = Int((start * Double(frameWidth)).rounded()), b = Int((end * Double(frameWidth)).rounded())
                    guard a != b else { return nil }
                    let step = b > a ? 1 : -1
                    var ground = background
                    for x in stride(from: a, to: b, by: step) where x >= 0 && x < frameWidth {
                        var far = 0
                        var sum = (0, 0, 0)
                        for y in rows {
                            let c = color(x, y)
                            far = max(far, abs(c.0 - ground.0), abs(c.1 - ground.1), abs(c.2 - ground.2))
                            sum = (sum.0 + c.0, sum.1 + c.1, sum.2 + c.2)
                        }
                        if far > inkDistance { return Double(x) / Double(frameWidth) }
                        // Degrade zeminde (yarı saydam şerit, harita) zemin rengi yavaşça izlenir.
                        let n = rows.count
                        ground = ((ground.0 * 7 + sum.0 / n) / 8, (ground.1 * 7 + sum.1 / n) / 8, (ground.2 * 7 + sum.2 / n) / 8)
                    }
                    return nil
                }
                // Tarama kutunun iki piksel dışından başlar: yazı tanıma kutusu harfin kenarında biter.
                let edge = 2.0 / Double(frameWidth)
                if let ink = scan(from: box.right + edge, to: right) { right = min(right, ink - gap) }
                if let ink = scan(from: box.left - edge, to: left) { left = max(left, ink + gap) }
            }
            result[i].room = TextBox(left: min(box.left, left), top: box.top, right: max(box.right, right), bottom: box.bottom)
        }
        return result
    }
    // MARK: - Çizicilerin ortak satır yerleşimi (TV fitStyled ile aynı sıra)

    /// Bir çevirinin çizimi: satırları, yatay sıkıştırması ve yazının alanının yeri (piksel). Yazı boyu hiç değişmez.
    public struct Lines: Equatable, Sendable {
        public var lines: [String]
        /// Yalnız yatay ölçek (1 = sıkıştırma yok, en az `minSqueeze`).
        public var squeeze: Double
        public var left: Double
        public var width: Double
    }

    /// Önce yalnız yatay sıkıştırma bu orana kadar, sonra genişleme, en son `minSqueeze`'e kadar (TV ile aynı).
    public static let firstSqueeze = 0.8
    public static let minSqueeze = 0.7

    /// Çeviriyi özgün yazının alanına yerleştirir. `measure`: yazının çizicinin kendi yazı tipiyle, sabit yazı boyunda
    /// genişliği (piksel). `room`: genişleyebileceği alan (piksel; yoksa kutunun kendisi). `rows`: özgün satır sayısı.
    /// Özgün tek satırlık kısa etiket (en çok iki sözcük) tek satır kalır; uzun yazı özgün satır sayısına bölünür.
    public static func lines(_ text: String, left: Double, width: Double, room: (left: Double, right: Double)?, rows: Int,
                             align: TextLook.Align, measure: (String) -> Double) -> Lines {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var lines = text.components(separatedBy: "\n")
        let count = max(rows, lines.count)
        if lines.count == 1, count > 1 || (words.count > 2 && measure(text) > width / minSqueeze) {
            // Sözcükler eşit uzunlukta satırlara: özgün yazı çok satırlıysa en çok o kadar satır; tek satırlık uzun yazı
            // (son çare) gerektiği kadar satıra iner.
            let cap = count > 1 ? count : Int.max
            let target = max(width / firstSqueeze, measure(text) / Double(max(1, count)))
            lines = []
            var current = ""
            for word in words {
                let next = current.isEmpty ? word : current + " " + word
                if !current.isEmpty, measure(next) > target, lines.count < cap - 1 { lines.append(current); current = word }
                else { current = next }
            }
            if !current.isEmpty { lines.append(current) }
        }
        let widest = lines.map(measure).max() ?? 0
        var a = left, b = left + width
        let r0 = min(left, room?.left ?? left), r1 = max(left + width, room?.right ?? left + width)
        var squeeze = widest > 0 ? min(1, (b - a) / widest) : 1
        if squeeze < firstSqueeze {
            // Hizanın tersine genişleme; alan bitince öbür yana.
            let extra = widest * firstSqueeze - (b - a)
            var l = align == .right ? extra : align == .center ? extra / 2 : 0
            var r = extra - l
            let freeL = a - r0, freeR = r1 - b
            if r > freeR { l += r - freeR; r = freeR }
            if l > freeL { r = min(freeR, r + l - freeL); l = freeL }
            a -= l
            b += r
            squeeze = max(minSqueeze, min(1, (b - a) / widest))
        }
        return Lines(lines: lines, squeeze: squeeze, left: a, width: b - a)
    }

    /// Mac ve iPhone çizicilerinin ölçüsü: sistem yazı tipiyle (SwiftUI `.system`) yazının genişliği. Kalın değilse
    /// çiziciler yarı kalın çizer; düz yazı tipiyle ölçülüp %4 pay bırakılır.
    public static func textWidth(_ text: String, size: CGFloat, bold: Bool) -> CGFloat {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) * (bold ? 1 : 1.04)
    }
}
