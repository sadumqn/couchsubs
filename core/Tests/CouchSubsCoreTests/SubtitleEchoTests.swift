// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Altyazı ekran yazısı olarak ikinci kez çizilmez (kullanıcı bildirimi, beta.65/66: çeviri hem seçilen altyazı konumunda
/// hem oyunun altyazısının üstünde görünüyordu). Windows: SubtitleEchoTests.cs, Android: SubtitleEchoTest.kt.
@MainActor
final class SubtitleEchoTests: XCTestCase {
    private var time = 0
    private lazy var echo = SubtitleEcho(clock: { [unowned self] in self.time })
    /// Varsayılan altyazı alanı (0,14–0,86 x 0,62–0,97).
    private let region = CropRegion()

    /// Altyazı alanına oranla kutu: karedeki yerden.
    private func inRegion(_ text: String, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> TextLine {
        let w = region.right - region.left, h = region.bottom - region.top
        return TextLine(text, box: TextBox(left: (left - region.left) / w, top: (top - region.top) / h,
                                           right: (right - region.left) / w, bottom: (bottom - region.top) / h))
    }

    private func at(_ text: String, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: bottom))
    }

    func testLinesInTheSubtitleAreaAreNotScreenText() {
        echo.record(Reading(lines: [inRegion("Thought I was flying solo. Come on.", 0.30, 0.80, 0.70, 0.84)]), region: region)
        // Altyazının yerine düşen satır (aynı altyazının bozuk okunuşu ya da yeni altyazı) metin tutmasa da atılır.
        let reading = Reading(lines: [at("Thought I was fiying soio. C0me on.", 0.31, 0.80, 0.69, 0.84),
                                      at("Okay, let's go then, right now.", 0.28, 0.80, 0.72, 0.845),
                                      at("Press up to open the phone", 0.02, 0.05, 0.30, 0.09)])
        XCTAssertEqual(echo.filter(reading).lines.map(\.text), ["Press up to open the phone"])
    }

    /// Kullanıcı bildirimi (X, beta.69, GTA 6): "Ekranı çevir" altyazıyı çeviriyor, telefon mesajlarını çevirmiyordu. Sağ
    /// alttaki telefon kartı (0,72–0,99 x 0,45–0,80) varsayılan altyazı alanıyla kesişiyor; altyazı okunurken kartın
    /// 0,62'nin altındaki satırlarının merkezi alanın içinde kaldığı için hepsi atılıyordu ("Ekranı çevir" de bu süzgeci
    /// kullanır: AppModel/PhoneModel `echo.filter(read, geometry: echo.hasRecent)`).
    func testPhoneMessagesInsideTheSubtitleAreaAreScreenText() {
        echo.record(Reading(lines: [inRegion("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)]), region: region)
        XCTAssertTrue(echo.hasRecent)
        let phone = [at("Jason", 0.76, 0.47, 0.84, 0.50),
                     at("Where are you? We need to talk.", 0.74, 0.55, 0.95, 0.58),
                     at("Come to the marina after dark", 0.74, 0.64, 0.94, 0.67),
                     at("Bring the cash", 0.74, 0.70, 0.84, 0.73),
                     at("Don't be late this time", 0.80, 0.76, 0.97, 0.79)]
        let reading = Reading(lines: phone + [at("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90)])
        XCTAssertEqual(echo.filter(reading, geometry: echo.hasRecent).lines.map(\.text), phone.map(\.text))
        // Geniş altyazıyla aynı sıradaki mesaj satırı da kalır (yalnız ucu örtüşür); altyazının alana düşen parçası atılır.
        echo.record(Reading(lines: [inRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.85, 0.80)]),
                    region: region)
        let wide = Reading(lines: [at("Don't be late this time", 0.80, 0.76, 0.97, 0.79),
                                   at("before the cops do", 0.73, 0.76, 0.85, 0.80)])
        XCTAssertEqual(echo.filter(wide).lines.map(\.text), ["Don't be late this time"])
    }

    /// İki satırlı altyazının üst satırı alanın dışında: altyazı hattı yalnız alt satırı okur, üst satır bitişik ve aynı
    /// boyda olduğu için o da altyazıdır.
    func testSubtitleLineOverflowingTheAreaEdgeIsNotScreenText() {
        echo.record(Reading(lines: [inRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67)]), region: region)
        let reading = Reading(lines: [at("Lucia, I told you twice already", 0.30, 0.585, 0.70, 0.625),
                                      at("Find a vehicle", 0.80, 0.30, 0.95, 0.34)])
        XCTAssertEqual(echo.filter(reading).lines.map(\.text), ["Find a vehicle"])
        // Altyazı kalkınca bitişik satır kuralı da kalkar.
        time += SubtitleEcho.adjacentMs + 1
        XCTAssertEqual(echo.filter(reading).lines.count, 2)
    }

    /// Alandan geniş altyazının ucu ya da hazır mesaj alanına düşen parçası metinle tanınır.
    func testTextReadByTheSubtitleLineIsNotScreenTextAnywhere() {
        echo.record(Reading(lines: [inRegion("You better get to the docks before the cops do", 0.15, 0.80, 0.85, 0.84)]),
                    region: region)
        XCTAssertTrue(echo.isEcho("YOU BETTER GET TO THE DOCKS BEFORE THE COPS DO"))
        XCTAssertTrue(echo.isEcho("the docks before the cops do"), "parça")
        XCTAssertFalse(echo.isEcho("Get to the docks"), "kısa ve farklı görev yazısı")
        // Görev alanında (yer kuralı kapalı) da metinle atılır.
        let mission = Reading(lines: [at("You better get to the docks before the cops do", 0.2, 0.2, 0.8, 0.6)])
        XCTAssertTrue(echo.filter(mission, geometry: false).lines.isEmpty)
        time += SubtitleEcho.windowMs + 1
        XCTAssertFalse(echo.isEcho("You better get to the docks before the cops do"))
    }

    func testFullScreenSubtitleAreaDoesNotHideEverything() {
        echo.record(.empty, region: CropRegion(top: 0, bottom: 1, left: 0, right: 1))
        let reading = Reading(lines: [at("Press up to open the phone", 0.4, 0.5, 0.6, 0.55)])
        XCTAssertEqual(echo.filter(reading).lines.count, 1)
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
        var sent: [String] = []
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) { sent.append(text) }
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?, icons: [IconPlacement]?,
                        blocks: [ScreenTranslation.Item]?) { sent.append(text) }
        func clearRegions() {}
    }

    /// Koyu düz panelde açık yazı benzeri çizgiler (hazır alanın arayüz kutusu kanıtı için).
    private func frame() -> CGImage {
        let width = 320, height = 180
        var pixels = [UInt8](repeating: 30, count: width * height)
        for y in 0..<height where (y / 3) % 4 == 0 {
            for x in 0..<width where (x / 4) % 3 == 0 { pixels[y * width + x] = 230 }
        }
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        return context!.makeImage()!
    }

    /// Dedektörün altyazı alanının kenarında bulduğu (yarım karo genişletilmiş) otomatik alan altyazıyı okur: çizilmez.
    func testAutoAreaReadingTheSubtitleSendsNothing() async {
        echo.record(Reading(lines: [inRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67)]), region: region)
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        watcher.subtitleEcho = echo
        // Alan 0,25–0,75 x 0,55–0,70: üst satır alanın dışında, alt satır içinde.
        let area = ExtraArea(id: "auto-1", name: ScreenTextDetector.areaName,
                             region: CropRegion(top: 0.55, bottom: 0.70, left: 0.25, right: 0.75), auto: true)
        func local(_ text: String, _ top: Double, _ bottom: Double) -> TextLine {
            TextLine(text, box: TextBox(left: 0.1, top: (top - 0.55) / 0.15, right: 0.9, bottom: (bottom - 0.55) / 0.15))
        }
        reader.lines = [local("Lucia, I told you twice already", 0.585, 0.625), local("and you still owe me for the boat.", 0.63, 0.67)]
        await watcher.pass(frame(), areas: [area])
        await watcher.pass(frame(), areas: [area])
        XCTAssertTrue(server.sent.allSatisfy(\.isEmpty), "\(server.sent)")
    }

    /// Hazır mesaj alanı altyazı alanıyla kesişir: kesişen yerdeki altyazı parçası çizilmez, mesaj kartı çizilir.
    func testPresetAreaDropsTheSubtitlePartButKeepsItsOwnText() async {
        let reader = Reader(), server = Server()
        let watcher = RegionWatcher(reader: reader, translator: Translator(), server: server)
        watcher.subtitleEcho = echo
        // Altyazı alanın sağ kenarına dek geniş: sağ ucu hazır mesaj alanına düşüyor.
        echo.record(Reading(lines: [inRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.86, 0.795)]),
                    region: region)
        let messages = GameAreaPresets.areas("GTA 6").first { $0.id == GameAreaPresets.phoneId }!
        let r = messages.region
        func local(_ text: String, _ top: Double, _ bottom: Double) -> TextLine {
            TextLine(text, box: TextBox(left: 0.05, top: (top - r.top) / (r.bottom - r.top), right: 0.5,
                                        bottom: (bottom - r.top) / (r.bottom - r.top)))
        }
        // Kartın altyazı alanına (0,62'den aşağısı) düşen mesaj satırı da kartın yazısıdır.
        reader.lines = [local("Meet me at the marina tonight, Jason", 0.50, 0.54), local("Bring the boat keys", 0.66, 0.70),
                        local("before the cops do", 0.80 - 0.04, 0.80 - 0.005)]
        await watcher.pass(frame(), areas: [messages])
        await watcher.pass(frame(), areas: [messages])
        // Yalnız mesaj kartı (36 + 19 harf) çevrilip çizilir; altyazı parçası metne katılmaz.
        XCTAssertEqual(server.sent.count, 1, "\(server.sent)")
        XCTAssertTrue(server.sent.first?.contains("çeviri 36") ?? false, "\(server.sent)")
        XCTAssertTrue(server.sent.first?.contains("çeviri 19") ?? false, "mesaj kartının alt satırı düşmüş: \(server.sent)")
    }
}
