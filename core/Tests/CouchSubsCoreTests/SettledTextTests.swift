// SPDX-License-Identifier: AGPL-3.0-only
#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import XCTest
@testable import CouchSubsCore

private final class MenuReader: TextReader, @unchecked Sendable {
    var texts: [String]
    init(_ texts: [String]) { self.texts = texts }
    func read(_ image: CGImage) throws -> String { texts.isEmpty ? "" : texts.removeFirst() }
}
private final class MenuSender: SubtitleSending {
    var sent: [String] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
    func clear() {}
}
private final class MenuTranslator: TextTranslator {
    var requested: [String] = []
    func translate(_ text: String) async throws -> String {
        requested.append(text)
        return "TR: " + text
    }
}

/// PS5'in Türkçe ana ekranı (beta.89, Mac): Türkçe harfleri düz okunan menü satırı çevrilmez ve paketle eşleşmez, bozuk
/// okunmuş parçası ("One [Ikan Ipufl") altyazı sayılmaz, değişmeyen ekranda aynı satır yeniden işlenmez. Ortak deneme
/// dosyası Fixtures/settled-text.json (Windows SettledTextTests.cs ve Android SettledTextTest.kt aynı dosyayı okur).
@MainActor
final class SettledTextTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Turkish: Decodable { let text: String; let turkish: Bool }
        struct Bracket: Decodable { let text: String; let garbled: Bool }
        struct Case: Decodable { let text: String; let box: [Double]?; let fragment: Bool }
        struct Fragment: Decodable { let target: String; let box: [Double]?; let cases: [Case] }
        struct Step: Decodable {
            let time: Int
            let observe: [String]?
            let settle: String?
            let target: Bool?
            let shown: Bool?
            let loose: Bool?
            let ask: String?
            let settled: Bool?
        }
        struct Settle: Decodable { let name: String; let steps: [Step] }
        struct Frame: Decodable { let text: String; let count: Int }
        struct Pipeline: Decodable { let pack: String; let packText: String; let cycles: Int; let frames: [Frame] }
        let turkish: [Turkish]
        let bracket: [Bracket]
        let fragment: [Fragment]
        let settle: [Settle]
        let pipeline: Pipeline
    }

    private func vectors() throws -> Vectors {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("settled-text.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private static func box(_ values: [Double]?) -> TextBox? {
        values.map { TextBox(left: $0[0], top: $0[1], right: $0[2], bottom: $0[3]) }
    }

    func testTurkishMenuLines() throws {
        for vector in try vectors().turkish {
            XCTAssertEqual(TurkishText.looksTurkish(vector.text), vector.turkish, vector.text)
        }
    }

    func testBracketGarbledReadings() throws {
        for vector in try vectors().bracket {
            XCTAssertEqual(OcrNoise.looksBracketGarbled(vector.text), vector.garbled, vector.text)
        }
    }

    func testFragmentsOfTargetLanguageBlock() throws {
        for vector in try vectors().fragment {
            var settled = SettledText()
            settled.settle(vector.target, box: Self.box(vector.box), target: true, shown: false, at: 0)
            for item in vector.cases {
                XCTAssertEqual(settled.isTargetFragment(item.text, box: Self.box(item.box)), item.fragment, item.text)
            }
        }
    }

    func testSettledLinesStayQuietWhileOnScreen() throws {
        for vector in try vectors().settle {
            var settled = SettledText()
            for step in vector.steps {
                if let lines = step.observe { settled.observe(lines, at: step.time) }
                if let source = step.settle {
                    settled.settle(source, box: nil, target: step.target ?? false, shown: step.shown ?? false,
                                   loose: step.loose ?? false, at: step.time)
                }
                if let source = step.ask { XCTAssertEqual(settled.isSettled(source), step.settled, "\(vector.name): \(source)") }
            }
        }
    }

    private var image: CGImage {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// Mac altyazi.log'undaki döngü: menü satırları sırayla seçilir, hiçbiri çevirmene ya da TV'ye gitmez, paketteki bozuk
    /// parça gösterilmez, her satır günlüğe en çok bir kez düşer.
    func testTurkishMenuLoopStaysQuiet() async throws {
        let vector = try vectors().pipeline
        var frames: [String] = []
        for _ in 0..<vector.cycles { for frame in vector.frames { frames += Array(repeating: frame.text, count: frame.count) } }
        var time = 0
        let translator = MenuTranslator(), sender = MenuSender()
        let pipeline = SubtitlePipeline(reader: MenuReader(frames), translator: translator, server: sender, clock: { time })
        pipeline.packLookup = { $0 == vector.pack ? PackMatch(text: vector.packText, spoken: []) : nil }
        var log: [String] = []
        pipeline.onLog = { log.append($0) }
        for _ in frames {
            await pipeline.process(image, region: CropRegion())
            await pipeline.waitForTranslations()
            time += 100
        }
        XCTAssertEqual(translator.requested, [])
        XCTAssertEqual(sender.sent, [])
        XCTAssertFalse(log.contains { $0.contains("→ paket") }, log.joined(separator: "\n"))
        for frame in vector.frames {
            let excerpt = SubtitleLog.excerpt(frame.text)
            let drops = log.filter { $0.contains(excerpt) && $0.contains("çevrilmedi") }
            XCTAssertLessThanOrEqual(drops.count, 1, "\(frame.text)\n" + log.joined(separator: "\n"))
        }
    }
}
#endif
