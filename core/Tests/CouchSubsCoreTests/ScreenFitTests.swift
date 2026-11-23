// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// "Ekranı çevir"in yerleşim ölçütü, gerçek GTA 6 menü/görev karelerinin kayıtlı okumalarıyla (testdata/frames/ocr/screen;
/// yazı tanıma koşmaz). Her çeviri kutusu özgün yazının yerinde olmalı (sapma satır yüksekliğinin en çok %10'u), kumanda
/// simgelerini ve fotoğrafları (frames.json → screen.clear) hiç örtmemeli, kutular birbirine binmemeli; önbellekteki
/// yazılar çeviri beklemeden ilk bildirimde gelmeli. TV'deki çizim ölçütü: scripts/tv-screen-fit.test.js (bu testin
/// `SCREEN_FIT_OUT` ile yazdığı öğelerle).
final class ScreenFitTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Screen: Decodable { let blocks: [String]; let clear: [[Double]]? }
        struct Frame: Decodable { let id: String; let file: String; let screen: Screen? }
        let frames: [Frame]
    }

    private struct Fixture: Decodable {
        struct Word: Decodable { let text: String; let box: [Double] }
        struct Line: Decodable { let text: String; let box: [Double]?; let confidence: Double?; let words: [Word]? }
        let lines: [Line]
    }

    /// Ölçüm için gerçekçi Türkçe karşılıklar (uzunlukları gerçek çeviriye yakın olsun diye).
    static let turkish: [String: String] = [
        "MAP": "HARİTA", "BRIEF": "ÖZET", "PROGRESS": "İLERLEME", "RECENTER": "ORTALA", "2D VIEW": "2B GÖRÜNÜM",
        "ADD MARKER": "İŞARET EKLE", "SET DESTINATION": "HEDEF BELİRLE", "EXIT": "ÇIK", "ISLAND DREAMS": "ADA HAYALLERİ",
        "HIGH TIDE": "YÜKSEK GELGİT", "DOWN BY THE DOCKS": "RIHTIMIN ORADA", "LEROY'S": "LEROY'NİN", "STYLE": "TARZ",
        "SOUVENIR": "HEDİYELİK", "Sunbelt Hwy": "Sunbelt Otoyolu",
        "Keep an eye on the bachelor party while searching Kenton's dive spot for treasure.":
            "Kenton'ın dalış noktasında hazine ararken bekârlığa veda partisine göz kulak ol.",
        "Meet Boobie at the marina and pick up the package before the coast guard arrives.":
            "Sahil güvenlik gelmeden marinada Boobie ile buluş ve paketi al.",
        "Follow the cargo truck to Port Gellhorn and find out who is buying the stolen goods.":
            "Kargo kamyonunu Port Gellhorn'a kadar izle ve çalıntı malları kimin aldığını öğren.",
        "Nautical-themed souvenir store selling accessories and summer wear.":
            "Aksesuar ve yazlık giyim satan denizcilik temalı hediyelik eşya dükkânı.",
    ]

    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../testdata/frames").standardized
    }

    private static func box(_ v: [Double]) -> TextBox { TextBox(left: v[0], top: v[1], right: v[2], bottom: v[3]) }

    static func translateWord(_ text: String) -> String {
        let key = text.trimmingCharacters(in: .whitespaces)
        return turkish[key] ?? turkish.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value ?? "çeviri: " + key
    }

    /// Ölçülen kareler: kayıtlı okuması, görüntüsü ve simge/fotoğraf alanları.
    static func frames() throws -> [(id: String, reading: Reading, image: CGImage, clear: [TextBox])] {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("frames.json")))
        return try manifest.frames.compactMap { frame in
            guard let screen = frame.screen else { return nil }
            let url = directory.appendingPathComponent("ocr/screen/\(frame.id).json")
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
            let reading = Reading(lines: fixture.lines.map { line in
                TextLine(line.text, box: line.box.map(box), confidence: line.confidence,
                         words: line.words?.map { TextWord($0.text, box: box($0.box)) })
            })
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(frame.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return (frame.id, reading, image, (screen.clear ?? []).map(box))
        }
    }

    struct Fit {
        var shift = 0.0          // en büyük konum sapması / satır yüksekliği
        var covered: [String] = []
        var overlaps: [String] = []
    }

    /// Kutunun okunan satırların birleşimine göre sapması: kutunun her kenarının, içerdiği satırların kenarına uzaklığının
    /// en büyüğü, satır yüksekliğine oranla (yükseklik kareye göre, en kareye göre: 16:9 düzeltmesiyle).
    static func measure(_ items: [ScreenTranslation.Item], _ reading: Reading, clear: [TextBox], aspect: Double) -> Fit {
        var fit = Fit()
        for item in items {
            let inside = reading.lines.compactMap(\.box).filter { line in
                let y = (line.top + line.bottom) / 2
                return y >= item.box.top && y <= item.box.bottom && line.right > item.box.left && line.left < item.box.right
            }
            guard !inside.isEmpty else { continue }
            let line = max(1e-6, item.lineHeight)
            let top = inside.map(\.top).min()!, bottom = inside.map(\.bottom).max()!
            let dy = max(abs(item.box.top - top), abs(item.box.bottom - bottom)) / line
            fit.shift = max(fit.shift, dy)
            for zone in clear where intersects(item.box, zone) {
                fit.covered.append(item.source.replacingOccurrences(of: "\n", with: " / "))
            }
        }
        for i in items.indices {
            for j in items.indices where j > i && intersects(items[i].box, items[j].box) {
                fit.overlaps.append(items[i].source + " / " + items[j].source)
            }
        }
        return fit
    }

    /// En az bir piksel (1080p) üst üste mi; simge alanları elle dört basamakla yazıldı.
    static func intersects(_ a: TextBox, _ b: TextBox) -> Bool {
        min(a.right, b.right) > max(a.left, b.left) + 1.0 / 1920 && min(a.bottom, b.bottom) > max(a.top, b.top) + 1.0 / 1080
    }

    func testScreenTranslationStaysOnOriginalTextAndOffIcons() async throws {
        var out: [[String: Any]] = []
        for frame in try Self.frames() {
            let items = try await ScreenTranslation.translate(frame.reading, using: { Self.translateWord($0) }, frame: frame.image)
            let fit = Self.measure(items, frame.reading, clear: frame.clear, aspect: Double(frame.image.width) / Double(frame.image.height))
            print("ölçüm \(frame.id): sapma=\(String(format: "%.2f", fit.shift)) örtülen=\(fit.covered.count) \(fit.covered) çakışma=\(fit.overlaps.count)")
            XCTAssertLessThanOrEqual(fit.shift, 0.10, frame.id)
            XCTAssertEqual(fit.covered, [], frame.id)
            XCTAssertEqual(fit.overlaps, [], frame.id)
            out.append(["id": frame.id, "width": frame.image.width, "height": frame.image.height,
                        "clear": frame.clear.map { [$0.left, $0.top, $0.right, $0.bottom] },
                        "items": items.map { SubtitleServer.json($0) }])
        }
        if let path = ProcessInfo.processInfo.environment["SCREEN_FIT_OUT"] {
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Ortak deneme dosyası (Fixtures/screen-fit.json; Windows ScreenFitTests.cs ve Android ScreenFitTest.kt aynı vakalar)

    /// Deneme dosyasının karesi: düz zemin, dikdörtgen harfler ve simgeler.
    static func syntheticFrame(_ fixture: [String: Any], rects: [[Double]]) -> CGImage {
        let width = fixture["width"] as! Int, height = fixture["height"] as! Int
        func rgb(_ hex: String) -> [UInt8] {
            let v = Int(hex.dropFirst(), radix: 16)!
            return [UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)]
        }
        let ground = rgb(fixture["background"] as! String), ink = rgb(fixture["ink"] as! String)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4] = ground[0]; bytes[i * 4 + 1] = ground[1]; bytes[i * 4 + 2] = ground[2] }
        for r in rects {
            let x0 = Int((r[0] * Double(width)).rounded()), x1 = Int((r[2] * Double(width)).rounded())
            let y0 = Int((r[1] * Double(height)).rounded()), y1 = Int((r[3] * Double(height)).rounded())
            for y in y0..<y1 { for x in x0..<x1 { let p = (y * width + x) * 4; bytes[p] = ink[0]; bytes[p + 1] = ink[1]; bytes[p + 2] = ink[2] } }
        }
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    func testSharedScreenFitVectors() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/screen-fit.json")
        var fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
        let tolerance = fixture["tolerance"] as! Double
        let record = ProcessInfo.processInfo.environment["RECORD_SCREEN_FIT"] == "1"
        var cases = fixture["cases"] as! [[String: Any]]
        for (c, vector) in cases.enumerated() {
            let frame = Self.syntheticFrame(fixture, rects: vector["rects"] as! [[Double]])
            let raw = vector["items"] as! [[String: Any]]
            let items = raw.map { entry -> ScreenTranslation.Item in
                let b = entry["box"] as! [Double]
                var item = ScreenTranslation.Item(source: entry["name"] as! String, translation: entry["name"] as! String,
                                                  box: Self.box(b), lineHeight: entry["line"] as! Double)
                item.style = PhoneTextStyle(background: fixture["background"] as! String, foreground: fixture["ink"] as! String)
                item.look = TextLook(bold: true, condensed: false, align: .left, upper: true, flat: true)
                return item
            }
            let fitted = ScreenFit.fitted(items, frame: frame)
            let got: [[String: Any]] = fitted.map { item in
                ["align": item.look!.align.rawValue, "line": item.lineHeight,
                 "box": [item.box.left, item.box.top, item.box.right, item.box.bottom],
                 "room": item.room.map { [$0.left, $0.top, $0.right, $0.bottom] } ?? []]
            }
            if record {
                cases[c]["expect"] = got.map { entry in entry.mapValues { value -> Any in
                    if let list = value as? [Double] { return list.map { ($0 * 10000).rounded() / 10000 } }
                    if let number = value as? Double { return (number * 10000).rounded() / 10000 }
                    return value
                } }
                continue
            }
            let expect = vector["expect"] as! [[String: Any]]
            XCTAssertEqual(expect.count, got.count, vector["id"] as! String)
            for (k, (want, have)) in zip(expect, got).enumerated() {
                let name = "\(vector["id"]!) \(raw[k]["name"]!)"
                XCTAssertEqual(want["align"] as? String, have["align"] as? String, name)
                XCTAssertEqual(want["line"] as! Double, have["line"] as! Double, accuracy: tolerance, name)
                for key in ["box", "room"] {
                    let a = want[key] as! [Double], b = have[key] as! [Double]
                    XCTAssertEqual(a.count, b.count, name)
                    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: tolerance, "\(name) \(key)") }
                }
            }
        }
        if record {
            fixture["cases"] = cases
            let data = try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: source)
        }
    }

    // MARK: - Önbellekteki yazı anında (okuma → çizim gecikmesi)

    /// Yapay zekâ çevirmeni yerine: önbelleğinde olanı istek göndermeden verir; `translateAll` serbest bırakılana kadar bekler.
    final class HeldTranslator: TextTranslator, @unchecked Sendable {
        let cache: [String: String]
        private let lock = NSLock()
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var asked: [String] = []
        init(cache: [String: String]) { self.cache = cache }
        func translate(_ text: String) async throws -> String { "çeviri: " + text }
        var translatesTogether: Bool { true }
        func cachedTranslation(_ text: String) -> String? { cache[text] }
        func translateAll(_ texts: [String]) async throws -> [String] {
            lock.withLock { asked += texts }
            await withCheckedContinuation { continuation in lock.withLock { gate = continuation } }
            return texts.map { _ in "yeni gelen çeviri" }
        }
        var waiting: Bool { lock.withLock { gate != nil } }
        func release() { lock.withLock { () -> CheckedContinuation<Void, Never>? in defer { gate = nil }; return gate }?.resume() }
    }

    /// Gerçek GTA 6 harita menüsü: menü satırları önceki oturumdan önbellekte; görev açıklaması yeni. Önbellekteki gruplar
    /// çeviri isteği dönmeden (sıfır kare gecikmeyle) çizilir; yalnız yeni yazı çevirmene gider.
    func testCachedScreenTextIsDrawnBeforeTheRequestReturns() async throws {
        let frame = try XCTUnwrap(Self.frames().first { $0.id == "gta6-menu-harita" })
        let menu = ["RECENTER", "2D VIEW", "ADD MARKER", "SET DESTINATION", "MAP", "BRIEF", "PROGRESS", "ISLAND DREAMS"]
        let translator = HeldTranslator(cache: Dictionary(uniqueKeysWithValues: menu.map { ($0, Self.translateWord($0)) }))
        final class Shown: @unchecked Sendable { var batches: [[ScreenTranslation.Item]] = [] }
        let shown = Shown()
        let task = Task {
            try await ScreenTranslation.translate(frame.reading, using: translator, frame: frame.image) { shown.batches.append($0) }
        }
        let deadline = Date().addingTimeInterval(10)
        while !translator.waiting, Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(translator.waiting, "çeviri isteği gitmedi")
        // İstek beklerken önbellekteki menü satırları zaten çizildi.
        let early = try XCTUnwrap(shown.batches.first, "önbellekteki gruplar istek dönmeden çizilmedi")
        XCTAssertTrue(early.contains { $0.translation == "HEDEF BELİRLE" }, early.map(\.translation).joined(separator: " | "))
        XCTAssertTrue(early.contains { $0.translation == "ADA HAYALLERİ" }, early.map(\.translation).joined(separator: " | "))
        XCTAssertFalse(early.contains { $0.translation == "yeni gelen çeviri" })
        // Çevirmene yalnız önbellekte olmayan yazı gitti.
        XCTAssertFalse(translator.asked.contains { menu.contains($0) }, translator.asked.joined(separator: " | "))
        translator.release()
        let final = try await task.value
        XCTAssertTrue(final.contains { $0.translation == "yeni gelen çeviri" })
        XCTAssertGreaterThan(final.count, early.count)
    }

    /// Çizicilerin ortak satır yerleşimi (Fixtures/screen-fit.json → lines; Windows ve Android aynı vakalar).
    func testSharedLineVectors() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/screen-fit.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
        for vector in fixture["lines"] as! [[String: Any]] {
            let room = (vector["room"] as? [Double]).map { ($0[0], $0[1]) }
            let align = TextLook.Align(rawValue: vector["align"] as! String)!
            let got = ScreenFit.lines(vector["text"] as! String, left: vector["left"] as! Double, width: vector["width"] as! Double,
                                      room: room, rows: vector["rows"] as! Int, align: align) { Double($0.count) * 10 }
            let want = vector["expect"] as! [String: Any]
            let name = vector["id"] as! String
            XCTAssertEqual(got.lines, want["lines"] as! [String], name)
            XCTAssertEqual(got.squeeze, want["squeeze"] as! Double, accuracy: 0.001, name)
            XCTAssertEqual(got.left, want["left"] as! Double, accuracy: 0.01, name)
            XCTAssertEqual(got.width, want["width"] as! Double, accuracy: 0.01, name)
        }
    }
}
