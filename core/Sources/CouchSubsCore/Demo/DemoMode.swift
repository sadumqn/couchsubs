// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreText
import Foundation

/// Deneme modu: konsol olmadan uygulamanın bütün hattını gösterir (App Store incelemesi ve merak eden kullanıcı için).
/// Konsol akışının yerine `DemoFrameSource` kod içinde çizilmiş "oyun" kareleri verir; kareler gerçek hattan geçer
/// (bölge, yazı tanıma, kararlılık, çeviri, TV/telefon). Görseller ve satırlar bizimdir: oyun, marka ya da logo yoktur.
public enum DemoScript {
    public struct Line: Equatable, Sendable {
        public let english: String
        public let turkish: String
    }

    /// Döngüde sırayla gösterilen altyazılar (özgün, telifsiz macera diyalogları).
    public static let lines: [Line] = [
        Line(english: "We should reach the lighthouse before dark.", turkish: "Hava kararmadan deniz fenerine varmalıyız."),
        Line(english: "The bridge is gone. We need another way across.", turkish: "Köprü yıkılmış. Karşıya geçmek için başka bir yol lazım."),
        Line(english: "Stay close to me and keep your voice down.", turkish: "Yanımdan ayrılma ve sesini alçak tut."),
        Line(english: "I found a map in the old captain's cabin.", turkish: "Yaşlı kaptanın kamarasında bir harita buldum."),
        Line(english: "Do you hear that? Something is moving in the fog.", turkish: "Duydun mu? Siste bir şey hareket ediyor."),
        Line(english: "Light the lantern. We can't see a thing out here.", turkish: "Feneri yak. Burada hiçbir şey göremiyoruz."),
        Line(english: "The storm will reach the harbor within an hour.", turkish: "Fırtına bir saat içinde limana ulaşacak."),
        Line(english: "If we take the boat, we can be there by morning.", turkish: "Tekneyi alırsak sabaha orada olabiliriz."),
        Line(english: "Thank you for coming back for me.", turkish: "Benim için geri döndüğün için teşekkürler."),
        Line(english: "Keep the key safe. We will need it at the gate.", turkish: "Anahtarı sakla. Kapıda ona ihtiyacımız olacak."),
        Line(english: "Follow the river north until you see the tower.", turkish: "Kuleyi görene kadar nehri kuzeye doğru takip et."),
        Line(english: "Rest now. Tomorrow will be a long day.", turkish: "Şimdi dinlen. Yarın uzun bir gün olacak."),
    ]

    /// Karenin sol üstündeki görev yazısı ("Ekranı çevir" ve ek alanlar bunu da çevirir).
    public static let objective = Line(english: "Objective: Reach the lighthouse", turkish: "Görev: Deniz fenerine ulaş")

    /// Gömülü hazır çeviri: okunan metin örnek satırlardan birine benziyorsa Türkçesi (ağ ve anahtar gerekmez).
    public static func translation(for text: String) -> String? {
        let wanted = TextMatch.normalize(text)
        guard !wanted.isEmpty else { return nil }
        let all = lines + [objective]
        if let exact = all.first(where: { TextMatch.normalize($0.english) == wanted }) { return exact.turkish }
        return all.first(where: { TextMatch.isSimilar(TextMatch.normalize($0.english), wanted, threshold: 0.8) })?.turkish
    }
}

/// Deneme karelerini CoreGraphics ile çizer: düz bir kıyı sahnesi, sol üstte görev yazısı, altta İngilizce altyazı.
public enum DemoFrames {
    public static let width = 1280
    public static let height = 720
    /// Altyazının karede durduğu yer (üstten oran); varsayılan altyazı bölgesinin (0.62–0.97) içindedir.
    public static let subtitleBaseline = 0.86

    /// `line`: gösterilen altyazının sırası (nil: altyazısız kare). `scene`: arka planın tonu (satır gruplarıyla değişir).
    public static func frame(line: Int?, scene: Int = 0) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        drawScene(in: context, scene: scene)
        drawText(DemoScript.objective.english, in: context, size: 24, x: 48, top: 0.08, centered: false, box: true)
        if let line {
            let text = DemoScript.lines[((line % DemoScript.lines.count) + DemoScript.lines.count) % DemoScript.lines.count].english
            drawText(text, in: context, size: 36, x: nil, top: subtitleBaseline, centered: true, box: true)
        }
        return context.makeImage()
    }

    /// Gökyüzü, deniz, tepe ve deniz feneri (CoreGraphics'in ekseni alttan yukarı).
    private static func drawScene(in context: CGContext, scene: Int) {
        let w = CGFloat(width), h = CGFloat(height)
        let palettes: [(sky: [CGFloat], horizon: [CGFloat], sea: [CGFloat], land: [CGFloat])] = [
            ([0.16, 0.22, 0.42], [0.86, 0.55, 0.38], [0.10, 0.24, 0.36], [0.12, 0.20, 0.16]),
            ([0.08, 0.10, 0.22], [0.36, 0.30, 0.50], [0.06, 0.14, 0.24], [0.08, 0.12, 0.12]),
            ([0.30, 0.46, 0.62], [0.78, 0.82, 0.80], [0.16, 0.34, 0.44], [0.20, 0.30, 0.20]),
        ]
        let palette = palettes[((scene % palettes.count) + palettes.count) % palettes.count]
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: [color(palette.horizon), color(palette.sky)] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h * 0.38), end: CGPoint(x: 0, y: h), options: [.drawsAfterEndLocation])
        }
        // Güneş ya da ay.
        context.setFillColor(color([1, 0.92, 0.75], alpha: 0.85))
        context.fillEllipse(in: CGRect(x: w * 0.70, y: h * 0.52, width: 90, height: 90))
        // Deniz.
        context.setFillColor(color(palette.sea))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.40))
        // Dalga çizgileri.
        context.setStrokeColor(color([1, 1, 1], alpha: 0.12))
        context.setLineWidth(2)
        for row in 0..<6 {
            let y = h * 0.36 - CGFloat(row) * 38
            context.move(to: CGPoint(x: 0, y: y))
            for step in stride(from: 0, through: Int(w), by: 40) {
                context.addLine(to: CGPoint(x: CGFloat(step), y: y + (step / 40 % 2 == 0 ? 4 : -4)))
            }
            context.strokePath()
        }
        // Kıyıdaki tepe.
        context.setFillColor(color(palette.land))
        context.move(to: CGPoint(x: 0, y: h * 0.40))
        context.addCurve(to: CGPoint(x: w * 0.42, y: h * 0.40), control1: CGPoint(x: w * 0.06, y: h * 0.60),
                         control2: CGPoint(x: w * 0.30, y: h * 0.58))
        context.closePath()
        context.fillPath()
        // Deniz feneri: gövde, şeritler, ışık odası ve ışık.
        let baseX = w * 0.16, baseY = h * 0.50
        context.setFillColor(color([0.93, 0.92, 0.88]))
        context.move(to: CGPoint(x: baseX - 26, y: baseY))
        context.addLine(to: CGPoint(x: baseX + 26, y: baseY))
        context.addLine(to: CGPoint(x: baseX + 16, y: baseY + 150))
        context.addLine(to: CGPoint(x: baseX - 16, y: baseY + 150))
        context.closePath()
        context.fillPath()
        context.setFillColor(color([0.72, 0.20, 0.18]))
        context.fill(CGRect(x: baseX - 22, y: baseY + 40, width: 44, height: 18))
        context.fill(CGRect(x: baseX - 19, y: baseY + 95, width: 38, height: 16))
        context.setFillColor(color([1, 0.88, 0.45]))
        context.fill(CGRect(x: baseX - 14, y: baseY + 150, width: 28, height: 22))
        context.setFillColor(color([1, 0.88, 0.45], alpha: 0.18))
        context.move(to: CGPoint(x: baseX, y: baseY + 161))
        context.addLine(to: CGPoint(x: w * 0.55, y: baseY + 210))
        context.addLine(to: CGPoint(x: w * 0.55, y: baseY + 120))
        context.closePath()
        context.fillPath()
    }

    /// Yazı, okunaklı olsun diye yarı saydam koyu kutunun üstünde beyaz çizilir (oyunlardaki altyazı gibi).
    /// `top`: satırın taban çizgisinin üstten oranı. `x`: sola yaslı yazının başladığı yer (ortalıysa nil).
    private static func drawText(_ text: String, in context: CGContext, size: CGFloat, x: CGFloat?, top: Double,
                                 centered: Bool, box: Bool) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color([1, 1, 1]),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let originX = centered ? (CGFloat(width) - bounds.width) / 2 : (x ?? 0)
        let baseline = CGFloat(height) * CGFloat(1 - top)
        if box {
            let pad: CGFloat = size * 0.45
            let rect = CGRect(x: originX - pad, y: baseline + bounds.minY - pad * 0.6,
                              width: bounds.width + pad * 2, height: bounds.height + pad * 1.2)
            context.setFillColor(color([0, 0, 0], alpha: 0.62))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.fillPath()
        }
        context.textPosition = CGPoint(x: originX, y: baseline)
        CTLineDraw(line, context)
    }

    private static func color(_ rgb: [CGFloat], alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [rgb[0], rgb[1], rgb[2], alpha])!
    }
}

/// Konsol akışının yerine deneme karelerini saniyede birkaç kez verir. Her satır `lineSeconds` boyunca görünür,
/// ardından `gapSeconds` altyazısız kare gelir (satırlar ayrı ayrı okunsun); satırlar döngüde sürer.
public final class DemoFrameSource: @unchecked Sendable {
    public var onFrame: ((CGImage) -> Void)?
    public let lineSeconds: Double
    public let gapSeconds: Double
    public let framesPerSecond: Double
    private var task: Task<Void, Never>?

    public init(lineSeconds: Double = 3.6, gapSeconds: Double = 0.9, framesPerSecond: Double = 5) {
        self.lineSeconds = lineSeconds
        self.gapSeconds = gapSeconds
        self.framesPerSecond = framesPerSecond
    }

    public var isRunning: Bool { task != nil }

    /// Başlangıçtan `elapsed` saniye sonra gösterilen satırın sırası (altyazısız aralıkta nil). İlk satır kısa bir
    /// boş karenin ardından gelir.
    public func lineIndex(at elapsed: Double) -> Int? {
        let shifted = elapsed - gapSeconds
        guard shifted >= 0 else { return nil }
        let cycle = lineSeconds + gapSeconds
        let position = shifted.truncatingRemainder(dividingBy: cycle)
        guard position < lineSeconds else { return nil }
        return Int(shifted / cycle) % DemoScript.lines.count
    }

    public func start() {
        stop()
        let begin = Date()
        let interval = UInt64(1_000_000_000 / max(1, framesPerSecond))
        task = Task.detached(priority: .userInitiated) { [weak self] in
            var shown: Int?? = .none
            var image: CGImage?
            while !Task.isCancelled {
                guard let self else { return }
                let line = self.lineIndex(at: Date().timeIntervalSince(begin))
                if shown != .some(line) {
                    image = DemoFrames.frame(line: line, scene: (line ?? 0) / 4)
                    shown = .some(line)
                }
                if let image { self.onFrame?(image) }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}

/// Deneme modunun çevirmeni: seçili motor (varsayılanı cihazdaki ücretsiz çeviri) çevirir; motor çeviremezse (dil
/// paketi indirilmemiş, sistem eski, ağ ya da anahtar yok) örnek satırların gömülü hazır çevirisi gösterilir. Böylece
/// deneme modu internet ve anahtar olmadan da baştan sona çalışır.
public final class DemoTranslator: TextTranslator {
    private let base: TextTranslator?

    public init(base: TextTranslator?) {
        self.base = base
    }

    public func translate(_ text: String) async throws -> String {
        if let base {
            do {
                let result = try await base.translate(text)
                if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return result }
            } catch is CancellationError {
                throw CancellationError()
            } catch {}
        }
        return DemoScript.translation(for: text) ?? text
    }

    public func translateAll(_ texts: [String]) async throws -> [String] {
        if let base, let results = try? await base.translateAll(texts), results.count == texts.count { return results }
        return texts.map { DemoScript.translation(for: $0) ?? $0 }
    }

    public func warmUp() async { await base?.warmUp() }

    public func spokenLines(for text: String) -> [SpokenLine] { base?.spokenLines(for: text) ?? [] }

    public var translatesTogether: Bool { base?.translatesTogether ?? false }

    public func noteSpeaker(_ name: String) { base?.noteSpeaker(name) }
}
