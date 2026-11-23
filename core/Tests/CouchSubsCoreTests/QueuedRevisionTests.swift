// SPDX-License-Identifier: AGPL-3.0-only
#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import CouchSubsCore

private final class QueuedReader: TextReader, @unchecked Sendable {
    var texts: [String]
    init(_ texts: [String]) { self.texts = texts }
    func read(_ image: CGImage) throws -> String { texts.isEmpty ? "" : texts.removeFirst() }
}
private final class QueuedSender: SubtitleSending {
    var sent: [String] = []
    func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
    func clear() {}
}
private final class QueuedTranslator: TextTranslator {
    var requested: [String] = []
    var open = false
    var gates: [CheckedContinuation<Void, Never>] = []
    func translate(_ text: String) async throws -> String {
        requested.append(text)
        if !open { await withCheckedContinuation { gates.append($0) } }
        return "Çeviri: " + String(requested.count)
    }
    func release() { open = true; gates.forEach { $0.resume() }; gates.removeAll() }
}

@MainActor
final class QueuedRevisionTests: XCTestCase {
    private let blocker = "Hold the gate."
    private let full = "Huh? Jumping out of airplanes, flying like birds? Fuck, that is crazy."
    private let short = "Huh? Jumping out of airplanes, flying like birds?"
    private var image: CGImage {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private func replay(_ readings: [String]) async -> [String] {
        var time = 0
        let translator = QueuedTranslator(), sender = QueuedSender()
        let frames = [blocker] + readings
        let pipeline = SubtitlePipeline(reader: QueuedReader(frames), translator: translator, server: sender, clock: { time })
        pipeline.packWait = 0; pipeline.cleanWait = 0; pipeline.holdReadings = true
        for (index, _) in frames.enumerated() {
            await pipeline.process(image, region: CropRegion())
            if index == 0 {
                for _ in 0..<1000 { if !translator.requested.isEmpty { break }; await Task.yield() }
                XCTAssertEqual(translator.requested, [blocker])
            }
            time += 100
        }
        translator.release()
        await pipeline.waitForTranslations()
        XCTAssertEqual(sender.sent.count, translator.requested.count)
        return translator.requested
    }
    func testShorterReadingDoesNotEraseQueuedFullLine() async {
        let withoutReturn = await replay([full, short])
        XCTAssertEqual(withoutReturn, [blocker, full, short])
        let returned = await replay([full, short, full])
        XCTAssertEqual(returned, [blocker, full])
    }
    func testGenuineShortLineKeepsBothQueuedUtterances() async {
        for (full, short) in [("Run! Wait here.", "Run!"),
            ("I swear to God, you kill me!", "You kill me!"),
            ("Hold your fire until I return.", "Get down!")] {
            let requested = await replay([full, short])
            XCTAssertEqual(requested, [blocker, full, short])
        }
    }
    func testCorrectedReadingReplacesOlderQueuedReading() async {
        for (old, corrected) in [("We have 5 minutes left.", "We have 1 minute left."),
            ("Meet me at 06:40.", "Meet me at 06:50."),
            ("I can do that for you right now.", "I can't do that for you right now."),
            ("We have time to wait.", "We have no time to wait."),
            ("We do not have...", "We do not have time.")] {
            let requested = await replay([old, corrected])
            XCTAssertEqual(requested, [blocker, corrected])
        }
    }
    func testFullReadingReturningAfterRestoreWindowStillCoalescesTheQueue() async {
        let requested = await replay([full] + Array(repeating: short, count: 18) + [full])
        XCTAssertEqual(requested, [blocker, full])
    }
    func testConfirmedBlankKeepsTheInterveningShortUtterance() async {
        let requested = await replay([full, short] + Array(repeating: "", count: 12) + [full])
        XCTAssertEqual(requested, [blocker, full, short])
    }
}
#endif
