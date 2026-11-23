// SPDX-License-Identifier: AGPL-3.0-only
#if os(macOS)
import CoreGraphics
import CoreText
import XCTest
@testable import CouchSubsCore

/// #679: asıl süreçteki Vision takılınca okuma ayrı süreçte sürer.
final class OcrHelperTests: XCTestCase {
    /// `swift test` yardımcıyı test paketinin yanına derler.
    private var helper: URL {
        let products = Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }!.bundleURL.deletingLastPathComponent()
        return products.appendingPathComponent("ocr-helper")
    }

    private func image(_ text: String, width: Int = 900, height: Int = 120) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
        context.textPosition = CGPoint(x: 40, y: 40)
        CTLineDraw(line, context)
        return context.makeImage()!
    }

    func testReadingSurvivesTheWire() throws {
        let reading = Reading(lines: [
            TextLine("We need to go. Now!", box: TextBox(left: 0.1, top: 0.2, right: 0.9, bottom: 0.4), confidence: 0.93,
                     words: [TextWord("We", box: TextBox(left: 0.1, top: 0.2, right: 0.2, bottom: 0.4))]),
            TextLine("İkinci satır"),
        ])
        let data = try JSONEncoder().encode(OcrHelper.Reply(lines: OcrHelper.encode(reading)))
        let back = OcrHelper.decode(try JSONDecoder().decode(OcrHelper.Reply.self, from: data).lines ?? [])
        XCTAssertEqual(back, reading)
    }

    func testPixelsRoundTrip() throws {
        let source = image("Hello")
        let pixels = try XCTUnwrap(OcrHelper.pixels(of: source))
        let back = try XCTUnwrap(OcrHelper.image(from: pixels, width: source.width, height: source.height))
        XCTAssertEqual(OcrHelper.pixels(of: back), pixels)
        XCTAssertNil(OcrHelper.image(from: pixels.dropLast(), width: source.width, height: source.height))
    }

    /// Yardımcı döngüsü borular üzerinden: kareyi alır, okuyucunun verdiği satırları geri yollar; giriş kapanınca çıkar.
    func testServeAnswersFramesUntilInputCloses() throws {
        let toHelper = Pipe(), fromHelper = Pipe()
        let served = expectation(description: "yardımcı döngüsü bitti")
        Thread.detachNewThread {
            OcrHelper.serve(input: toHelper.fileHandleForReading.fileDescriptor, output: fromHelper.fileHandleForWriting.fileDescriptor) { image, language, fast in
                Reading(text: "\(image.width)x\(image.height) \(language) \(fast ? "hızlı" : "isabetli")")
            }
            served.fulfill()
        }
        let frame = image("x", width: 32, height: 16)
        for fast in [true, false] {
            let head = try JSONEncoder().encode(OcrHelper.Header(width: 32, height: 16, language: "en", fast: fast))
            XCTAssertTrue(OcrHelper.write(head, to: toHelper.fileHandleForWriting.fileDescriptor))
            XCTAssertTrue(OcrHelper.write(try XCTUnwrap(OcrHelper.pixels(of: frame)), to: toHelper.fileHandleForWriting.fileDescriptor))
            let reply = try JSONDecoder().decode(OcrHelper.Reply.self, from: try XCTUnwrap(OcrHelper.read(from: fromHelper.fileHandleForReading.fileDescriptor)))
            XCTAssertEqual(reply.lines?.first?.t, "32x16 en \(fast ? "hızlı" : "isabetli")")
        }
        try toHelper.fileHandleForWriting.close()
        wait(for: [served], timeout: 5)
    }

    /// Gerçek yardımcı süreç gerçek Vision ile okur (hızlı düzey: model derlemesi beklemez).
    func testHelperProcessReadsText() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: helper.path), "ocr-helper derlenmemiş")
        let rescuer = OcrHelperRescuer(executable: helper, arguments: [])
        defer { rescuer.standDown() }
        let started = Date()
        let reading = try rescuer.recognize(image("We need to go now"), language: "en")
        XCTAssertTrue(reading.text.lowercased().contains("need to go"), reading.text)
        XCTAssertNotNil(reading.lines.first?.box)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "hızlı düzey soğuk açılışta da saniyeler içinde dönmeli")
        XCTAssertFalse(rescuer.isAccurate)
        // Aynı süreç sonraki kareleri de okur.
        XCTAssertTrue(try rescuer.recognize(image("Second line here"), language: "en").text.lowercased().contains("second line"))
    }

    /// Yardımcı öldürülürse (takıldığı için bırakıldı) süren okuma hata ile döner, sonraki okuma yeni süreçte yapılır.
    func testAbandonedHelperIsReplaced() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: helper.path), "ocr-helper derlenmemiş")
        let rescuer = OcrHelperRescuer(executable: helper, arguments: [])
        defer { rescuer.standDown() }
        _ = try rescuer.recognize(image("First"), language: "en")
        rescuer.abandon()
        // `abandon` yalnız süren okumanın sürecini öldürür; boştaysa bir şey yapmaz, okuma sürer.
        XCTAssertTrue(try rescuer.recognize(image("Still reading fine"), language: "en").text.lowercased().contains("reading"))
    }

    /// Açılamayan yardımcı (ör. dosya yok) hattı kilitlemez: birkaç denemeden sonra `stuck` döner.
    func testMissingHelperGivesUp() {
        let rescuer = OcrHelperRescuer(executable: URL(fileURLWithPath: "/nonexistent/ocr-helper"), arguments: [])
        for _ in 0..<OcrHelperRescuer.maxLaunchFailures {
            XCTAssertThrowsError(try rescuer.recognize(image("x"), language: "en")) { XCTAssertEqual($0 as? OcrHelper.Failure, .closed) }
        }
        XCTAssertThrowsError(try rescuer.recognize(image("x"), language: "en")) { XCTAssertEqual($0 as? ReadQueueError, .stuck) }
    }

    /// Uçtan uca: asıl okuyucuda asla dönmeyen okuma → sıradaki kareler yardımcı süreçte gerçek Vision ile okunur.
    func testQueueRescuesThroughHelperProcess() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: helper.path), "ocr-helper derlenmemiş")
        let queue = ReadQueue(label: "test.helper", timeoutMs: 3000)
        let rescuer = OcrHelperRescuer(executable: helper, arguments: [])
        queue.rescuer = rescuer
        defer { rescuer.standDown() }
        let hang = DispatchSemaphore(value: 0)
        defer { hang.signal() }
        _ = try? await queue.run { hang.wait() }
        XCTAssertTrue(queue.isRescuing)
        let reader = VisionReader(language: "en")
        let frame = image("They invite you on the yacht")
        // İlk okuma süreci açar; süre aşımına takılırsa yeniden denenir.
        var text = ""
        for _ in 0..<5 where text.isEmpty {
            text = (try? await queue.run { try reader.readLines(frame, deep: false).text }) ?? ""
        }
        XCTAssertTrue(text.lowercased().contains("yacht"), text)
    }
}
#endif
