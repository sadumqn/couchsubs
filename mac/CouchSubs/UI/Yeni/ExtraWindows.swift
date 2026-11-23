// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI

// Tuval 17–18: menü çubuğu penceresi, Hakkında, Sürüm Notları ve açılır reklam.

private struct CheckForUpdatesKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Sparkle'ın "Güncellemeleri Denetle…" eylemi (Mac App Store sürümünde nil; güncellemeyi App Store yapar).
    var checkForUpdates: (() -> Void)? {
        get { self[CheckForUpdatesKey.self] }
        set { self[CheckForUpdatesKey.self] = newValue }
    }
}

// MARK: Hakkında

/// Hakkında: logo, sürüm, lisans ve teşekkürler, Kaynak ve Güncellemeleri Denetle…, altta Enmera logosu ve
/// "Telif Hakkı © 2026 Enmera" (kişi adı yok).
struct NewAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.checkForUpdates) private var checkForUpdates

    var body: some View {
        VStack(spacing: DS.space("s")) {
            HStack {
                DSMonoLabel("About")
                Spacer()
            }
            DSLogoMark(height: 64, breathing: false)
                .shadow(color: Color.dsAmberGlow, radius: 24)
                .padding(.top, DS.space("xs"))
            Text(verbatim: "CouchSubs").font(.dsH2)
            Text(verbatim: AppIdentity.version).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.dsMuted)
            Group {
                Text("Free and open source under the GNU AGPL-3.0 license.")
                Text("Remote Play connection by chiaki-ng (AGPL-3.0). Thanks to its developers.")
                Text("The Xbox home console picture uses the open source approach of Greenlight (MIT).")
                Text("CouchSubs is not affiliated with Sony Interactive Entertainment. PlayStation and PS5 are trademarks of Sony Interactive Entertainment Inc.")
                Text("CouchSubs is not affiliated with Microsoft. Xbox is a trademark of Microsoft Corporation.")
            }
            .dsMuted()
            .multilineTextAlignment(.center)
            HStack(spacing: DS.space("xs")) {
                Link(destination: AppIdentity.sourceURL) { Text("Source") }.buttonStyle(.dsSecondary)
                Link(destination: URL(string: "https://github.com/chiaki-ng/chiaki-ng")!) { Text(verbatim: "chiaki-ng") }.buttonStyle(.dsSecondary)
                if let checkForUpdates {
                    Button("Check for Updates…") { checkForUpdates() }.buttonStyle(.dsSecondary)
                }
            }
            .padding(.top, DS.space("xs"))
            VStack(spacing: DS.space("xs")) {
                Image("Enmera").resizable().aspectRatio(contentMode: .fit).frame(height: 16).opacity(0.85)
                    .accessibilityLabel(Text(verbatim: "Enmera"))
                Text("Copyright © 2026 Enmera").font(.system(size: 11)).foregroundStyle(Color.dsFaint)
            }
            .padding(.top, DS.space("xs"))
            Button("Close") { dismiss() }
                .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, DS.space("xs"))
        }
        .padding(DS.space("l"))
        .frame(width: 460)
        // Perde: üstten düşen durağan projeksiyon ışığı, logonun arkasında amber ışıma.
        .background { DSProjectorLight() }
        .background(Color.dsSurface)
        .newLook()
    }
}

// MARK: Sürüm Notları

/// docs/surum-notlari.md'den (uygulamayla gelir): "Bu sürümde yeni" maddeleri ve bir önceki sürümün özeti.
enum ReleaseNotes {
    static func load() -> (current: [String], previous: [String]) {
        guard let url = Bundle.main.url(forResource: "surum-notlari", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ([], []) }
        return parse(text)
    }

    static func parse(_ text: String) -> (current: [String], previous: [String]) {
        var current: [String] = []
        var previous: [String] = []
        var inCurrent = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("**Bu sürümde yeni**") { inCurrent = true; continue }
            if inCurrent, line.hasPrefix("- ") { current.append(clean(String(line.dropFirst(2)))); continue }
            if inCurrent, line.hasPrefix("**"), previous.isEmpty, let colon = line.range(of: ":**") {
                previous = line[colon.upperBound...].split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
                break
            }
        }
        return (current, previous)
    }

    /// Markdown kalın ve bağlantı işaretleri atılır; cümle büyük harfle başlar ve noktayla biter.
    private static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "**", with: "")
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let first = value.first else { return "" }
        return String(first).uppercased(with: Locale(identifier: "tr")) + value.dropFirst() + "."
    }
}

struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var which = 0
    private let notes = ReleaseNotes.load()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("s")) {
            DSCardHeader("Release notes")
            DSTabs(selection: $which, items: [(0, "This Version"), (1, "Previous")])
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DS.space("s")) {
                    ForEach(Array((which == 0 ? notes.current : notes.previous).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: DS.space("s")) {
                            Circle().fill(Color.dsAmber).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                            Text(verbatim: line).font(.system(size: 14)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: 360)
            Button("OK") { dismiss() }
                .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(DS.space("l"))
        .frame(width: 520)
        .background(Color.dsSurface)
        .newLook()
    }
}

// MARK: Menü çubuğu

/// Menü çubuğu penceresi: başlık (konsol · TV ve durum rozeti), Çeviriyi Başlat/Durdur, Tıklamalar Alttaki Pencereye
/// Geçsin (kısayolu sağda), Altyazıları Konumlandır, CouchSubs'ı Aç. Yalnız altyazı bu bilgisayarın ekranındayken.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("s")) {
            HStack(spacing: DS.space("s")) {
                DSLogoMark(height: 18, breathing: false)
                    .frame(width: 40, height: 40)
                    .dsElevation(.raised, in: RoundedRectangle(cornerRadius: DS.radius("control"), style: .continuous))
                VStack(alignment: .leading, spacing: DS.space("xxs")) {
                    Text(verbatim: "CouchSubs").font(.dsBodyStrong)
                    Text(verbatim: subtitle).font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1)
                }
                Spacer(minLength: DS.space("xs"))
                DSStatusChip(model.isRunning ? "Translation On" : "Ready", tone: model.isRunning ? .live : .muted)
            }
            Group {
                if model.isRunning {
                    Button("Stop Translating") { model.stop() }.buttonStyle(DSButtonStyle(kind: .stop, fullWidth: true))
                } else {
                    Button("Start Translating") { Task { await model.start() } }
                        .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
                        .disabled(model.isStarting || !model.canStart)
                }
            }
            DSDivider()
            HStack(spacing: DS.space("m")) {
                DSSwitch(isOn: Binding(get: { model.settings.overlayClickThrough }, set: { model.settings.overlayClickThrough = $0 }))
                    .accessibilityLabel(Text("Clicks Pass to the Window Below"))
                DSTitleBlock(title: "Clicks Pass to the Window Below", subtitle: "Subtitles don't block clicks.",
                             titleFont: .system(size: 14, weight: .medium))
                if let key = HotkeyTable.keys(model.settings.hotkeys, .clickThrough).first {
                    Text(verbatim: key.label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.dsFaint)
                }
            }
            MenuRow(title: "Position the Subtitles") { model.overlayAdjusting = true }
            DSDivider()
            MenuRow(title: "Show CouchSubs", arrow: true) {
                if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        .padding(DS.space("m"))
        .frame(width: 340)
        .background { DSProjectorLight() }
        .background(Color.dsSurface)
        // Menü çubuğu penceresi ana pencereden ayrı: hareket kapısı (çeviri sürüyor mu) buradan kurulur.
        .dsMotionGate()
        .environment(\.dsMotionOff, !model.settings.transitionAnimations)
        .newLook()
    }

    private var subtitle: String {
        let console = model.isXbox ? "Xbox" : model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? model.pictureSourceName
        return [console, model.tv?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private struct MenuRow: View {
        let title: LocalizedStringKey
        var arrow = false
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Spacer()
                    if arrow { Text(verbatim: "→").foregroundStyle(Color.dsFaint) }
                }
                .padding(.horizontal, DS.space("s"))
                .frame(height: DS.size("tab"))
                .background(hovering ? Color.dsField : Color.clear, in: RoundedRectangle(cornerRadius: DS.radius("control")))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

// MARK: Açılır reklam

/// Açılır reklam: yalnız görsel (yazı/düğme yok), görselin oranına göre yatay ya da dikey, tıklanınca bağlantı; köşede ×
/// ve küçük REKLAM. Günde en çok 1; yalnız açılışta ya da çeviri durunca; çeviri sürerken, kurulumda, deneme modunda
/// asla. Üçüncü taraf reklam ağı yok. İçerik design/yeni-arayuz/reklamlar.json › popups (Windows aynı dosyayı okur);
/// görseli yüklenemeyen reklam listeye girmez, liste boşsa açılır reklam hiç açılmaz (yer tutucu ya da logo asla).
struct PopupAd: Identifiable, Equatable {
    let id: String
    let image: NSImage
    let url: URL

    /// Görselin en-boy oranı (genişlik / yükseklik); 1'den büyükse yatay açılır.
    var aspect: CGFloat { image.size.height > 0 ? image.size.width / image.size.height : 1 }

    static func == (lhs: PopupAd, rhs: PopupAd) -> Bool { lhs.id == rhs.id }

    private struct File: Decodable {
        struct Popup: Decodable {
            let id: String
            let image: String
            let link: String
        }

        let popups: [Popup]?
    }

    /// reklamlar.json'daki açılır reklamlar; görseli bulunamayan, açılamayan ya da bağlantısı bozuk olan atlanır.
    static func load(json: Data?, image: (String) -> NSImage?) -> [PopupAd] {
        guard let json, let file = try? JSONDecoder().decode(File.self, from: json) else { return [] }
        return (file.popups ?? []).compactMap { popup in
            guard let url = URL(string: popup.link), url.scheme == "https",
                  let picture = image(popup.image), picture.isValid, picture.size.width > 0, picture.size.height > 0 else { return nil }
            return PopupAd(id: popup.id, image: picture, url: url)
        }
    }

    @MainActor static let catalog: [PopupAd] = load(
        json: Bundle.main.url(forResource: "reklamlar", withExtension: "json").flatMap { try? Data(contentsOf: $0) },
        image: { name in Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "reklam").flatMap(NSImage.init(contentsOf:)) })

    /// O günün reklamı (birden çok varsa gün sırasıyla); liste boşsa nil.
    static func pick(from ads: [PopupAd], date: Date = Date(), calendar: Calendar = .current) -> PopupAd? {
        guard !ads.isEmpty else { return nil }
        return ads[(calendar.ordinality(of: .day, in: .era, for: date) ?? 0) % ads.count]
    }
}

@MainActor
enum PopupAdSchedule {
    private static let key = "popupAdShownDay"

    /// Bugün gösterilmediyse ve koşullar uygunsa gösterilecek reklam.
    static func next(model: AppModel, defaults: UserDefaults = .standard) -> PopupAd? {
        guard model.step == .done, !model.isRunning, !model.demoMode, !model.isStarting,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let ad = PopupAd.pick(from: PopupAd.catalog) else { return nil }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard defaults.double(forKey: key) < today else { return nil }
        defaults.set(today, forKey: key)
        return ad
    }
}

struct PopupAdView: View {
    let ad: PopupAd
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Dikey görsel 340 × 604'e kadar, yatay 560 genişlikte; oran korunur.
        let width: CGFloat = ad.aspect >= 1 ? 560 : min(340, 604 * ad.aspect)
        Button {
            openURL(ad.url)
            close()
        } label: {
            Image(nsImage: ad.image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: width, height: width / ad.aspect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background { Circle().fill(.ultraThinMaterial); Circle().fill(Color.black.opacity(0.45)) }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text("Close"))
            .padding(DS.space("s"))
        }
        .overlay(alignment: .bottomLeading) {
            Text("AD").font(.dsAdTag).tracking(0.9).foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, DS.space("xs")).frame(height: 18).background(Color.black.opacity(0.35), in: Capsule(style: .circular)).padding(DS.space("s"))
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
        .accessibilityLabel(Text("Advertisement"))
    }
}
