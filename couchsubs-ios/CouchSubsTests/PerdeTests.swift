// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import SwiftUI
import UIKit
import XCTest
@testable import CouchSubs

@MainActor
private final class SilentAnalytics: AnalyticsLogging {
    func log(_ event: AnalyticsEvent) {}
    func screen(_ name: String) {}
    func setCollection(_ enabled: Bool) {}
}

/// Perde tasarım dili, iPhone: tasarim.json v2 okunuyor, yazılar her iki temada okunaklı (≥ 4.5:1), hareket kapısı Mac'le
/// aynı; `COUCHSUBS_PERDE` (klasör) verilince bileşen kataloğu ve ana ekranın koyu/açık görüntüleri çekilir.
@MainActor
final class PerdeTests: XCTestCase {
    func testTokensLoad() {
        XCTAssertEqual(DS.tokens.version, 2)
        XCTAssertEqual(DS.tokens.defaultTheme, "dark")
        XCTAssertNotNil(DS.tokens.color["surfaceRaised"])
        XCTAssertEqual(DS.size("switchWidthIOS"), 51)
        XCTAssertEqual(DS.tokens.motion.celebrate, 600)
        // Varsayılan görünüm koyu.
        XCTAssertEqual(UserSettings().appearance, .dark)
    }

    func testTextContrast() {
        var failures: [String] = []
        let color = DS.tokens.color
        for mode in ["light", "dark"] {
            func hex(_ name: String) -> String { mode == "light" ? color[name]!.light : color[name]!.dark }
            for text in ["text", "muted", "amberText", "successText", "liveText", "infoText"] {
                for back in ["background", "surface", "surfaceRaised", "surfaceHigh", "field"] {
                    let ratio = DSTokens.contrast(hex(text), hex(back), over: hex("background"))
                    if ratio < 4.5 { failures.append("\(mode) \(text)/\(back) \(ratio)") }
                }
            }
            for (text, soft) in [("amberText", "amberSoft"), ("successText", "successSoft"), ("liveText", "liveSoft"), ("infoText", "infoSoft")] {
                let ratio = DSTokens.contrast(hex(text), hex(soft), over: hex("surface"))
                if ratio < 4.5 { failures.append("\(mode) \(text)/\(soft) \(ratio)") }
            }
            if DSTokens.contrast(hex("onAmber"), hex("amber")) < 4.5 { failures.append("\(mode) onAmber") }
        }
        XCTAssertEqual(failures, [])
    }

    func testMotionGate() {
        XCTAssertTrue(DSMotionGate().ambient)
        XCTAssertFalse(DSMotionGate(translating: true).ambient)
        XCTAssertTrue(DSMotionGate(translating: true).live)
        XCTAssertFalse(DSMotionGate(reduced: true).live)
        XCTAssertFalse(DSMotionGate(active: false).ambient)
    }

    func testCapturePerde() async throws {
        guard let path = ProcessInfo.processInfo.environment["COUCHSUBS_PERDE"] else { throw XCTSkip("COUCHSUBS_PERDE verilmedi") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = EphemeralStore()
        store.save(Data([1, 2, 3]), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.103", name: "PS5-002", registKey: Data(), morning: Data()), for: StoreKey.console)
        store.save(LGTV(name: "Salon TV", host: "192.168.1.50", brand: .lg), for: StoreKey.tv)
        store.save("demo", for: StoreKey.tvKey)
        store.save(true, for: StoreKey.setupComplete)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = PhoneModel(services: LivePhoneServices(), store: store, defaults: defaults)
        let app = AppModel(analytics: SilentAnalytics(), packStore: nil, library: GamePackLibrary(bundled: nil, user: nil), defaults: defaults)
        let phone = CGSize(width: 393, height: 852)
        for (theme, style) in [("koyu", UIUserInterfaceStyle.dark), ("acik", .light)] {
            // Katalog ekrandan uzun: katman ağacı doğrudan çizilir (cam katmanının bulanıklığı burada düz renk görünür).
            let catalog = AnyView(PerdeCatalog(columns: 1).frame(width: phone.width).frame(height: 5000, alignment: .top))
            try await snapshot(catalog, size: CGSize(width: phone.width, height: 5000), style: style, layer: true)
                .write(to: folder.appendingPathComponent("iphone-katalog-\(theme).png"))
            let home = AnyView(NavigationStack { HomeScreen(path: .constant([])) }
                .environmentObject(model).environmentObject(app))
            try await snapshot(home, size: phone, style: style).write(to: folder.appendingPathComponent("iphone-ana-\(theme).png"))
            let settings = AnyView(NavigationStack { SettingsPageScreen(section: .basics, path: .constant([])) }
                .environmentObject(model).environmentObject(app))
            try await snapshot(settings, size: phone, style: style).write(to: folder.appendingPathComponent("iphone-ayarlar-\(theme).png"))
        }
    }

    /// Perde iPhone ekranları (adım 5): `COUCHSUBS_PERDE_PHONE` (klasör) verilince ana ekranlar iki boyda (SE 375×667,
    /// Pro Max 440×956) ve iki temada `iphone-<ekran>-<boy>-<tema>.png` olarak çekilir. Sekme çubuğu ve reklam şeridi
    /// uygulamadaki gibi.
    func testCapturePhoneScreens() async throws {
        guard let path = ProcessInfo.processInfo.environment["COUCHSUBS_PERDE_PHONE"] else { throw XCTSkip("COUCHSUBS_PERDE_PHONE verilmedi") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = EphemeralStore()
        store.save(Data([1, 2, 3]), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.103", name: "PS5-002", registKey: Data(), morning: Data()), for: StoreKey.console)
        store.save(LGTV(name: "Salon TV", host: "192.168.1.50", brand: .lg), for: StoreKey.tv)
        store.save("demo", for: StoreKey.tvKey)
        store.save(true, for: StoreKey.setupComplete)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let library = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory, user: nil)
        let model = PhoneModel(services: LivePhoneServices(), store: store, defaults: defaults, packs: library)
        model.reloadPackList()
        let app = AppModel(analytics: SilentAnalytics(), packStore: nil, library: library, defaults: defaults)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        func shell(_ tab: PhoneTab, ad: Bool = true, @ViewBuilder _ screen: () -> some View) -> AnyView {
            AnyView(NavigationStack {
                screen().environment(\.mobileAdBand, ad).environment(\.perdeTabBar, PerdeTabBarState(active: tab) { _ in })
            }
            .environmentObject(model).environmentObject(app))
        }
        let screens: [(String, AnyView)] = [
            ("ana", shell(.home) { HomeScreen(path: .constant([])) }),
            ("ayarlar", shell(.settings) { SettingsScreen(path: .constant([])) }),
            ("altyazi-gorunumu", shell(.settings) { SettingsPageScreen(section: .appearance, path: .constant([])) }),
            ("paketler", shell(.settings) { PacksScreen() }),
            ("gecmis", shell(.history) { HistoryScreen() }),
            ("tv-kurulum", AnyView(NavigationStack { TVInstallScreen() }.environmentObject(model).environmentObject(app))),
            ("ps5-esleme", AnyView(PS5PairScreen(onDone: {}).environmentObject(model).environmentObject(app))),
            ("karsilama", AnyView(WelcomeFlow(onFinish: {}).environmentObject(model).environmentObject(app))),
        ]
        let sizes: [(String, CGSize)] = [("se", CGSize(width: 375, height: 667)), ("promax", CGSize(width: 440, height: 956))]
        for (theme, style) in [("koyu", UIUserInterfaceStyle.dark), ("acik", .light)] {
            for (sizeName, size) in sizes {
                for (name, view) in screens {
                    try await snapshot(view, size: size, style: style)
                        .write(to: folder.appendingPathComponent("iphone-\(name)-\(sizeName)-\(theme).png"))
                }
                // Canlı çeviri: deneme modu (örnek kareler) çalışırken.
                if model.isRunning {
                    try await snapshot(shell(.home, ad: false) { RunningScreen(path: .constant([])) }, size: size, style: style)
                        .write(to: folder.appendingPathComponent("iphone-canli-\(sizeName)-\(theme).png"))
                }
            }
            if !model.isRunning {
                await model.startDemo()
                try await Task.sleep(nanoseconds: 6_000_000_000)
                for (sizeName, size) in sizes {
                    try await snapshot(shell(.home, ad: false) { RunningScreen(path: .constant([])) }, size: size, style: style)
                        .write(to: folder.appendingPathComponent("iphone-canli-\(sizeName)-\(theme).png"))
                }
            }
        }
        model.exitDemo()
    }

    /// Görünümü uygulamanın sahnesinde bir pencerede açar ve PNG'ye çizer (malzeme/cam katmanları dahil).
    private func snapshot(_ view: AnyView, size: CGSize, style: UIUserInterfaceStyle, layer: Bool = false) async throws -> Data {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: view.dsMotionGate(translating: false).toggleStyle(DSToggleStyle()))
        host.view.backgroundColor = UIColor(Color.dsBackground)
        window.rootViewController = host
        window.isHidden = false
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            if layer { window.layer.render(in: context.cgContext) } else { window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        }
        window.isHidden = true
        return try XCTUnwrap(image.pngData())
    }
}
