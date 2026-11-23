// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Otomatik ekran yazısının türleri Ayarlar'dan ayrı açılıp kapanır (Windows: ScreenTextKindTests.cs, Android:
/// ScreenTextKindTest.kt).
@MainActor
final class ScreenTextKindTests: XCTestCase {
    func testDefaultsAndOldSettingsGetTheDefaults() throws {
        let fresh = UserSettings()
        XCTAssertFalse(fresh.autoScreenText, "ana anahtar deneysel, kapalı")
        XCTAssertEqual([fresh.screenTextPhone, fresh.screenTextMission, fresh.screenTextHelp, fresh.screenTextMenus,
                        fresh.screenTextOther], [true, true, true, false, false])
        // Eski kayıt: türler yok, otomatik ekran yazısı açık.
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"autoScreenText": true}"#.utf8))
        XCTAssertTrue(old.autoScreenText)
        XCTAssertEqual(ScreenTextKind.allCases.map(old.screenTextAllows), [true, true, true, false, false])
        // Kayıt ve yeniden okuma türleri korur.
        var changed = old
        changed.screenTextMenus = true
        changed.screenTextPhone = false
        let again = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(ScreenTextKind.allCases.map(again.screenTextAllows), [false, true, true, true, false])
    }

    func testKindsApplyOnlyWhileAutoScreenTextIsOn() {
        var settings = UserSettings()
        settings.screenTextHelp = false
        XCTAssertTrue(ScreenTextKind.allCases.allSatisfy(settings.screenTextAllows))
        settings.autoScreenText = true
        XCTAssertFalse(settings.screenTextAllows(.help))
        XCTAssertFalse(settings.screenTextAllows(.menu))
    }

    func testPhoneIsReadWithItsOwnSettingOrThePhoneKind() {
        var settings = UserSettings()
        XCTAssertFalse(settings.readsGamePhone)
        settings.autoScreenText = true
        XCTAssertTrue(settings.readsGamePhone)
        settings.screenTextPhone = false
        XCTAssertFalse(settings.readsGamePhone)
        settings.autoReadGamePhone = true
        XCTAssertTrue(settings.readsGamePhone)
    }

    func testKindOfAnArea() {
        let help = GameAreaPresets.areas("GTA 6")
        XCTAssertEqual(help.map { ScreenTextKind.of($0) }, [.help, .phone])
        XCTAssertEqual(ScreenTextKind.of(ExtraArea(id: MissionLine.areaId, name: "Mission", region: CropRegion(), auto: true)), .mission)
        var menu = ExtraArea(id: "auto-1", name: ScreenTextDetector.areaName, region: CropRegion(), auto: true)
        XCTAssertNil(ScreenTextKind.of(menu), "menü dışındaki otomatik alanın türü yazısından çıkar")
        menu.menu = true
        XCTAssertEqual(ScreenTextKind.of(menu), .menu)
        XCTAssertNil(ScreenTextKind.of(ExtraArea(id: "q", name: "Quest", region: CropRegion())), "kullanıcının kendi alanı")
    }

    func testKindOfAutoText() {
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["Press \(ButtonIcons.marker) to open the phone"]), .help)
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["R2 Aim"]), .help)
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["You can buy properties from the website on your phone."]), .help)
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["VICE CITY", "Leonida Keys"]), .help, "birden çok parça: kutu")
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["Ocean Drive"]), .other)
        XCTAssertEqual(ScreenTextKind.of(paragraphs: ["Follow Paulie to the car."]), .mission, "kısa hedef cümlesi")
    }

    // MARK: - RegionWatcher

    private final class Reader: TextReader, @unchecked Sendable {
        var lines: [TextLine] = []
        func read(_ image: CGImage) throws -> String { "" }
        func read(_ image: CGImage, deep: Bool) throws -> String { "" }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(lines: lines) }
    }

    private final class Translator: TextTranslator {
        func translate(_ text: String) async throws -> String { "çeviri \(text.count)" }
    }

    private final class Server: RegionSending {
        var sent: [(id: String, text: String)] = []
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) { sent.append((id, text)) }
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?, icons: [IconPlacement]?,
                        blocks: [ScreenTranslation.Item]?) { sent.append((id, text)) }
        func clearRegions() {}
    }

    private func frame() -> CGImage {
        let width = 320, height = 180
        var pixels = [UInt8](repeating: 30, count: width * height)
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        return context!.makeImage()!
    }

    private func watcher(_ settings: UserSettings, lines: [TextLine]) -> (RegionWatcher, Server) {
        let reader = Reader(), server = Server()
        reader.lines = lines
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        watcher.allows = { settings.screenTextAllows($0) }
        return (watcher, server)
    }

    private func line(_ text: String) -> TextLine { TextLine(text, box: TextBox(left: 0.1, top: 0.3, right: 0.9, bottom: 0.5)) }

    /// Menüler kapalıyken (varsayılan) menü alanı okunmaz; açılınca çevrilir.
    func testMenuAreaIsTranslatedOnlyWhenMenusAreOn() async {
        var settings = UserSettings()
        settings.autoScreenText = true
        var area = ExtraArea(id: "auto-1", name: ScreenTextDetector.areaName, region: CropRegion(top: 0.2, bottom: 0.4, left: 0.1, right: 0.5), auto: true)
        area.menu = true
        let lines = [line("Story Mode"), TextLine("Online Settings", box: TextBox(left: 0.1, top: 0.6, right: 0.9, bottom: 0.8))]
        var (watcher, server) = watcher(settings, lines: lines)
        await watcher.pass(frame(), areas: [area])
        await watcher.pass(frame(), areas: [area])
        XCTAssertTrue(server.sent.isEmpty)
        settings.screenTextMenus = true
        (watcher, server) = self.watcher(settings, lines: lines)
        await watcher.pass(frame(), areas: [area])
        await watcher.pass(frame(), areas: [area])
        XCTAssertFalse(server.sent.filter { !$0.text.isEmpty }.isEmpty)
    }

    /// Kısa tek satır "diğer" türdür (varsayılan kapalı); tuş ipucu yardım/eylemdir (varsayılan açık).
    func testAutoAreaKindComesFromItsText() async {
        var settings = UserSettings()
        settings.autoScreenText = true
        let area = ExtraArea(id: "auto-1", name: ScreenTextDetector.areaName, region: CropRegion(top: 0.2, bottom: 0.4, left: 0.1, right: 0.5), auto: true)
        var (watcher, server) = watcher(settings, lines: [line("Welcome to Ocean Drive Beach")])
        var rejected: [String] = []
        watcher.onAutoRejected = { rejected.append($0) }
        await watcher.pass(frame(), areas: [area])
        await watcher.pass(frame(), areas: [area])
        XCTAssertTrue(server.sent.filter { !$0.text.isEmpty }.isEmpty)
        XCTAssertEqual(rejected, ["auto-1"], "kapalı tür dedektöre bildirilir")
        (watcher, server) = self.watcher(settings, lines: [line("Press \(ButtonIcons.marker) to open the phone menu now")])
        await watcher.pass(frame(), areas: [area])
        await watcher.pass(frame(), areas: [area])
        XCTAssertEqual(server.sent.filter { !$0.text.isEmpty }.count, 1)
    }

    /// Görev kapalıyken görev satırının alanı okunmaz; ana anahtar kapalıyken türler uygulanmaz.
    func testMissionAreaFollowsItsKind() async {
        var settings = UserSettings()
        settings.autoScreenText = true
        settings.screenTextMission = false
        let mission = ExtraArea(id: MissionLine.areaId, name: "Mission", region: CropRegion(top: 0.85, bottom: 0.92, left: 0.3, right: 0.7), auto: true)
        let (watcher, server) = watcher(settings, lines: [line("Get in the sea plane and fly to the island")])
        await watcher.pass(frame(), areas: [mission])
        await watcher.pass(frame(), areas: [mission])
        XCTAssertTrue(server.sent.isEmpty)
        settings.screenTextMission = true
        let (on, onServer) = self.watcher(settings, lines: [line("Get in the sea plane and fly to the island")])
        await on.pass(frame(), areas: [mission])
        await on.pass(frame(), areas: [mission])
        XCTAssertEqual(onServer.sent.filter { !$0.text.isEmpty }.map(\.id), [MissionLine.areaId])
    }
}
