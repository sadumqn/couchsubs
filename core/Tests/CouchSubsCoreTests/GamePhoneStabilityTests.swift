// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation
import XCTest
@testable import CouchSubsCore

/// Otomatik telefon okumasında mesaj kaybı ve titreme: soluk satırın aynı kareden kurtarılması, tek turluk balon
/// atlaması ve balonların görünüşünün sabit kalması (Windows: GamePhoneReaderTests, RegionWatcherTests.PhoneAppearance).
final class GamePhoneStabilityTests: XCTestCase {
    private final class StripReader: TextReader, @unchecked Sendable {
        let full: Reading
        let strip: (CGImage) -> Reading
        var calls = 0
        init(_ full: Reading, strip: @escaping (CGImage) -> Reading) {
            self.full = full
            self.strip = strip
        }
        func read(_ image: CGImage) throws -> String { "" }
        func read(_ image: CGImage, deep: Bool) throws -> String { "" }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading {
            calls += 1
            return image.height == 300 ? full : strip(image)
        }
    }

    private func line(_ text: String, _ l: Double, _ t: Double, _ r: Double, _ b: Double, confidence: Double? = nil) -> TextLine {
        TextLine(text, box: TextBox(left: l, top: t, right: r, bottom: b), confidence: confidence)
    }

    private func run(ink: Bool, complete: Bool, anchorMatches: Bool, partial: Bool = false)
        throws -> (reader: StripReader, result: Reading, again: () throws -> Reading) {
        let width = 200, height = 300
        var rgba = Data(repeating: 255, count: width * height * 4)
        if ink {
            for y in 244..<266 {
                for x in 40..<150 {
                    let tone = UInt8((x / 3 % 2) * 180), at = (y * width + x) * 4
                    rgba[at] = tone; rgba[at + 1] = tone; rgba[at + 2] = tone
                }
            }
        }
        let image = GamePhoneTestFrame.image(width: width, height: height) { x, y in
            let at = (y * width + x) * 4
            return (rgba[at], rgba[at + 1], rgba[at + 2])
        }
        let anchor = line("around. Be good", 0.20, 0.88, 0.67, 0.94, confidence: 0.98)
        let upper = line("Just passing through", 0.20, 0.83, 0.85, 0.89, confidence: 0.96)
        var lines = [line("Friends", 0.1, 0.12, 0.3, 0.18), line("See you soon.", 0.1, 0.49, 0.6, 0.54), anchor]
        if complete { lines.append(upper) }
        if partial { lines.append(line("passing through", 0.41, 0.83, 0.85, 0.89)) }
        let start = Int(floor((0.88 - 1.6 * 0.06) * Double(height))), end = Int(ceil((0.94 + 0.35 * 0.06) * Double(height)))
        func local(_ b: TextBox) -> TextBox {
            TextBox(left: b.left, top: (b.top * Double(height) - Double(start)) / Double(end - start),
                    right: b.right, bottom: (b.bottom * Double(height) - Double(start)) / Double(end - start))
        }
        let reader = StripReader(Reading(lines: lines)) { crop in
            XCTAssertLessThan(crop.height, height)
            var top = upper
            top.box = local(upper.box!)
            top.words = [TextWord("passing", box: top.box!)]
            var tail = anchor
            if !anchorMatches { tail.text = "around the corner" }
            tail.box = local(anchor.box!)
            return Reading(lines: [top, tail])
        }
        let retry = GamePhoneRetry()
        let read = { try GamePhoneReader.readMessages(image, rgba: rgba, width: width, height: height, reader: reader, retry: retry) }
        return (reader, try read(), read)
    }

    /// Yalnız okunmamış şerit yeniden okunur ve ikinci okuma aynı alt satırı aynı yerde bulmalıdır.
    func testFaintUpperLineIsRecoveredOnlyFromAConfirmedStrip() throws {
        let cases: [(ink: Bool, complete: Bool, anchor: Bool, calls: Int, recovered: Bool, partial: Bool)] = [
            (true, false, true, 2, true, false), (true, false, true, 2, false, true), (true, false, false, 2, false, false),
            (false, false, true, 1, false, false), (true, true, true, 1, false, false),
        ]
        for c in cases {
            let (reader, result, again) = try run(ink: c.ink, complete: c.complete, anchorMatches: c.anchor, partial: c.partial)
            XCTAssertEqual(reader.calls, c.calls, "\(c)")
            XCTAssertEqual(result.lines.filter { $0.text == "around. Be good" }.count, 1)
            let found = result.lines.filter { $0.text == "Just passing through" }
            XCTAssertEqual(found.count, c.complete || c.recovered ? 1 : 0, "\(c)")
            if c.calls == 2 && !c.anchor {
                // Başarısız kurtarma aynı sohbete her dönüşte yeni bir OCR başlatmaz.
                XCTAssertEqual(try again(), result)
                XCTAssertEqual(reader.calls, 3)
            }
            if c.recovered {
                let recovered = try XCTUnwrap(found.first)
                XCTAssertEqual(recovered.box!.top, 0.83, accuracy: 1e-5)
                XCTAssertEqual(recovered.words?.first?.box, recovered.box)
            }
        }
    }

    /// Tek iç balon eksilip kalanlar aynı yerde duruyorsa okuma bir tur bekletilir; ilk ya da kaymış balon değil.
    func testOnlyASingleInteriorBubbleBetweenUnchangedNeighborsIsHeld() {
        func bubble(_ text: String, _ y: Double) -> (paragraphs: [String], box: TextBox) {
            ([text], TextBox(left: 0.1, top: y, right: 0.6, bottom: y + 0.05))
        }
        let shown = [bubble("Lucia!", 0.05), bubble("How's work?", 0.25), bubble("Not great.", 0.45), bubble("See you.", 0.7)]
        XCTAssertTrue(PhoneRegionSession.missingInteriorBubble(shown, [shown[0], shown[1], shown[3]]))
        XCTAssertFalse(PhoneRegionSession.missingInteriorBubble(shown, Array(shown.dropFirst())))
        XCTAssertFalse(PhoneRegionSession.missingInteriorBubble(shown, [shown[0], shown[1], bubble("See you.", 0.8)]))
        XCTAssertFalse(PhoneRegionSession.missingInteriorBubble(shown, [shown[0], shown[2]]))
        // En alttaki balon düşüp kalanlar yerinde duruyorsa o da OCR atlamasıdır (yeni mesaj eklenir, silinmez).
        XCTAssertTrue(PhoneRegionSession.missingInteriorBubble(shown, [shown[0], shown[1], shown[2]]))
    }

    /// Aynı mesajın OCR'la bir iki harfi farklı okunuşu yeni mesaj sayılmaz: bilinen çevirisi kullanılır, çeviri gidip
    /// gelmez. Sayı ya da olumsuzluk değiştiren okuma ve kısa satır aynı mesaj sayılmaz (Windows ve Android'de aynı deneme).
    func testSameMessageReadSlightlyDifferentlyKeepsItsTranslation() {
        let known = ["Did you hear back from the guy at the marina?": "Marinadaki adamdan haber aldın mı?",
                     "Meet me at 5 by the docks": "Benimle 5'te rıhtımda buluş",
                     "I can do that tonight": "Bunu bu gece yapabilirim",
                     "Ok": "Tamam"]
        XCTAssertEqual(PhoneSteady.translation(of: "Did you hear back from the guy at the rnarina?", in: known),
                       "Marinadaki adamdan haber aldın mı?")
        XCTAssertEqual(PhoneSteady.translation(of: "Did you hear back frorn the guy at the marina", in: known),
                       "Marinadaki adamdan haber aldın mı?")
        XCTAssertNil(PhoneSteady.translation(of: "Meet me at 6 by the docks", in: known))
        XCTAssertNil(PhoneSteady.translation(of: "I can't do that tonight", in: known))
        XCTAssertNil(PhoneSteady.translation(of: "On", in: known))
        XCTAssertNil(PhoneSteady.translation(of: "Where are you going tonight?", in: known))
        XCTAssertEqual(PhoneSteady.translation(of: "Ok", in: known), "Tamam")
    }

    private func item(_ source: String, _ translation: String, _ box: TextBox, _ line: Double, _ style: PhoneTextStyle?) -> ScreenTranslation.Item {
        var item = ScreenTranslation.Item(source: source, translation: translation, box: box, lineHeight: line)
        item.style = style
        return item
    }

    func testSelectionKeepsReadableContrastWhenOnlyTheSurfaceColorLooksStable() {
        let before = item("Call me.", "Beni ara.", TextBox(left: 0.1, top: 0.2, right: 0.4, bottom: 0.28), 0.06,
                          PhoneTextStyle(background: "#686868", foreground: "#FFFFFF"))
        var selected = before
        selected.style = PhoneTextStyle(background: "#787878", foreground: "#000000")
        XCTAssertEqual(PhoneRegionSession.stableBlocks([selected], previous: [before]).first?.style, selected.style)
    }

    func testPhoneAppearanceFollowsNewSourceTranslationWidthAndSelectionColor() {
        let first = item("Meet May.", "May ile buluş.", TextBox(left: 0.1, top: 0.2, right: 0.4, bottom: 0.28), 0.06,
                         PhoneTextStyle(background: "#B8C0D0", foreground: "#000000"))
        let jiggled = item("Meet May.", "May ile buluş.", TextBox(left: 0.11, top: 0.21, right: 0.42, bottom: 0.296), 0.064,
                           PhoneTextStyle(background: "#B0B8C8", foreground: "#000000"))
        let steady = PhoneRegionSession.stableBlocks([jiggled], previous: [first])[0]
        XCTAssertEqual(steady.box.left, jiggled.box.left)
        XCTAssertEqual(steady.box.right - steady.box.left, first.box.right - first.box.left, accuracy: 1e-6)
        XCTAssertEqual(steady.lineHeight, first.lineHeight)
        XCTAssertEqual(steady.style, first.style)
        var selection = jiggled
        selection.style = PhoneTextStyle(background: "#B0B8C8", foreground: "#FFFFFF")
        selection.box.right = 0.49
        let selected = PhoneRegionSession.stableBlocks([selection], previous: [steady])[0]
        XCTAssertEqual(selected.style?.foreground, "#FFFFFF")
        XCTAssertEqual(selected.box.right, selection.box.right)
        var source = jiggled
        source.source = "Meet Chase."
        var translation = jiggled
        translation.translation = "May’i gör."
        for replaced in [source, translation] {
            XCTAssertEqual(PhoneRegionSession.stableBlocks([replaced], previous: [first]), [replaced])
        }
    }
}
