// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import CouchSubsCore

/// X (22 Kas, videolu bildirim, GTA 6 telefonu): "yazılar sürekli oynuyor okumak çok zor, balonların içinde de aynı
/// şekilde aynı hata var". Her OCR turunda balon kutuları ve telefonun bulunan yeri birkaç piksel oynuyor; masaüstü bunları
/// her turda yeniden gönderiyor, TV paneli ve balonları yeniden diziyordu. Aynı balon küçük oynamada yerinde kalır
/// (`PhoneSteady.steadyPositions`), panel telefonun el titremesiyle kaymaz (`steadyPose`), TV'de aynı görünen gönderi
/// yinelenmez (`samePicture`); gerçek kaydırmada hepsi birlikte bir kerede yeni yerine geçer. Windows
/// (PhoneJitterTests.cs) ve Android (PhoneJitterTest.kt) aynı denemeleri yapar.
@MainActor
final class PhoneJitterTests: XCTestCase {
    private final class Reader: TextReader, @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [TextLine] = []
        func set(_ lines: [TextLine]) { lock.withLock { self.lines = lines } }
        func read(_ image: CGImage) throws -> String { try readLines(image, deep: false).text }
        func read(_ image: CGImage, deep: Bool) throws -> String { try read(image) }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { lock.withLock { Reading(lines: lines) } }
    }

    private actor Translator: TextTranslator {
        nonisolated let translatesTogether = true
        private(set) var calls: [String] = []
        func translate(_ text: String) async throws -> String {
            calls.append(text)
            return "Çevrildi: " + text
        }
    }

    private final class Server: RegionSending {
        var sent: [[ScreenTranslation.Item]] = []
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) {
            sendRegion(id: id, text: text, box: box, lineHeight: lineHeight, icons: nil, blocks: nil)
        }
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?,
                        icons: [IconPlacement]?, blocks: [ScreenTranslation.Item]?) {
            sent.append(blocks ?? [])
        }
        func clearRegions() {}
    }

    private struct TimedOut: Error {}

    private func wait(_ done: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await done()) {
            if Date() >= deadline { throw TimedOut() }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private static let frames = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../testdata/frames").standardized

    private func item(_ text: String, _ box: TextBox, line: Double = 0.03) -> ScreenTranslation.Item {
        ScreenTranslation.Item(source: text, translation: "Çevrildi: " + text, box: box, lineHeight: line)
    }

    func testSmallJitterKeepsEachBubbleWhereItWasDrawn() {
        let before = [item("Thx amigo! U find", TextBox(left: 0.62, top: 0.65, right: 0.75, bottom: 0.69)),
                      item("New message", TextBox(left: 0.64, top: 0.59, right: 0.75, bottom: 0.62))]
        // Satır 0,03: dikeyde 0,0075'ten, yatayda 0,0075 / (16/9)'dan az oynama yerinde kalır; harfi oynayan okuma da aynı balon.
        var jiggled = before
        jiggled[0].box = TextBox(left: 0.623, top: 0.655, right: 0.753, bottom: 0.695)
        jiggled[0].source = "Thx amigo! U flnd"
        jiggled[1].box = TextBox(left: 0.638, top: 0.586, right: 0.748, bottom: 0.616)
        let still = PhoneSteady.steadyPositions(jiggled, previous: before, aspect: 16.0 / 9)
        XCTAssertEqual(still[0].box.left, 0.62, accuracy: 1e-9)
        XCTAssertEqual(still[0].box.top, 0.65, accuracy: 1e-9)
        XCTAssertEqual(still[1].box.top, 0.59, accuracy: 1e-9)
        XCTAssertEqual(still[1].box.bottom - still[1].box.top, 0.03, accuracy: 1e-9, "boyu stableBlocks'un işi; burada korunur")

        // Sohbet kaydı: hepsi birlikte 0,02 yukarı; tek seferde hepsi yeni yerine.
        var scrolled = before
        for index in scrolled.indices {
            scrolled[index].box.top -= 0.02
            scrolled[index].box.bottom -= 0.02
        }
        XCTAssertEqual(PhoneSteady.steadyPositions(scrolled, previous: before, aspect: 16.0 / 9), scrolled)

        // Tek balon belirgin kaydı (eşik üstü), öbürü titredi: yalnız kayan yeni yerine geçer.
        var one = jiggled
        one[0].box.top = 0.665
        one[0].box.bottom = 0.705
        let mixed = PhoneSteady.steadyPositions(one, previous: before, aspect: 16.0 / 9)
        XCTAssertEqual(mixed[0].box.top, 0.665, accuracy: 1e-9)
        XCTAssertEqual(mixed[1].box.top, 0.59, accuracy: 1e-9)

        // Başka mesaj (başka çeviri) eşleşmez.
        var other = jiggled
        other[1].translation = "Başka"
        XCTAssertEqual(PhoneSteady.steadyPositions(other, previous: before, aspect: 16.0 / 9)[1].box, other[1].box)
    }

    func testPanelAnchorIgnoresHandShakeAndFollowsARealMove() {
        let pose = GamePhoneGeometry.Pose(topX: 0.70, topY: 0.19, bottomX: 0.70, bottomY: 0.87)
        let shaken = GamePhoneGeometry.Pose(topX: 0.704, topY: 0.186, bottomX: 0.703, bottomY: 0.874)
        XCTAssertEqual(PhoneSteady.steadyPose(shaken, anchor: pose), pose)
        let moved = GamePhoneGeometry.Pose(topX: 0.66, topY: 0.19, bottomX: 0.66, bottomY: 0.87)
        XCTAssertEqual(PhoneSteady.steadyPose(moved, anchor: pose), moved)
        XCTAssertEqual(PhoneSteady.steadyPose(shaken, anchor: nil), shaken)
    }

    func testPanelMessagesAreComparedByOrderAndTextNotByTheirFlowBoxes() {
        var card = item("", TextBox(left: 0.2, top: 0.2, right: 0.5, bottom: 0.8))
        card.translation = ScreenPhoneCard.backdropText
        card.panel = .card
        var message = item("Hi", TextBox(left: 0.22, top: 0.3, right: 0.4, bottom: 0.34))
        message.panel = .theirs
        var nudged = message
        nudged.box.top += 0.004
        XCTAssertTrue(PhoneSteady.samePicture([card, message], [card, nudged]))
        var reworded = message
        reworded.translation = "Selam"
        XCTAssertFalse(PhoneSteady.samePicture([card, message], [card, reworded]))
        var movedCard = card
        movedCard.box.left += 0.01
        XCTAssertFalse(PhoneSteady.samePicture([card, message], [movedCard, message]))
        // Balonların Üstünde: kutu da aynı olmalı.
        XCTAssertFalse(PhoneSteady.samePicture([item("Hi", message.box)], [item("Hi", nudged.box)]))
    }

    /// Yazı rengi örneği balonun kenarından bir siyah bir koyu gri okunur: zeminin aynı yanında kaldıkça eskisi kalır;
    /// seçimde (siyahtan beyaza) değişim izlenir.
    func testInkOnTheSameSideOfTheBubbleKeepsItsColor() {
        XCTAssertTrue(PhoneSteady.sameInk("#000000", "#584048", on: "#C8B0B8"))
        XCTAssertFalse(PhoneSteady.sameInk("#000000", "#FFFFFF", on: "#C8B0B8"))
        var before = item("Casa De Donnie", TextBox(left: 0.65, top: 0.36, right: 0.77, bottom: 0.38))
        before.style = PhoneTextStyle(background: "#C8B0B8", foreground: "#000000")
        var grey = before
        grey.style = PhoneTextStyle(background: "#C8B0B8", foreground: "#584048")
        XCTAssertEqual(PhoneRegionSession.stableBlocks([grey], previous: [before])[0].style, before.style)
    }

    func testShortMessageWithPunctuationNoiseKeepsItsTranslation() {
        let known = ["Ok.": "Tamam.", "Comprendo?": "Anladın mı?"]
        XCTAssertEqual(PhoneSteady.translation(of: "ok", in: known), "Tamam.")
        XCTAssertEqual(PhoneSteady.translation(of: "Comprendo ?", in: known), "Anladın mı?")
        XCTAssertNil(PhoneSteady.translation(of: "Ok?", in: known), "soru başka anlam")
        XCTAssertNil(PhoneSteady.translation(of: "On", in: known))
    }

    /// Gerçek kare (testdata/frames/gta6-telefon-sohbet-1.jpg) ve kayıtlı okuması (ocr/gta6-telefon-sohbet-1-tam.json):
    /// art arda sekiz turda telefonun yeri ve her satırın kutusu birkaç piksel oynuyor, bazı satırlar bir harf farklı
    /// okunuyor. Panelde de balonların üstünde de ilk gönderiden sonra hiçbir şey yeniden gönderilmez, hiçbir mesaj yeniden
    /// çevrilmez. Sohbet gerçekten kayınca bir kez gönderilir, sonra yine durur.
    func testRealPhoneChatStaysStillWhileOcrAndPoseJitter() async throws {
        let url = Self.frames.appendingPathComponent("gta6-telefon-sohbet-1.jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw XCTSkip("gerçek kare yok") }
        let data = try Data(contentsOf: Self.frames.appendingPathComponent("ocr/gta6-telefon-sohbet-1-tam.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recorded = try XCTUnwrap(json["lines"] as? [[String: Any]]).compactMap { line -> (String, TextBox)? in
            guard let text = line["text"] as? String, let box = line["box"] as? [Double], box.count == 4 else { return nil }
            return (text, TextBox(left: box[0], top: box[1], right: box[2], bottom: box[3]))
        }
        let pose = try XCTUnwrap(GamePhoneGeometry.locate(frame))
        let handset = ScreenPhoneCard.Handset(pose: pose, aspect: Double(frame.width) / Double(frame.height))
        // Telefon okuyucusu düz ekranı okur: kayıtlı satırlar düz ekrana taşınır.
        let flat = recorded.filter { ScreenPhoneCard.holds($0.1, handset: handset) }.map { ($0.0, handset.flat($0.1)) }
        XCTAssertGreaterThanOrEqual(flat.count, 6)
        // OCR gürültüsü: harf oynaması ve noktalama (aynı mesaj sayılır).
        let noisy = ["Dropped that stuff": "Dropped that stuf", "Comprendo?": "Comprendo ?", "New message": "New rnessage"]
        let shakes: [(Double, Double)] = [(0.004, -0.003), (-0.003, 0.004), (0.002, 0.002), (-0.004, -0.002),
                                          (0.003, -0.004), (-0.002, 0.003), (0.004, 0.001), (-0.001, -0.004)]

        for panel in [true, false] {
            let reader = Reader(), translator = Translator(), server = Server()
            var clock = 0
            let watcher = RegionWatcher(reader: reader, translator: translator, server: server, clock: { clock })
            watcher.phonePanel = { PhonePanelOptions(enabled: panel) }
            reader.set(flat.map { TextLine($0.0, box: $0.1) })
            watcher.offer(frame, areas: [], phone: pose)
            try await wait { !watcher.isBusy }
            let first = try XCTUnwrap(server.sent.last)
            XCTAssertFalse(first.isEmpty)
            XCTAssertEqual(first.contains { $0.panel == .card }, panel)
            let sends = server.sent.count
            let calls = await translator.calls

            for (turn, shake) in shakes.enumerated() {
                let (dx, dy) = shake
                reader.set(flat.enumerated().map { index, line in
                    let sign = index % 2 == 0 ? 1.0 : -1.0
                    let text = turn % 2 == 0 ? (noisy[line.0] ?? line.0) : line.0
                    return TextLine(text, box: TextBox(left: line.1.left + dx * sign, top: line.1.top + dy * sign,
                                                       right: line.1.right + dx * sign, bottom: line.1.bottom + dy * sign))
                })
                // Telefonun bulunan yeri de birkaç piksel oynar (el titremesi, kasanın bulunması).
                let shaken = GamePhoneGeometry.Pose(topX: pose.topX + dx / 2, topY: pose.topY + dy / 2,
                                                    bottomX: pose.bottomX + dx / 2, bottomY: pose.bottomY - dy / 2)
                clock += 450
                watcher.offer(frame, areas: [], phone: shaken)
                try await wait { !watcher.isBusy }
            }
            XCTAssertEqual(server.sent.count, sends, "panel \(panel): titreme yeniden gönderilmedi")
            let after = await translator.calls
            XCTAssertEqual(after, calls, "panel \(panel): hiçbir mesaj yeniden çevrilmedi")

            // Gerçek kaydırma: bütün satırlar birlikte yukarı kayar; bir kez gönderilir, sonra yine durur.
            let scroll = 0.08
            reader.set(flat.map { TextLine($0.0, box: TextBox(left: $0.1.left, top: $0.1.top - scroll,
                                                              right: $0.1.right, bottom: $0.1.bottom - scroll)) })
            clock += 450
            watcher.offer(frame, areas: [], phone: pose)
            try await wait { !watcher.isBusy }
            if !panel {
                XCTAssertEqual(server.sent.count, sends + 1, "kaydırma bir kez gönderilir")
                let moved = try XCTUnwrap(server.sent.last)
                XCTAssertEqual(moved.count, first.count)
                XCTAssertTrue(zip(moved, first).allSatisfy { $0.box.top < $1.box.top - 0.01 }, "hepsi birlikte kaydı")
            }
            let scrolled = server.sent.count
            for (dx, dy) in shakes.prefix(3) {
                reader.set(flat.map { TextLine($0.0, box: TextBox(left: $0.1.left + dx, top: $0.1.top - scroll + dy,
                                                                  right: $0.1.right + dx, bottom: $0.1.bottom - scroll + dy)) })
                clock += 450
                watcher.offer(frame, areas: [], phone: pose)
                try await wait { !watcher.isBusy }
            }
            XCTAssertEqual(server.sent.count, scrolled, "panel \(panel): kaydırmadan sonra yine sabit")
        }
    }

    /// Telefonun ekranı kısa süre boş okunursa (kare geçişi, bulanıklık) panel hemen silinmez: `PhoneSteady.missTurns`
    /// tur boş kalırsa silinir. Önceden ikinci boş okumada siliniyor, sonraki turda geri geliyordu (yanıp sönme).
    func testBriefEmptyReadingDoesNotBlinkThePanel() async throws {
        let reader = Reader(), translator = Translator(), server = Server()
        var clock = 0
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server, clock: { clock })
        let a = GamePhoneTestFrame.phone(), b = GamePhoneTestFrame.phone(patch: CGRect(x: 183, y: 94, width: 36, height: 12))
        let pose = try XCTUnwrap(GamePhoneGeometry.locate(a))
        let line = TextLine("Where are you man", box: TextBox(left: 0.15, top: 0.30, right: 0.85, bottom: 0.36))
        reader.set([line])
        watcher.offer(a, areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        XCTAssertEqual(server.sent.count, 1)
        reader.set([])
        for turn in 1..<PhoneSteady.missTurns {
            clock += 450
            watcher.offer(turn % 2 == 0 ? a : b, areas: [], phone: pose)
            try await wait { !watcher.isBusy }
        }
        XCTAssertEqual(server.sent.count, 1, "kısa boşluk paneli silmez")
        reader.set([line])
        clock += 450
        watcher.offer(a, areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        XCTAssertEqual(server.sent.count, 1, "geri gelen aynı sohbet yeniden gönderilmez")

        reader.set([])
        for _ in 0..<PhoneSteady.missTurns {
            clock += 450
            watcher.offer(b, areas: [], phone: pose)
            try await wait { !watcher.isBusy }
            clock += 450
            watcher.offer(a, areas: [], phone: pose)
            try await wait { !watcher.isBusy }
        }
        XCTAssertEqual(server.sent.last?.isEmpty, true, "uzun süren boşlukta silinir")
    }
}
