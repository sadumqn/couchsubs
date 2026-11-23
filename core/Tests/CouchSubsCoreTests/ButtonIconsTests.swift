// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import ImageIO
import XCTest
@testable import CouchSubsCore

/// Oyun ipuçlarındaki kumanda simgeleri ("Hold △ to sprint"): yazı tanıma simgeyi harf sanıyor ("A", "Ä"), çeviri
/// simgeyi örtüyor ve Türkçede neye basılacağı kalmıyordu. Sözcük yerleri Windows yazı tanımasının 1280×200'lük gerçek
/// okumalarından alındı (simgeli ipucu görüntüleri; Windows: ButtonIconsTests.cs, aynı sayılar).
final class ButtonIconsTests: XCTestCase {
    private static let width = 1280, height = 200
    private let m = ButtonIcons.marker
    private let nowhere = TextBox(left: 0, top: 0, right: 0, bottom: 0)

    private func word(_ text: String, _ x: Double, _ w: Double, _ y: Double, _ h: Double) -> TextWord {
        TextWord(text, box: TextBox(left: x / Double(Self.width), top: y / Double(Self.height),
                                    right: (x + w) / Double(Self.width), bottom: (y + h) / Double(Self.height)))
    }

    private func line(_ words: TextWord...) -> TextLine {
        let box = words.dropFirst().reduce(words[0].box) { $0.union($1.box) }
        return TextLine(words.map(\.text).joined(separator: " "), box: box, words: words)
    }

    /// "Hold △ to sprint.": △ "A" okundu.
    private var hold: TextLine {
        line(word("Hold", 48, 75, 89, 31), word("A", 138, 29, 90, 27), word("to", 202, 34, 91, 25), word("sprint.", 249, 99, 84, 39))
    }

    // MARK: - Kare

    private typealias Color = (b: UInt8, g: UInt8, r: UInt8)
    private let background: Color = (52, 44, 40)
    private let white: Color = (255, 255, 255)

    private func blank(_ color: Color) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        fill(&pixels, 0, 0, Self.width, Self.height, color)
        return pixels
    }

    private func fill(_ pixels: inout [UInt8], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: Color) {
        for y in y0..<y1 {
            for x in x0..<x1 { paint(&pixels, x, y, color) }
        }
    }

    private func paint(_ pixels: inout [UInt8], _ x: Int, _ y: Int, _ color: Color) {
        let i = (y * Self.width + x) * 4
        pixels[i] = color.r
        pixels[i + 1] = color.g
        pixels[i + 2] = color.b
        pixels[i + 3] = 255
    }

    /// Koyu zeminde beyaz "yazı" blokları ve (135–182, 79–126) arasında yuvarlak bir simge.
    private func holdPixels() -> [UInt8] {
        var pixels = blank(background)
        fill(&pixels, 48, 89, 123, 120, white) // Hold
        fill(&pixels, 202, 91, 236, 116, white) // to
        fill(&pixels, 249, 84, 348, 123, white) // sprint.
        for y in 79..<126 {
            for x in 135..<182 {
                let dx = Double(x) - 158.5, dy = Double(y) - 102.5
                if dx * dx + dy * dy <= 23.5 * 23.5 { paint(&pixels, x, y, (0, 0, 0)) }
            }
        }
        return pixels
    }

    /// Pikseller (satırlar yukarıdan aşağı, RGBA) bir CGImage olur.
    private func cgImage(_ pixels: [UInt8]) -> CGImage {
        let context = CGContext(data: nil, width: Self.width, height: Self.height, bitsPerComponent: 8, bytesPerRow: Self.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let target = context.data!.assumingMemoryBound(to: UInt8.self)
        for i in pixels.indices { target[i] = pixels[i] }
        return context.makeImage()!
    }

    /// Simgenin PNG'si: başlıktaki boyut ve ImageIO'nun çözdüğü resim (PNG elle yazılıyor; çözülebilmeli).
    private func decodedPng(_ dataUri: String) throws -> (width: Int, height: Int, image: CGImage) {
        let prefix = "data:image/png;base64,"
        XCTAssertTrue(dataUri.hasPrefix(prefix))
        let data = try XCTUnwrap(Data(base64Encoded: String(dataUri.dropFirst(prefix.count))))
        let bytes = [UInt8](data)
        func read(_ at: Int) -> Int {
            (Int(bytes[at]) << 24) | (Int(bytes[at + 1]) << 16) | (Int(bytes[at + 2]) << 8) | Int(bytes[at + 3])
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (read(16), read(20), image)
    }

    private func decodedPixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    // MARK: - İşaretleme

    func testIconReadAsALetterAfterAVerbIsMarked() throws {
        let marked = ButtonIcons.mark(hold)
        XCTAssertEqual(marked.text, "Hold \(m) to sprint.")
        let icons = try XCTUnwrap(marked.icons)
        XCTAssertEqual(icons.count, 1)
        let icon = icons[0]
        XCTAssertEqual(icon.text, "A")
        // Kutu simgenin tamamını içine alır (komşu sözcüklerle arasındaki boşlukların ortasına kadar).
        XCTAssertTrue(icon.box.left * Double(Self.width) <= 135 && icon.box.right * Double(Self.width) >= 182)
        XCTAssertTrue(icon.box.top * Double(Self.height) <= 79 && icon.box.bottom * Double(Self.height) >= 126)
    }

    func testIconGluedToTheVerbIsSplitOff() {
        // "Press [R2] to open the weapon wheel." → "PressÄ"
        let hint = line(word("PressÄ", 49, 148, 71, 41), word("to", 223, 33, 80, 24), word("open", 269, 80, 85, 28),
                        word("the", 362, 52, 76, 28), word("weapon", 425, 127, 85, 28), word("wheel.", 565, 101, 76, 28))
        let marked = ButtonIcons.mark(hint)
        XCTAssertEqual(marked.text, "Press \(m) to open the weapon wheel.")
        XCTAssertEqual(marked.icons?.map(\.text), ["Ä"])
    }

    func testSeveralIconsInOneHintAreMarked() {
        // "Use [stick] to move the camera and [△] to interact." → "Useo ... and A to interact."
        let hint = line(word("Useo", 48, 94, 69, 41), word("to", 164, 27, 80, 21), word("move", 204, 76, 85, 16),
                        word("the", 291, 44, 77, 24), word("camera", 346, 100, 85, 16), word("and", 458, 50, 77, 24),
                        word("A", 527, 26, 76, 24), word("to", 582, 29, 80, 21), word("interact.", 623, 110, 78, 23))
        let marked = ButtonIcons.mark(hint)
        XCTAssertEqual(marked.text, "Use \(m) to move the camera and \(m) to interact.")
        XCTAssertEqual(marked.icons?.map(\.text), ["o", "A"])
    }

    func testUnreadIconLeavesAGapAfterTheVerb() {
        // Beyaz yazı süzgecinde simge kaybolur: "Hold" ile "to" arasında birkaç harflik boşluk kalır.
        let hint = line(word("Hold", 48, 75, 89, 31), word("to", 202, 34, 91, 25), word("sprint.", 249, 99, 84, 39))
        let marked = ButtonIcons.mark(hint)
        XCTAssertEqual(marked.text, "Hold \(m) to sprint.")
        XCTAssertEqual(marked.icons?.map(\.text), [""])
    }

    func testOrdinaryTextIsLeftAlone() {
        for text in ["I'll use a rope to climb down.", "Press the button to continue.", "Hold on, Arthur.",
                     "He uses the map, and I follow.", "A New Quest", "Use it wisely."] {
            // Sözcük yerleri bilinmiyor: harf sayısına göre kestirilir.
            let line = TextLine(text, box: TextBox(left: 0.1, top: 0.4, right: 0.6, bottom: 0.45))
            XCTAssertEqual(ButtonIcons.mark(line), line, text)
        }
    }

    func testWithoutWordPositionsTheIconIsStillFoundByItsPlaceInTheText() {
        // Okuyucu yalnız satırın kutusunu veriyor.
        let marked = ButtonIcons.mark(TextLine("Hold A to sprint.", box: TextBox(left: 0.1, top: 0.4, right: 0.6, bottom: 0.45)))
        XCTAssertEqual(marked.text, "Hold \(m) to sprint.")
    }

    func testIconRecognisedAsASymbolIsTranslatedInsteadOfDroppedAsAPrompt() {
        // Simgeyi tanıyan okuyucu: "Hold △ to sprint." eskiden kumanda ipucu sayılıp hiç çevrilmiyordu.
        let line = TextLine("Hold △ to sprint.", box: TextBox(left: 39.0 / Double(Self.width), top: 0.4, right: 356.0 / Double(Self.width), bottom: 0.62))
        let lines = Reading(lines: [line]).withButtonIcons().withoutButtonPrompts().lines
        XCTAssertEqual(lines.map(\.text), ["Hold \(m) to sprint."])
    }

    func testIconRemnantsFromTheHintPoolBecomeIcons() {
        // #424'ün GTA 6 havuzundaki gerçek okumaları: fiil ile "to" arasındaki tuş kalıntıları simgedir.
        let cases: [(String, String, [String])] = [
            ("Press @ to open the map", "Press \(m) to open the map", ["@"]),
            ("Hold I LI to open your loadout", "Hold \(m) to open your loadout", ["I LI"]),
            ("Press RE to go back to your weapons and equipment", "Press \(m) to go back to your weapons and equipment", ["RE"]),
            ("Press (9 0 to stop focusing", "Press \(m) to stop focusing", ["(9 0"]),
            ("Release 2 and R2 to breathe out", "Release \(m) and \(m) to breathe out", ["2", "R2"]),
            ("Press [RB] to take cover", "Press \(m) to take cover", ["[RB]"]),
        ]
        for (read, marked, icons) in cases {
            let line = ButtonIcons.mark(TextLine(read, box: TextBox(left: 0.1, top: 0.4, right: 0.6, bottom: 0.45)))
            XCTAssertEqual(line.text, marked, read)
            XCTAssertEqual((line.icons ?? []).map(\.text), icons, read)
        }
    }

    func testHintWhoseIconWasFoundIsTranslatedButOtherwiseStillDropped() {
        let line = TextLine("Press @ to open the map", box: TextBox(left: 0.1, top: 0.4, right: 0.6, bottom: 0.45))
        // Ekranı çevir/ek alan: simge bulunduysa satır kalır (simgesiyle çevrilir).
        XCTAssertEqual(Reading(lines: [line]).withButtonIcons().withoutButtonPrompts().lines.count, 1)
        // Ana altyazı simge aramaz: #424'teki gibi ipucu atılır.
        XCTAssertTrue(Reading(lines: [line]).withoutButtonPrompts().lines.isEmpty)
    }

    func testSpeechKeptByTheHintRuleIsNotMarked() {
        // #424'ün koruduğu konuşmalar simge sanılmaz.
        for text in ["Press the button, Jason!", "Hold on to something.", "HOLD ON TO IT", "Use it to open the door.",
                     "Jason: Press to the left", "Hold to your course"] {
            let line = TextLine(text, box: TextBox(left: 0.1, top: 0.4, right: 0.6, bottom: 0.45))
            XCTAssertEqual(ButtonIcons.mark(line), line, text)
        }
    }

    func testHintSplitAroundTheIconIsJoinedBack() {
        // PaddleOCR'ın gerçek okuması (Windows): "Press" | "R2" | "to open the weapon wheel." (x: 42-144, 125-179, 215-670).
        let w = Double(Self.width), h = Double(Self.height)
        let reading = Reading(lines: [
            TextLine("Press", box: TextBox(left: 42 / w, top: 70 / h, right: 144 / w, bottom: 114 / h)),
            TextLine("R2", box: TextBox(left: 125 / w, top: 68 / h, right: 179 / w, bottom: 116 / h)),
            TextLine("to open the weapon wheel.", box: TextBox(left: 215 / w, top: 72 / h, right: 670 / w, bottom: 112 / h)),
        ])
        let lines = reading.withButtonIcons().lines
        XCTAssertEqual(lines.map(\.text), ["Press \(m) to open the weapon wheel."])
        XCTAssertEqual(lines.first?.icons?.map(\.text), ["R2"])
    }

    func testSeparateLabelsOnOneRowAreNotJoined() {
        let reading = Reading(lines: [
            TextLine("Map", box: TextBox(left: 0.10, top: 0.9, right: 0.14, bottom: 0.93)),
            TextLine("Inventory", box: TextBox(left: 0.16, top: 0.9, right: 0.24, bottom: 0.93)),
        ])
        XCTAssertEqual(ButtonIcons.joinHints(reading), reading)
    }

    func testShortPromptsWithTheButtonAtAnEdgeStayUntranslated() {
        // Bilerek çevrilmezler (ek alanda sürekli gelip giderler); örtülmedikleri için simge zaten görünür kalır.
        for text in ["△ Pick up", "L1 + R1 Spartan Rage", "PHOTO MODE L1 + R1"] {
            let line = TextLine(text, box: TextBox(left: 0.1, top: 0.4, right: 0.4, bottom: 0.45))
            XCTAssertTrue(Reading(lines: [line]).withButtonIcons().withoutButtonPrompts().lines.isEmpty, text)
        }
    }

    func testButtonAfterAVerbAtTheEndIsTranslatedWithTheVerb() {
        // "Hold △": yalnız "Hold" çevrilince "Tut" kalır; ad ile "△'yu basılı tut" olur.
        let marked = ButtonIcons.mark(TextLine("Hold △", box: TextBox(left: 0.1, top: 0.4, right: 0.3, bottom: 0.45)))
        XCTAssertEqual(IconText.protect(marked.text).text, "Hold Feldor")
    }

    func testSingleLettersAtTheStartAreNotButtons() {
        // "A Pick up": "A" düğme de olabilir, tanım edatı da; tek harfe ancak fiilden sonra güvenilir.
        let line = TextLine("A Pick up", box: TextBox(left: 0.1, top: 0.4, right: 0.3, bottom: 0.45))
        XCTAssertEqual(ButtonIcons.mark(line), line)
    }

    func testOcrNoiseCleaningKeepsTheMarker() {
        let reading = Reading(lines: [ButtonIcons.mark(hold)]).withoutOcrNoise()
        XCTAssertEqual(reading.lines.first?.text, "Hold \(m) to sprint.")
        XCTAssertEqual(reading.lines.first?.icons?.count, 1)
    }

    // MARK: - Kesme

    func testCropCutsTheIconTightlyOutOfTheFrame() throws {
        let icon = try XCTUnwrap(ButtonIcons.mark(hold).icons?.first)
        let image = try XCTUnwrap(ButtonIcons.crop(cgImage(holdPixels()), icon.box))
        let png = try decodedPng(image)
        // 47 piksellik simge + iki yanda 2 piksel pay; komşu sözcükler girmez.
        XCTAssertTrue((47...53).contains(png.width), "\(png.width)")
        XCTAssertTrue((47...53).contains(png.height), "\(png.height)")
        XCTAssertEqual(png.image.width, png.width)
        XCTAssertEqual(png.image.height, png.height)
        // ImageIO resmi çözebiliyor: ortası simgenin siyahı, köşesi zemin.
        let pixels = decodedPixels(png.image)
        let centre = ((png.image.height / 2) * png.image.width + png.image.width / 2) * 4
        XCTAssertLessThan(Int(pixels[centre]) + Int(pixels[centre + 1]) + Int(pixels[centre + 2]), 60)
        XCTAssertEqual(Double(pixels[0]), Double(background.r), accuracy: 12)
        XCTAssertEqual(Double(pixels[1]), Double(background.g), accuracy: 12)
        XCTAssertEqual(Double(pixels[2]), Double(background.b), accuracy: 12)
    }

    func testCropOfAnEmptyPlaceGivesNothing() {
        XCTAssertNil(ButtonIcons.crop(cgImage(blank(background)), TextBox(left: 0.1, top: 0.3, right: 0.15, bottom: 0.6)))
    }

    func testCropIgnoresANeighbouringLetterThatFallsIntoTheBox() throws {
        var pixels = holdPixels()
        fill(&pixels, 126, 96, 132, 118, white) // simgeye yakın bir harf
        let w = Double(Self.width), h = Double(Self.height)
        let image = try XCTUnwrap(ButtonIcons.crop(cgImage(pixels), TextBox(left: 120 / w, top: 70 / h, right: 186 / w, bottom: 135 / h)))
        let png = try decodedPng(image)
        XCTAssertTrue((47...53).contains(png.width), "\(png.width)")
    }

    // MARK: - Çeviri

    func testIconKeepsItsPlaceThroughTranslation() {
        let prepared = IconText.protect("Hold \(m) to sprint.")
        XCTAssertEqual(prepared.text, "Hold Feldor to sprint.")
        // Çevirmen ada Türkçe ek koyar; ek gerçek düğmenin adına uymayacağı için atılır.
        let restored = IconText.restore("Koşmak için Feldor'u basılı tutun.", names: prepared.names, offset: 0)
        let rendered = IconText.render(restored, slots: [IconSlot(box: nowhere, text: "A", image: "data:image/png;base64,AAAA")])
        XCTAssertEqual(rendered.text, "Koşmak için basılı tutun.")
        XCTAssertEqual(rendered.icons, [IconPlacement(at: 12, image: "data:image/png;base64,AAAA")])
    }

    func testTwoIconsKeepTheirOwnPlacesAndPunctuationStaysAttached() {
        let prepared = IconText.protect("Use \(m) to move the camera and \(m) to interact.")
        XCTAssertEqual(prepared.text, "Use Feldor to move the camera and Halvor to interact.")
        // Türkçede sıra değişir; her ad kendi simgesine döner.
        let restored = IconText.restore("Etkileşim için Halvor'u, kamerayı oynatmak için Feldor'u kullanın.", names: prepared.names, offset: 0)
        let slots = [IconSlot(box: nowhere, text: "o", image: "data:image/png;base64,STICK"),
                     IconSlot(box: nowhere, text: "A", image: "data:image/png;base64,TRI")]
        let rendered = IconText.render(restored, slots: slots)
        XCTAssertEqual(rendered.text, "Etkileşim için, kamerayı oynatmak için kullanın.")
        XCTAssertEqual(rendered.icons, [IconPlacement(at: 14, image: "data:image/png;base64,TRI"),
                                        IconPlacement(at: 39, image: "data:image/png;base64,STICK")])
    }

    func testDroppedPlaceholderPutsTheIconInFront() {
        let prepared = IconText.protect("Hold \(m) to sprint.")
        let restored = IconText.restore("Koşmak için basılı tutun.", names: prepared.names, offset: 0)
        let rendered = IconText.render(restored, slots: [IconSlot(box: nowhere, text: "A", image: "data:image/png;base64,AAAA")])
        XCTAssertEqual(rendered.text, "Koşmak için basılı tutun.")
        XCTAssertEqual(rendered.icons.map(\.at), [0])
    }

    func testIconThatCouldNotBeCutFallsBackToTheReadText() {
        let restored = IconText.restore("Koşmak için Feldor'u basılı tutun.", names: ["Feldor"], offset: 0)
        let rendered = IconText.render(restored, slots: [IconSlot(box: nowhere, text: "A")])
        XCTAssertEqual(rendered.text, "Koşmak için A basılı tutun.")
        XCTAssertTrue(rendered.icons.isEmpty)
    }

    func testScreenTranslationShowsTheButtonInsideTheTranslation() async throws {
        var calls: [String] = []
        let items = try await ScreenTranslation.translate(Reading(lines: [hold]), using: { text in
            calls.append(text)
            return text == "Hold Feldor to sprint." ? "Koşmak için Feldor'u basılı tutun." : text
        }, frame: cgImage(holdPixels()))
        XCTAssertEqual(calls, ["Hold Feldor to sprint."])
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.translation, "Koşmak için basılı tutun.")
        XCTAssertEqual(item.source, "Hold to sprint.")
        let icons = try XCTUnwrap(item.icons)
        XCTAssertEqual(icons.map(\.at), [12])
        XCTAssertTrue(icons[0].image.hasPrefix("data:image/png;base64,"))
    }

    private struct Reader: TextReader {
        let line: TextLine
        func read(_ image: CGImage) throws -> String { line.text }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(lines: [line]) }
    }

    private final class Translator: TextTranslator {
        var calls: [String] = []
        func translate(_ text: String) async throws -> String {
            calls.append(text)
            return text == "Hold Feldor to sprint." ? "Koşmak için Feldor'u basılı tutun." : text
        }
    }

    private final class Server: RegionSending {
        var sent: [(text: String, icons: [IconPlacement]?)] = []
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) { sent.append((text, nil)) }
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?, icons: [IconPlacement]?) {
            sent.append((text, icons))
        }
        func clearRegions() {}
    }

    @MainActor
    func testExtraAreaShowsTheButtonInsideTheTranslation() async {
        // Alan karenin tamamı: okunan alanın kutuları kareyle aynı.
        let area = ExtraArea(id: "tip", name: "Tip", region: CropRegion(top: 0, bottom: 1, left: 0, right: 1))
        let server = Server(), translator = Translator()
        let watcher = RegionWatcher(reader: Reader(line: hold), translator: translator, server: server)
        let frame = cgImage(holdPixels())
        await watcher.pass(frame, areas: [area])
        await watcher.pass(frame, areas: [area])
        XCTAssertEqual(translator.calls, ["Hold Feldor to sprint."])
        XCTAssertEqual(server.sent.map(\.text), ["Koşmak için basılı tutun."])
        XCTAssertEqual(server.sent.first?.icons?.map(\.at), [12])
        XCTAssertTrue(server.sent.first?.icons?.first?.image.hasPrefix("data:image/png;base64,") == true)
    }

    /// TV simgeleri `icons` alanıyla alır: her simgenin düz metindeki yeri (`at`) ve PNG'si (`src`).
    func testServerSendsIconsWithScreenAndRegionTranslations() async throws {
        let server = SubtitleServer(port: 0)
        let port = try await server.start()
        defer { server.stop() }
        let (bytes, _) = try await URLSession.shared.bytes(from: URL(string: "http://127.0.0.1:\(port)/events")!)
        let deadline = Date().addingTimeInterval(3)
        while server.connectedClients < 1 {
            if Date() > deadline { XCTFail("TV bağlanmadı"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let icons = [IconPlacement(at: 12, image: "data:AAAA")]
        server.sendScreen([ScreenTranslation.Item(source: "Hold to sprint.", translation: "Koşmak için basılı tutun.",
                                                  box: TextBox(left: 0.1, top: 0.4, right: 0.3, bottom: 0.45), lineHeight: 0.03,
                                                  icons: icons)], durationMs: 12000)
        server.sendRegion(id: "q", text: "Koşmak için basılı tutun.", box: nil, lineHeight: nil, icons: icons)
        server.clearRegions()
        var lines: [String] = []
        for try await line in bytes.lines {
            lines.append(line)
            if line == "event: region-clear" { break }
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("data:") && $0.contains(#""items":[{"#)
            && $0.contains(#""icons":[{"at":12,"src":"data:AAAA"}]"#) }, "\(lines)")
        XCTAssertTrue(lines.contains(#"data: {"icons":[{"at":12,"src":"data:AAAA"}],"id":"q","text":"Koşmak için basılı tutun."}"#), "\(lines)")
    }
}
