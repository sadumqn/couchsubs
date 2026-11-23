// SPDX-License-Identifier: AGPL-3.0-only
#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Yazı tanıma yerine: hep aynı satırı "okur" (Vision testlerde takılabiliyor).
private final class DemoFakeReader: TextReader, @unchecked Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    func read(_ image: CGImage) throws -> String { text }
}
private final class DemoSender: SubtitleSending {
    var sent: [String] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
    func clear() {}
}
/// Dil paketi indirilmemiş ücretsiz çeviri gibi davranır.
private final class MissingModelTranslator: TextTranslator {
    func translate(_ text: String) async throws -> String { throw TranslatorError.needsDownload }
}
private final class EchoTranslator: TextTranslator {
    func translate(_ text: String) async throws -> String { "motor: " + text }
}

@MainActor
final class DemoModeTests: XCTestCase {
    func testScriptHasEnoughLinesWithTurkish() {
        XCTAssertGreaterThanOrEqual(DemoScript.lines.count, 10)
        XCTAssertLessThanOrEqual(DemoScript.lines.count, 15)
        for line in DemoScript.lines + [DemoScript.objective] {
            XCTAssertFalse(line.turkish.isEmpty)
            for brand in ["PS5", "PlayStation", "Sony"] { XCTAssertFalse(line.english.contains(brand)) }
        }
    }

    func testFramesAreDrawnWithAndWithoutSubtitle() throws {
        let blank = try XCTUnwrap(DemoFrames.frame(line: nil))
        let withLine = try XCTUnwrap(DemoFrames.frame(line: 0))
        XCTAssertEqual(blank.width, DemoFrames.width)
        XCTAssertEqual(blank.height, DemoFrames.height)
        // Altyazı bölgesi iki karede farklıdır.
        let region = CropRegion()
        let a = RegionCropper.signature(of: RegionCropper.crop(blank, to: region))
        let b = RegionCropper.signature(of: RegionCropper.crop(withLine, to: region))
        XCTAssertNotEqual(a, b)
    }

    func testScheduleShowsLinesInTurnWithGaps() {
        let source = DemoFrameSource(lineSeconds: 3, gapSeconds: 1)
        XCTAssertNil(source.lineIndex(at: 0.5))
        XCTAssertEqual(source.lineIndex(at: 1.5), 0)
        XCTAssertNil(source.lineIndex(at: 4.5))
        XCTAssertEqual(source.lineIndex(at: 5.5), 1)
        XCTAssertEqual(source.lineIndex(at: 1 + 4 * Double(DemoScript.lines.count) + 0.5), 0)
    }

    func testSourceDeliversFrames() async {
        let source = DemoFrameSource(lineSeconds: 0.2, gapSeconds: 0.05, framesPerSecond: 40)
        let got = expectation(description: "kare")
        got.assertForOverFulfill = false
        source.onFrame = { image in if image.width == DemoFrames.width { got.fulfill() } }
        source.start()
        await fulfillment(of: [got], timeout: 5)
        source.stop()
        XCTAssertFalse(source.isRunning)
    }

    func testTableTranslatesReadingsWithOcrSlips() {
        XCTAssertEqual(DemoScript.translation(for: DemoScript.lines[0].english), DemoScript.lines[0].turkish)
        XCTAssertEqual(DemoScript.translation(for: "We should reach the lighthouse before dark"), DemoScript.lines[0].turkish)
        XCTAssertEqual(DemoScript.translation(for: "We shou1d reach the lighthouse before dark."), DemoScript.lines[0].turkish)
        XCTAssertNil(DemoScript.translation(for: "Completely different text"))
    }

    func testTranslatorUsesEngineAndFallsBackToTable() async throws {
        let line = DemoScript.lines[3]
        let engine = try await DemoTranslator(base: EchoTranslator()).translate(line.english)
        XCTAssertEqual(engine, "motor: " + line.english)
        let fallback = try await DemoTranslator(base: MissingModelTranslator()).translate(line.english)
        XCTAssertEqual(fallback, line.turkish)
        let screen = try await DemoTranslator(base: MissingModelTranslator()).translateAll([DemoScript.objective.english])
        XCTAssertEqual(screen, [DemoScript.objective.turkish])
    }

    /// Deneme karesi gerçek hattan geçer: okunan satır çevrilip TV/telefona gider (dil paketi olmasa da).
    func testPipelineTranslatesAndShowsADemoLine() async throws {
        var time = 0
        let line = DemoScript.lines[1]
        let sender = DemoSender()
        let pipeline = SubtitlePipeline(reader: DemoFakeReader(line.english),
                                        translator: DemoTranslator(base: MissingModelTranslator()),
                                        server: sender, clock: { time })
        pipeline.packWait = 0
        pipeline.cleanWait = 0
        let frame = try XCTUnwrap(DemoFrames.frame(line: 1))
        for _ in 0..<8 {
            await pipeline.process(frame, region: CropRegion())
            time += 200
        }
        await pipeline.waitForTranslations()
        XCTAssertTrue(sender.sent.contains(where: { $0.contains(line.turkish) }), "\(sender.sent)")
        XCTAssertEqual(pipeline.lastPair?.translation, line.turkish)
    }
}
#endif
