// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI
import XCTest
@testable import CouchSubs

/// Geliştirme aracı: README'deki ekran görüntüleri (docs/screenshots/mac). Yalnız `COUCHSUBS_SCREENSHOTS` ortam
/// değişkeni (klasör) verilince çalışır; `scripts/mac-screenshots.sh` başlatır. Uygulamanın ekranları koyu görünümde,
/// örnek verilerle (sahte hizmetler, bellekteki kayıt) birer pencerede açılır ve pencerenin kendisi (başlık çubuğu
/// dahil, ekranın 2x ölçeğinde) PNG'ye çizilir; Ekran Kaydı izni gerekmez.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var windows: [NSWindow] = []

    func testCaptureScreens() async throws {
        guard let path = ProcessInfo.processInfo.environment["COUCHSUBS_SCREENSHOTS"] else {
            throw XCTSkip("COUCHSUBS_SCREENSHOTS verilmedi")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let main = try await mainModel()
        let setup = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        setup.accountId = Data(repeating: 1, count: 8)
        setup.step = .console

        // Yeni arayüz: her ekran sırayla aynı modelle açılır (sekme ve bölüm modelin bayraklarında).
        let size = CGSize(width: DS.size("windowWidth"), height: DS.size("windowHeight"))
        var screens: [(String, () -> Void)] = [
            ("ana", { main.showSettings = false; main.showHistory = false }),
            ("gecmis", { main.showHistory = true }),
        ]
        for section in SettingsSection.allCases {
            screens.append(("ayarlar-\(section)", { main.showHistory = false; main.settingsSection = section; main.showSettings = true }))
        }
        // Tam ekran (1920 × 1080) görünümleri: içerik reklam bandının üstünde biter, orantı korunur.
        let wide = CGSize(width: 1920, height: 1080)
        screens += [("genis-ana", { main.showSettings = false; main.showHistory = false }),
                    ("genis-ayarlar-basics", { main.showHistory = false; main.settingsSection = .basics; main.showSettings = true }),
                    ("genis-ayarlar-appearance", { main.showHistory = false; main.settingsSection = .appearance; main.showSettings = true })]
        let only = ProcessInfo.processInfo.environment["COUCHSUBS_SCREENSHOT_ONLY"].flatMap { $0.isEmpty ? nil : $0 }
        for (name, prepare) in screens where only == nil || name.hasPrefix(only!) {
            prepare()
            let window = show(AnyView(RootView().environmentObject(main)), size: name.hasPrefix("genis-") ? wide : size, offset: 0)
            try await Task.sleep(for: .seconds(1.5))
            try capture(window).write(to: folder.appendingPathComponent("\(name).png"))
            window.close()
        }
        // Kurulum adımları (karşılama adımı ilk kurulumda açılış animasyonunu gösterir).
        let steps: [(String, AppModel.Step)] = [("kurulum-0-acilis", .welcome), ("kurulum-2-hesap", .secondAccount),
                                                ("kurulum-2b-giris", .psnLogin), ("kurulum-3-ps5", .console), ("kurulum-5-tv", .tv),
                                                ("kurulum-6-hdmi", .hdmi), ("kurulum-7-ceviri", .betterTranslation), ("kurulum-8-dene", .test)]
        for (name, step) in steps where only == nil || name.hasPrefix(only!) {
            setup.step = step
            let window = show(AnyView(WizardView().environmentObject(setup)), size: size, offset: 40)
            try await Task.sleep(for: .seconds(step == .welcome ? 3.5 : 2))
            try capture(window).write(to: folder.appendingPathComponent("\(name).png"))
            window.close()
        }
        // "Altyazı TV'de Görünsün" durumları (sahte liste ve kurulum durumları).
        let lg = LGTV(name: "LG OLED55C3", host: "192.168.1.153"), samsung = LGTV(name: "Samsung QE55Q80", host: "192.168.1.160", brand: .samsung)
        let tvStates: [(String, TVSetupStep.Preview, LGTV?, TVAppState)] = [
            ("tv-1-bos", .init(), nil, .unknown),
            ("tv-2-tariyor", .init(searching: true), nil, .unknown),
            ("tv-3-bulundu", .init(tvs: [lg, samsung]), nil, .unknown),
            ("tv-4-onay", .init(tvs: [lg, samsung], pairingHost: lg.host), nil, .unknown),
            ("tv-5-kuruluyor", .init(tvs: [lg, samsung]), lg, .working),
            ("tv-6-hata", .init(tvs: [lg, samsung]), samsung, .failed(.certificateRejected)),
            ("tv-7-samsung-onkosul", .init(tvs: [samsung]), samsung, .devModeOff),
        ]
        for (name, preview, tv, state) in tvStates where only == nil || name.hasPrefix(only!) {
            TVSetupStep.preview = preview
            let tvModel = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
            tvModel.accountId = Data(repeating: 1, count: 8)
            tvModel.step = .tv
            tvModel.tv = tv
            tvModel.tvApp = state
            let window = show(AnyView(WizardView().environmentObject(tvModel)), size: size, offset: 40)
            try await Task.sleep(for: .seconds(2))
            try capture(window).write(to: folder.appendingPathComponent("kurulum-\(name).png"))
            window.close()
        }
        TVSetupStep.preview = nil
        // Açılır reklam: reklamlar.json › popups (karartılmış zeminle, görselin oranında).
        for ad in PopupAd.catalog where only == nil || "popup-\(ad.id)".hasPrefix(only!) {
            let popup = ZStack {
                Color.dsScrim
                PopupAdView(ad: ad) {}.shadow(color: .black.opacity(0.28), radius: 32, y: 24)
            }
            .frame(width: 640, height: 720)
            .newLook()
            let window = show(AnyView(popup), size: CGSize(width: 640, height: 720), offset: 40)
            try await Task.sleep(for: .seconds(1))
            try capture(window).write(to: folder.appendingPathComponent("popup-\(ad.id).png"))
            window.close()
        }
        windows.forEach { $0.close() }
    }

    /// Perde tasarım dili: bileşen kataloğu, ana ekranlar (Ana Ekran, Geçmiş, Ayarlar'ın bütün bölümleri, oyun sorusu),
    /// kurulum adımları, TV kurulum durumları ve ek pencereler (Hakkında, menü çubuğu), koyu ve açık temada.
    /// `COUCHSUBS_PERDE` (klasör) verilince çalışır; dosyalar `mac-<ekran>-<koyu|acik>.png`. `COUCHSUBS_PERDE_ONLY`
    /// verilirse yalnız adı onunla başlayan ekranlar.
    func testCapturePerde() async throws {
        guard let path = ProcessInfo.processInfo.environment["COUCHSUBS_PERDE"] else { throw XCTSkip("COUCHSUBS_PERDE verilmedi") }
        let only = ProcessInfo.processInfo.environment["COUCHSUBS_PERDE_ONLY"].flatMap { $0.isEmpty ? nil : $0 }
        func wanted(_ name: String) -> Bool { only.map { name.hasPrefix($0) } ?? true }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let main = try await mainModel()
        let size = CGSize(width: DS.size("windowWidth"), height: DS.size("windowHeight"))
        var screens: [(String, () -> Void)] = [
            ("ana", { main.showSettings = false; main.showHistory = false }),
            ("gecmis", { main.showHistory = true }),
        ]
        for section in SettingsSection.allCases {
            screens.append(("ayarlar-\(section)", { main.showHistory = false; main.settingsSection = section; main.showSettings = true }))
        }
        let steps: [(String, AppModel.Step)] = [("kurulum-1-konsol", .welcome), ("kurulum-2-hesap", .secondAccount),
                                                ("kurulum-2b-giris", .psnLogin), ("kurulum-3-ps5", .console), ("kurulum-5-tv", .tv),
                                                ("kurulum-6-hdmi", .hdmi), ("kurulum-7-ceviri", .betterTranslation), ("kurulum-8-dene", .test)]
        let lg = LGTV(name: "LG OLED55C3", host: "192.168.1.153"), samsung = LGTV(name: "Samsung QE55Q80", host: "192.168.1.160", brand: .samsung)
        let tvStates: [(String, TVSetupStep.Preview, LGTV?, TVAppState)] = [
            ("tv-1-tariyor", .init(searching: true), nil, .unknown),
            ("tv-2-bulundu", .init(tvs: [lg, samsung]), nil, .unknown),
            ("tv-3-onay", .init(tvs: [lg, samsung], pairingHost: lg.host), nil, .unknown),
            ("tv-4-kuruluyor", .init(tvs: [lg, samsung]), lg, .working),
            ("tv-5-hazir", .init(tvs: [lg, samsung]), lg, .upToDate("0.9.81")),
            ("tv-6-hata", .init(tvs: [lg, samsung]), samsung, .failed(.certificateRejected)),
        ]
        let introPlayed = UserDefaults.standard.bool(forKey: "introPlayed")
        UserDefaults.standard.set(true, forKey: "introPlayed")
        defer { UserDefaults.standard.set(introPlayed, forKey: "introPlayed") }
        for (theme, dark) in [("koyu", true), ("acik", false)] {
            if wanted("katalog") {
                let catalog = AnyView(ScrollView { PerdeCatalog(columns: 3) }.frame(width: 1280, height: 2560))
                let window = show(catalog, size: CGSize(width: 1280, height: 2560), offset: 0, dark: dark, unconstrained: true)
                try await Task.sleep(for: .seconds(2))
                try capture(window).write(to: folder.appendingPathComponent("mac-katalog-\(theme).png"))
                window.close()
            }
            for (name, prepare) in screens where wanted(name) {
                prepare()
                let window = show(AnyView(RootView().environmentObject(main)), size: size, offset: 0, dark: dark)
                try await Task.sleep(for: .seconds(1.5))
                try capture(window).write(to: folder.appendingPathComponent("mac-\(name)-\(theme).png"))
                window.close()
            }
            // Tam ekran (1920 × 1080): orantı korunur, içerik reklam bandının üstünde biter.
            if wanted("genis-ana") {
                main.showSettings = false
                main.showHistory = false
                let window = show(AnyView(RootView().environmentObject(main)), size: CGSize(width: 1920, height: 1080), offset: 0, dark: dark)
                try await Task.sleep(for: .seconds(1.5))
                try capture(window).write(to: folder.appendingPathComponent("mac-genis-ana-\(theme).png"))
                window.close()
            }
            if wanted("oyun-sor") {
                main.showSettings = false
                main.showHistory = false
                main.gameChoice.ask()
                let window = show(AnyView(RootView().environmentObject(main)), size: size, offset: 0, dark: dark)
                try await Task.sleep(for: .seconds(1.5))
                try capture(window).write(to: folder.appendingPathComponent("mac-oyun-sor-\(theme).png"))
                window.close()
                main.gameChoice.dismiss()
            }
            for (name, step) in steps where wanted(name) {
                let setup = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
                setup.accountId = Data(repeating: 1, count: 8)
                setup.step = step
                let window = show(AnyView(WizardView().environmentObject(setup)), size: size, offset: 40, dark: dark)
                try await Task.sleep(for: .seconds(2))
                try capture(window).write(to: folder.appendingPathComponent("mac-\(name)-\(theme).png"))
                window.close()
            }
            for (name, preview, tv, state) in tvStates where wanted("kurulum-\(name)") {
                TVSetupStep.preview = preview
                let tvModel = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
                tvModel.accountId = Data(repeating: 1, count: 8)
                tvModel.step = .tv
                tvModel.tv = tv
                tvModel.tvApp = state
                let window = show(AnyView(WizardView().environmentObject(tvModel)), size: size, offset: 40, dark: dark)
                try await Task.sleep(for: .seconds(2))
                try capture(window).write(to: folder.appendingPathComponent("mac-kurulum-\(name)-\(theme).png"))
                window.close()
            }
            TVSetupStep.preview = nil
            if wanted("hakkinda") {
                let window = show(AnyView(NewAboutView()), size: CGSize(width: 460, height: 560), offset: 40, dark: dark)
                try await Task.sleep(for: .seconds(1))
                try capture(window).write(to: folder.appendingPathComponent("mac-hakkinda-\(theme).png"))
                window.close()
            }
            if wanted("menu") {
                let window = show(AnyView(MenuBarPanel().environmentObject(main)), size: CGSize(width: 340, height: 330), offset: 40, dark: dark)
                try await Task.sleep(for: .seconds(1))
                try capture(window).write(to: folder.appendingPathComponent("mac-menu-cubugu-\(theme).png"))
                window.close()
            }
        }
        windows.forEach { $0.close() }
    }

    /// Perde'nin boşta süren efektlerinin işlemci maliyeti (hedef ≤ %2): ortam ışığı tek başına (uygulamadaki gerçek boşta
    /// durumu) ve bütün sürekli efektler birden (katalog; en kötü durum), her biri kapı zorla açık / kapalı 15'er sn.
    /// `COUCHSUBS_CPU` verilince çalışır; sonuç konsola `CPU_PERDE` satırıyla yazılır.
    func testPerdeIdleCPU() async throws {
        guard ProcessInfo.processInfo.environment["COUCHSUBS_CPU"] != nil else { throw XCTSkip("COUCHSUBS_CPU verilmedi") }
        defer { DSMotionGate.forced = nil }
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        func measure(_ view: AnyView, size: CGSize, animate: Bool) async throws -> Double {
            DSMotionGate.forced = animate
            let window = show(view, size: size, offset: 0, dark: true)
            try await Task.sleep(for: .seconds(2))
            let (start, began) = (cpu(), Date())
            try await Task.sleep(for: .seconds(15))
            let percent = (cpu() - start) / Date().timeIntervalSince(began) * 100
            window.close()
            return percent
        }
        try await Task.sleep(for: .seconds(10))
        let window = CGSize(width: 1200, height: 760)
        let ambient = AnyView(ZStack { Color.dsBackground; DSAmbientGlow() }.frame(width: 1200, height: 760))
        let ambientStill = try await measure(ambient, size: window, animate: false)
        let ambientMoving = try await measure(ambient, size: window, animate: true)
        let pulse = AnyView(ZStack { Color.dsBackground; DSStatusPill(text: "Çeviri Açık", dot: .dsLiveDot, pulse: true) }.frame(width: 1200, height: 760))
        let pulseStill = try await measure(pulse, size: window, animate: false)
        let pulseMoving = try await measure(pulse, size: window, animate: true)
        print("CPU_PERDE pulse still=\(String(format: "%.2f", pulseStill)) moving=\(String(format: "%.2f", pulseMoving)) " +
              "cost=\(String(format: "%.2f", pulseMoving - pulseStill))")
        let catalog = AnyView(ScrollView { PerdeCatalog(columns: 3) }.frame(width: 1280, height: 900))
        let catalogStill = try await measure(catalog, size: CGSize(width: 1280, height: 900), animate: false)
        let catalogMoving = try await measure(catalog, size: CGSize(width: 1280, height: 900), animate: true)
        print("CPU_PERDE ambient still=\(String(format: "%.2f", ambientStill)) moving=\(String(format: "%.2f", ambientMoving)) " +
              "cost=\(String(format: "%.2f", ambientMoving - ambientStill)) | catalog still=\(String(format: "%.2f", catalogStill)) " +
              "moving=\(String(format: "%.2f", catalogMoving)) cost=\(String(format: "%.2f", catalogMoving - catalogStill))")
        XCTAssertLessThan(ambientMoving - ambientStill, 2)
    }

    /// Gerçek ana pencerenin boşta (çeviri kapalı) işlemci kullanımı: Ana Ekran ve Ayarlar, hareket kapısı açık ve kapalı,
    /// 15'er sn. `COUCHSUBS_CPU` verilince çalışır; `CPU_HOME` satırı. Hedef ≤ %2.
    func testHomeIdleCPU() async throws {
        guard ProcessInfo.processInfo.environment["COUCHSUBS_CPU"] != nil else { throw XCTSkip("COUCHSUBS_CPU verilmedi") }
        defer { DSMotionGate.forced = nil }
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        func measure(_ view: AnyView, animate: Bool?) async throws -> Double {
            DSMotionGate.forced = animate
            let window = show(view, size: CGSize(width: 1200, height: 760), offset: 0, dark: true)
            try await Task.sleep(for: .seconds(3))
            let (start, began) = (cpu(), Date())
            try await Task.sleep(for: .seconds(15))
            let percent = (cpu() - start) / Date().timeIntervalSince(began) * 100
            // Kapanan pencerenin görünümleri (ve görevleri) sonraki ölçüme yük bindirmesin.
            window.contentView = nil
            window.close()
            windows.removeAll { $0 === window }
            try await Task.sleep(for: .seconds(1))
            return percent
        }
        let main = try await mainModel()
        main.isRunning = false
        main.showSettings = false
        main.showHistory = false
        try await Task.sleep(for: .seconds(10))
        let home = AnyView(RootView().environmentObject(main))
        let homeStill = try await measure(home, animate: false)
        let homeMoving = try await measure(home, animate: true)
        // Geçmiş ve Ayarlar'da ortam ışığı durağan (yalnız Ana Ekran'da süzülür): kapı zorlanmadan, uygulamadaki gibi ölçülür.
        var pages: [(String, Double)] = []
        main.showHistory = true
        pages.append(("gecmis", try await measure(home, animate: nil)))
        main.showHistory = false
        for section in [SettingsSection.basics, .appearance, .packs, .outputs] {
            main.settingsSection = section
            main.showSettings = true
            pages.append(("ayarlar-\(section)", try await measure(home, animate: nil)))
        }
        print("CPU_HOME home still=\(String(format: "%.2f", homeStill)) moving=\(String(format: "%.2f", homeMoving)) " +
              "cost=\(String(format: "%.2f", homeMoving - homeStill)) | " +
              pages.map { "\($0.0)=\(String(format: "%.2f", $0.1))" }.joined(separator: " "))
        // Hedef %2; test sürecinde XCTest ve Main Thread Checker yükü de sayıldığı için sınır biraz geniş (gürültü ±0,5).
        XCTAssertLessThan(homeMoving, 2.5)
        for (name, value) in pages { XCTAssertLessThan(value, 2.5, name) }
    }

    /// Ayarlar menüsünün renk geçişinin işlemci maliyeti: aynı pencere önce durağan, sonra oynarken 15'er sn ölçülür;
    /// fark konsola yazılır. `COUCHSUBS_CPU` verilince çalışır; fark %5'i aşarsa başarısız (hedef %2'nin altı).
    func testSettingsNavGlowCPU() async throws {
        guard ProcessInfo.processInfo.environment["COUCHSUBS_CPU"] != nil else { throw XCTSkip("COUCHSUBS_CPU verilmedi") }
        let model = AppModel(services: FakeServices(), store: MemoryStore(), defaults: .isolated())
        let view = SettingsNavGlow().frame(width: 240, height: 560).environmentObject(model)
        defer { SettingsNavGlow.forced = nil }
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        func measure(_ animate: Bool) async throws -> Double {
            SettingsNavGlow.forced = animate
            let window = show(AnyView(view), size: CGSize(width: 240, height: 560), offset: 0)
            try await Task.sleep(for: .seconds(2))
            let (start, began) = (cpu(), Date())
            try await Task.sleep(for: .seconds(15))
            let percent = (cpu() - start) / Date().timeIntervalSince(began) * 100
            window.close()
            return percent
        }
        // Açılıştaki işler (paket yükleme vb.) ölçümü bozmasın: önce bekle; durağan ölçüm iki kez, ortalaması.
        try await Task.sleep(for: .seconds(20))
        let before = try await measure(false)
        let moving = try await measure(true)
        let still = (before + (try await measure(false))) / 2
        print("CPU_NAV_GLOW still=\(String(format: "%.2f", still)) moving=\(String(format: "%.2f", moving)) cost=\(String(format: "%.2f", moving - still))")
        XCTAssertLessThan(moving - still, 5)
    }

    /// Pencereyi çerçevesiyle (başlık çubuğu ve düğmeleri dahil) PNG olarak çizer.
    private func capture(_ window: NSWindow) throws -> Data {
        let view = try XCTUnwrap(window.contentView?.superview ?? window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Kurulumu bitmiş, çeviri süren uygulama: PS5 ve TV bağlı, DeepL seçili, son altyazılar geçmişte.
    private func mainModel() async throws -> AppModel {
        let store = MemoryStore()
        store.save(Data(repeating: 1, count: 8), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.253", name: "PS5-789", registKey: Data(repeating: 0x31, count: 16),
                                     morning: Data(repeating: 2, count: 16)), for: StoreKey.console)
        store.save(LGTV(name: "LG TV", host: "192.168.1.153"), for: StoreKey.tv)
        store.save("tv-key", for: StoreKey.tvKey)
        let model = AppModel(services: FakeServices(), store: store, defaults: .isolated())
        model.settings.translationEngine = .deepL
        // Ayarlar › Altyazı Alanı'nda bir ek alan, Seslendirme'de açık dublaj görünsün.
        model.settings.addExtraArea(.quest, name: String(localized: "Quest"))
        model.settings.dubbing.enabled = true
        model.isRunning = true
        model.sessionState = .streaming
        model.tvClients = 1
        let sample = [("I gotta tell you this, Franklin.", "Bunu sana söylemem lazım, Franklin."),
                      ("Take out the Lost.", "Lost üyelerini ortadan kaldır."),
                      ("Are you listening to me?", "Dinliyor musun beni?")]
        for (source, translation) in sample {
            model.history.add(source: source, translation: translation)
            model.lastSource = source
            model.lastTranslation = translation
        }
        // Paketler açılışta arka planda yüklenir.
        let deadline = Date().addingTimeInterval(10)
        while model.installedPacks.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        return model
    }

    /// Ekrandan büyük pencere (bileşen kataloğu): sistem pencereyi ekrana sığdırmak için küçültmesin.
    private final class TallWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private func show(_ view: AnyView, size: CGSize, offset: CGFloat, dark: Bool? = nil, unconstrained: Bool = false) -> NSWindow {
        let window = (unconstrained ? TallWindow.self : NSWindow.self).init(contentRect: NSRect(origin: .zero, size: size),
                                                                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "CouchSubs"
        window.titlebarAppearsTransparent = true
        let darkMode = dark ?? !(ProcessInfo.processInfo.environment["COUCHSUBS_SCREENSHOT_DARK"] ?? "").isEmpty
        window.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
        window.backgroundColor = NSColor(Color.dsBackground)
        window.contentView = NSHostingView(rootView: view.appSurface().frame(width: size.width, height: size.height))
        window.setFrameTopLeftPoint(NSPoint(x: 80 + offset, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 40 - offset))
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }
}
