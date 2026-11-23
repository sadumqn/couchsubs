// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI
import XCTest
@testable import CouchSubs

/// Yeni arayüzün mantık parçaları: tasarım değerleri, sürüm notları, altyazı görünümü eşlemeleri, hazır bekleme değerleri.
@MainActor
final class NewDesignTests: XCTestCase {
    /// tasarim.json uygulama paketinde ve okunuyor (eksikse açılışta çökerdi).
    func testDesignTokensLoad() {
        XCTAssertEqual(DS.size("windowWidth"), 1200)
        XCTAssertEqual(DS.size("windowHeight"), 760)
        XCTAssertNotNil(DS.tokens.color["amber"])
        XCTAssertEqual(DSTokens.rgba("#F5B83D33")?.3 ?? 0, 0.2, accuracy: 0.01)
    }

    /// tasarim.json v2 (Perde): koyu tema varsayılan, yeni renk/efekt/hareket belirteçleri okunuyor, eski anahtarlar duruyor.
    func testPerdeTokensLoad() {
        let tokens = DS.tokens
        XCTAssertEqual(tokens.version, 2)
        XCTAssertEqual(tokens.defaultTheme, "dark")
        for name in ["surfaceRaised", "surfaceHigh", "segPill", "borderStrong", "topHighlight", "amberGlow", "amberRing", "info",
                     "infoSoft", "infoText", "glass", "glassBorder", "charTeal", "charPeach", "subtitlePlate", "subtitleText", "coverScrim"] {
            XCTAssertNotNil(tokens.color[name], name)
        }
        // v1 anahtarları korunur (Windows ve eski ekranlar okur).
        for name in ["background", "surface", "field", "border", "text", "muted", "amber", "amberText", "live", "liveDot", "peach", "sky"] {
            XCTAssertNotNil(tokens.color[name], name)
        }
        XCTAssertEqual(tokens.motion.celebrate, 600)
        XCTAssertEqual(tokens.motion.livePulse, 1600)
        XCTAssertEqual(tokens.motion.spring, [0.34, 1.56, 0.64, 1])
        XCTAssertEqual(DS.effect("ambientBlobs", "maxFps", 0), 15)
        XCTAssertEqual(DS.effect("sheen", "period", 0), 1800)
        XCTAssertEqual(DS.size("coverAspect"), 0.75, accuracy: 0.001)
        XCTAssertNil(tokens.font["ios"], "iPhone metin stilleri fontIOS'ta; font bölümünde yalnız düz yazı biçimleri")
        // Bütün renkler okunabilir onaltılık değer.
        for (name, pair) in tokens.color {
            XCTAssertNotNil(DSTokens.rgba(pair.light), name)
            XCTAssertNotNil(DSTokens.rgba(pair.dark), name)
        }
    }

    /// Geçmiş satırları (kullanıcı şikâyeti: koyu temada soluk): çeviri ≥ 7:1, İngilizce ve saat ≥ 4.5:1; iki temada, kart
    /// yüzeyinde ve seçili satırın amber zemininde. Durdur düğmesi: beyaz yazı dolu zeminde ≥ 3:1 (kalın 15 pt+).
    func testHistoryRowAndStopContrast() {
        let tokens = DS.tokens
        var failures: [String] = []
        for mode in ["light", "dark"] {
            func hex(_ name: String) -> String { mode == "light" ? tokens.color[name]!.light : tokens.color[name]!.dark }
            for back in ["surface", "amberSoft"] {
                for (token, minimum) in [(HistoryRowStyle.translationToken, 7.0), (HistoryRowStyle.sourceToken, 4.5),
                                         (HistoryRowStyle.timeToken, 4.5)] {
                    let ratio = DSTokens.contrast(hex(token), hex(back), over: hex("surface"))
                    if ratio < minimum { failures.append("\(mode) \(token) / \(back): \(String(format: "%.2f", ratio))") }
                }
            }
            let stop = DSTokens.contrast(hex("onStop"), hex("stopFill"), over: hex("background"))
            if stop < 3 { failures.append("\(mode) onStop / stopFill: \(String(format: "%.2f", stop))") }
        }
        XCTAssertEqual(failures, [])
    }

    /// Kaydırıcı hizası: iz tam genişlik, uç etiketleri kenarlarda. Sol kenar = başlığın sol kenarı = "16"nın sol kenarı;
    /// sağ kenar = değer yazısının ve "50"nin sağ kenarı (fark ≤ 1 pt). Hem hesap hem gerçek çizim (piksel) ölçülür.
    func testSliderAlignsWithLabels() throws {
        XCTAssertEqual(DSSlider.trackSpan(width: 300), 0...300)
        XCTAssertEqual(DSSlider.knobCenter(fraction: 0, width: 300), 0)
        XCTAssertEqual(DSSlider.knobCenter(fraction: 1, width: 300), 300)
        func render(_ value: Double) throws -> (CGImage, CGFloat) {
            let view = VStack(alignment: .leading, spacing: 4) {
                DSSlider(value: .constant(value), range: 16...50, step: 1)
                DSSliderRange(low: "16", high: "50")
            }
            .frame(width: 300)
            .padding(40)
            .background(Color(red: 1, green: 0, blue: 1))
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return (try XCTUnwrap(renderer.cgImage), 2)
        }
        func pixels(_ image: CGImage) -> (Int, Int, (Int, Int) -> (Int, Int, Int)) {
            let data = CFDataGetBytePtr(image.dataProvider!.data!)!
            let bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
            return (image.width, image.height, { x, y in
                let i = y * bpr + x * bpp
                return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
            })
        }
        func isMagenta(_ p: (Int, Int, Int)) -> Bool { p.0 > 200 && p.1 < 60 && p.2 > 200 }
        // Değer en büyükken amber iz soldan başlar; en küçükken iz (alan rengi) sağ kenara kadar uzanır.
        let (full, scale) = try render(50)
        let (fw, _, fp) = pixels(full)
        let row = Int((40 + 12) * scale)
        let firstLeft = (0..<fw).first { !isMagenta(fp($0, row)) }.map { CGFloat($0) / scale }
        XCTAssertEqual(try XCTUnwrap(firstLeft), 40, accuracy: 1, "izin sol ucu")
        let (empty, _) = try render(16)
        let (ew, eh, ep) = pixels(empty)
        let lastRight = (0..<ew).last { !isMagenta(ep($0, row)) }.map { CGFloat($0 + 1) / scale }
        XCTAssertEqual(try XCTUnwrap(lastRight), 340, accuracy: 1, "izin sağ ucu")
        // Uç etiketleri: "16"nın mürekkebi sol kenarda, "50"ninki sağ kenarda başlar/biter (yazı iç boşluğu ≤ 1 pt).
        let labelRows = Int((40 + 24 + 4) * scale)..<min(eh, Int((40 + 24 + 4 + 16) * scale))
        var inkLeft = CGFloat.infinity, inkRight: CGFloat = 0
        for y in labelRows {
            for x in 0..<ew where !isMagenta(ep(x, y)) {
                inkLeft = min(inkLeft, CGFloat(x) / scale)
                inkRight = max(inkRight, CGFloat(x + 1) / scale)
            }
        }
        XCTAssertEqual(inkLeft, 40, accuracy: 1.5, "16 etiketinin sol kenarı")
        XCTAssertEqual(inkRight, 340, accuracy: 1.5, "50 etiketinin sağ kenarı")
    }

    /// Tipografik kapak kısaltmaları (gerçek kapak/logo yok): oyunun adından kararlı ve kısa.
    func testCoverMonogram() {
        XCTAssertEqual(DSCoverArt.monogram("GTA V"), "GTA")
        XCTAssertEqual(DSCoverArt.numeral("GTA V"), "V")
        XCTAssertEqual(DSCoverArt.monogram("Grand Theft Auto VI"), "GTA")
        XCTAssertEqual(DSCoverArt.numeral("Grand Theft Auto VI"), "VI")
        XCTAssertEqual(DSCoverArt.monogram("Red Dead Redemption 2"), "RDR")
        XCTAssertEqual(DSCoverArt.numeral("Red Dead Redemption 2"), "2")
        XCTAssertEqual(DSCoverArt.monogram("Mafia"), "Ma")
        XCTAssertNil(DSCoverArt.numeral("Mafia"))
        XCTAssertEqual(DSCoverArt.monogram("Assassin's Creed Shadows"), "ACS")
        XCTAssertEqual(DSCoverArt.monogram("Cyberpunk 2077"), "Cy")
        XCTAssertEqual(DSCoverArt.paletteIndex("GTA V"), DSCoverArt.paletteIndex("GTA V"))
    }

    /// Perde kontrastı: her yazı rengi her yüzeyde, her iki temada en az 4.5:1 (WCAG AA). Saydam zeminler altlarındaki
    /// yüzeye karıştırılarak ölçülür. Soluk (faint) yalnız süs/ikincil etiket olduğundan dışarıda.
    func testPerdeTextContrast() {
        let tokens = DS.tokens
        var failures: [String] = []
        func check(_ text: String, on back: String, over base: String = "background", minimum: Double = 4.5) {
            for mode in ["light", "dark"] {
                func hex(_ name: String) -> String { mode == "light" ? tokens.color[name]!.light : tokens.color[name]!.dark }
                let ratio = DSTokens.contrast(hex(text), hex(back), over: hex(base))
                if ratio < minimum { failures.append("\(mode) \(text) / \(back): \(String(format: "%.2f", ratio))") }
            }
        }
        for text in ["text", "muted", "amberText", "successText", "liveText", "infoText"] {
            for back in ["background", "surface", "surfaceRaised", "surfaceHigh", "field"] { check(text, on: back) }
        }
        check("amberText", on: "amberSoft", over: "surface")
        check("successText", on: "successSoft", over: "surface")
        check("liveText", on: "liveSoft", over: "surface")
        check("infoText", on: "infoSoft", over: "surface")
        check("text", on: "segPill")
        check("onAmber", on: "amber")
        check("onCharcoal", on: "charcoal")
        // Altyazı plakası her temada aynı; en kötü durum açık sahne (beyaz) üstü.
        for mode in [DS.tokens.color["subtitlePlate"]!.light, DS.tokens.color["subtitlePlate"]!.dark] {
            let ratio = DSTokens.contrast(tokens.color["subtitleText"]!.dark, mode, over: "#FFFFFF")
            if ratio < 7 { failures.append("subtitleText / subtitlePlate: \(ratio)") }
        }
        // Karakter adı renkleri kendi temalarının zemininde.
        for name in ["charTeal", "charPeach"] {
            check(name, on: "background")
            check(name, on: "surface")
        }
        XCTAssertEqual(failures, [])
    }

    /// Tek hareket kapısı: çeviri, hareketi azalt / Geçiş Animasyonları ya da arka plan sürekli efektleri durdurur; canlı
    /// nabız çeviri sürerken atar ama hareket azaltılmışken ya da arka planda durur.
    func testMotionGate() {
        XCTAssertTrue(DSMotionGate().ambient)
        XCTAssertTrue(DSMotionGate().live)
        XCTAssertFalse(DSMotionGate(translating: true).ambient)
        XCTAssertTrue(DSMotionGate(translating: true).live)
        XCTAssertFalse(DSMotionGate(reduced: true).ambient)
        XCTAssertFalse(DSMotionGate(reduced: true).live)
        XCTAssertFalse(DSMotionGate(active: false).ambient)
        XCTAssertFalse(DSMotionGate(active: false).live)
        // Uygulamanın çeviri durumu bütün pencerelerin kapısına gider.
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        model.isRunning = true
        XCTAssertTrue(DSMotionState.shared.translating)
        model.isRunning = false
        XCTAssertFalse(DSMotionState.shared.translating)
    }

    /// Perde koyu temalıdır: yeni arayüze geçiş kullanıcının Görünüm ayarını değiştirmez (eskiden koyu → açık çevrilirdi).
    func testAdoptingNewDesignKeepsAppearance() {
        defer { AppAppearance.dark.apply() }
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        XCTAssertEqual(model.settings.appearance, .dark)
        model.adoptNewDesign()
        XCTAssertEqual(model.settings.appearance, .dark)
        let light = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        light.settings.appearance = .light
        light.adoptNewDesign()
        XCTAssertEqual(light.settings.appearance, .light)
    }

    func testReleaseNotesParseCurrentAndPrevious() {
        let text = """
        Giriş.

        **Bu sürümde yeni** (yalnız hata düzeltmeleri)

        - **Android TV'de siyah ekran**: Görüntü modu Otomatik.
        - **Güncelleme penceresi:** Yalnız yeni notlar.

        **beta.83'te gelenler:** GTA 6 telefon mesajları, haber bandı (#933), Samsung'da AS400 uyarısı düzeltmesi.
        """
        let notes = ReleaseNotes.parse(text)
        XCTAssertEqual(notes.current, ["Android TV'de siyah ekran: Görüntü modu Otomatik.", "Güncelleme penceresi: Yalnız yeni notlar."])
        XCTAssertEqual(notes.previous.count, 3)
        XCTAssertEqual(notes.previous.first, "GTA 6 telefon mesajları.")
        // Uygulamayla gelen dosya da okunuyor.
        XCTAssertFalse(ReleaseNotes.load().current.isEmpty)
    }

    /// 16–50 kaydırıcısı TV yazı boyuna (16–90) doğrusal eşlenir; uçlar korunur, varsayılan 46 ≈ 30.
    func testTextSizeMapping() {
        XCTAssertEqual(SubtitlePalette.fontSize(16), 16)
        XCTAssertEqual(SubtitlePalette.fontSize(50), 90)
        XCTAssertEqual(SubtitlePalette.display(90), 50)
        XCTAssertEqual(SubtitlePalette.display(46), 30)
        for value in 16...50 { XCTAssertEqual(SubtitlePalette.display(SubtitlePalette.fontSize(value)), value) }
    }

    func testLowContrastWarning() {
        var style = SubtitleStyle()
        style.textHex = "#FFFFFF"
        XCTAssertFalse(SubtitlePalette.lowContrast(style))
        style.textHex = "#111114"
        XCTAssertTrue(SubtitlePalette.lowContrast(style))
        style.backgroundColor = "#FFFFFF"
        style.background = 100
        XCTAssertFalse(SubtitlePalette.lowContrast(style))
    }

    /// Hızlı / Dengeli / Doğru mevcut iki beklemenin hazır değerleridir; Dengeli varsayılandır.
    func testTranslationPacePresets() {
        XCTAssertEqual(TranslationPace.of(UserSettings()), .balanced)
        var settings = UserSettings()
        settings.misreadWaitMs = 400
        settings.partialWaitMs = 0
        XCTAssertEqual(TranslationPace.of(settings), .fast)
        settings.partialWaitMs = 123
        XCTAssertNil(TranslationPace.of(settings))
    }

    func testSpeakerSplit() {
        let split = SpeakerSplit("Jason: Tamam. Gidelim.")
        XCTAssertEqual(split.speaker, "Jason:")
        XCTAssertEqual(split.line, "Tamam. Gidelim.")
        XCTAssertNil(SpeakerSplit("Gel buraya.").speaker)
    }

    /// Denetimler her maddeyi döner; PS5 bulunamadıysa "PS5 Yanıt Veriyor" sorunlu, Uzaktan Oynama hep bilinmiyor.
    func testSetupChecksNeverGuess() {
        let checks = SetupCheck.run(consoles: [])
        XCTAssertEqual(checks.map(\.kind), SetupCheck.Kind.allCases)
        XCTAssertEqual(checks.first { $0.kind == .ps5Responds }?.state, .problem)
        XCTAssertEqual(checks.first { $0.kind == .remotePlay }?.state, .unknown)
        XCTAssertEqual(checks.first { $0.kind == .restModeInternet }?.state, .unknown)
    }

    /// Dikey ritim tek yerde: başlık → denetim 8, denetim → açıklama 6, birimler arası 24.
    func testVerticalRhythmTokens() {
        XCTAssertEqual(DS.unitTitleGap, 8)
        XCTAssertEqual(DS.unitHintGap, 6)
        XCTAssertEqual(DS.unitGap, 24)
    }

    /// "Günlüğü Kopyala": güncel .log dosyaları maskelenip zip'e girer, eski ve günlük olmayan dosyalar girmez; büyük
    /// günlüğün yalnız sonu alınır. Gerçek ~/Library/Logs'a dokunmaz (geçici klasör).
    func testLogArchiveMasksSecretsAndZips() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("logarchive-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Logs", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let now = Date()
        try Data("passphrase=A1B2C3 api_key: AIzaSyX\nPS5 192.168.1.20 bağlandı\n".utf8).write(to: source.appendingPathComponent("tvinstall.log"))
        try Data("access_token=eyJhbGciOiJIUzI1NiJ9 Bearer abc.def\n".utf8).write(to: source.appendingPathComponent("altyazi.log"))
        try Data("x".utf8).write(to: source.appendingPathComponent("notlar.txt"))
        let old = source.appendingPathComponent("eski.log")
        try Data("eski\n".utf8).write(to: old)
        try manager.setAttributes([.modificationDate: now.addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: old.path)

        XCTAssertEqual(LogArchive.logs(in: source, now: now).map(\.lastPathComponent), ["altyazi.log", "tvinstall.log"])
        let zip = try LogArchive.make(from: source, into: output, header: "CouchSubs test", now: now)
        XCTAssertEqual(zip.lastPathComponent, LogArchive.fileName(now))
        XCTAssertTrue(zip.lastPathComponent.hasPrefix("CouchSubs-gunluk-"))

        let unzip = root.appendingPathComponent("unzip", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unzip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let folder = unzip.appendingPathComponent("CouchSubs-gunluk", isDirectory: true)
        let names = try manager.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["altyazi.log", "bilgi.txt", "tvinstall.log"])
        let tv = try String(contentsOf: folder.appendingPathComponent("tvinstall.log"), encoding: .utf8)
        XCTAssertFalse(tv.contains("A1B2C3"))
        XCTAssertFalse(tv.contains("AIzaSyX"))
        XCTAssertTrue(tv.contains("192.168.1.20"))
        let subtitles = try String(contentsOf: folder.appendingPathComponent("altyazi.log"), encoding: .utf8)
        XCTAssertFalse(subtitles.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertFalse(subtitles.contains("abc.def"))
    }

    func testLogArchiveTakesTailOfLargeLog() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("buyuk-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        let line = String(repeating: "a", count: 99) + "\n"
        try Data(String(repeating: line, count: 30_000).utf8).write(to: file)
        let tail = try XCTUnwrap(LogArchive.tail(file))
        XCTAssertLessThanOrEqual(tail.utf8.count, LogArchive.maxBytesPerLog)
        XCTAssertTrue(tail.hasPrefix(line))
    }

    /// Açılır reklam reklamlar.json › popups'tan gelir (Enmera dikey görseli ve bağlantısı). Görsel yoksa, açılamıyorsa,
    /// bağlantı bozuksa ya da liste boşsa açılır reklam hiç açılmaz: yer tutucu ya da logo asla gösterilmez.
    func testPopupAdNeverShowsWithoutImage() throws {
        let json = Data(#"{"popups":[{"id":"a","image":"a.jpg","link":"https://enmera.com.tr"},{"id":"b","image":"yok.jpg","link":"https://enmera.com.tr"}],"ads":[]}"#.utf8)
        let picture = NSImage(size: NSSize(width: 9, height: 16), flipped: false) { _ in true }
        XCTAssertEqual(PopupAd.load(json: json) { $0 == "a.jpg" ? picture : nil }.map(\.id), ["a"])
        XCTAssertTrue(PopupAd.load(json: json) { _ in nil }.isEmpty)
        XCTAssertTrue(PopupAd.load(json: nil) { _ in picture }.isEmpty)
        XCTAssertTrue(PopupAd.load(json: Data(#"{"ads":[]}"#.utf8)) { _ in picture }.isEmpty)
        XCTAssertTrue(PopupAd.load(json: Data("bozuk".utf8)) { _ in picture }.isEmpty)
        XCTAssertNil(PopupAd.pick(from: []))
        // Uygulamayla gelen gerçek reklam: dikey Enmera görseli yükleniyor, tıklanınca Enmera Commerce sayfası.
        let ad = try XCTUnwrap(PopupAd.catalog.first)
        XCTAssertLessThan(ad.aspect, 1)
        XCTAssertEqual(ad.url.host, "enmera.com.tr")
        XCTAssertEqual(PopupAd.pick(from: PopupAd.catalog)?.id, ad.id)
    }
}
