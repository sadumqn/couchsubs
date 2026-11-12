// SPDX-License-Identifier: AGPL-3.0-only
// Ana ekran, çeviri sürüyor ekranı, yatay altyazı ekranı ve kullanım turu (tuvaldeki Telefon · 7–10).

import CouchSubsCore
import RemotePlay
import SwiftUI
import Translation
import UIKit

/// Ana ekrandan açılan sayfalar.
enum Route: Hashable {
    case settings, profile, packs, target, ps5, psn, about
}

/// Turun vurguladığı öğeler.
enum TourTarget: Int, CaseIterable {
    case start, target, packs, profile
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// Ana ekranın ortak üst satırı: logo, ayarlar, profil.
struct HomeHeader: View {
    @Binding var path: [Route]

    var body: some View {
        HStack(spacing: Mobile.Space.gap) {
            LogoView(size: 36)
            Spacer()
            IconButton(symbol: "gearshape", label: "Settings") { path.append(.settings) }
            AvatarButton(initials: "") { path.append(.profile) }
                .tourTarget(.profile)
        }
        .frame(height: Mobile.Control.icon)
    }
}

// MARK: - 8 Ana ekran

/// Apple çevirisinin dil paketi henüz indirilmedi: "İndir" sistemin indirme penceresini açar.
@available(iOS 26, *)
private struct LanguagePackTile: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        Tile {
            Text("The English–Turkish language pack is not downloaded yet.").font(Mobile.TypeScale.headline)
            Button("Download") {
                download = TranslationSession.Configuration(source: Locale.Language(identifier: model.settings.sourceLanguage),
                                                            target: Locale.Language(identifier: model.settings.targetLanguage))
            }
            .buttonStyle(.mobileSecondary)
        }
        .translationTask(download) { session in
            try? await session.prepareTranslation()
            await model.refreshTranslatorStatus()
        }
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @EnvironmentObject private var app: AppModel
    @Binding var path: [Route]

    var body: some View {
        MobileScreen {
            HomeHeader(path: $path)
        } content: {
            ScreenTitle(title: model.canStart ? "Ready" : "Almost ready",
                        message: model.canStart ? "Open the game on the PS5, then start." : "Finish the setup to start translating.")
            BentoGrid {
                StatTile(symbol: "gamecontroller.fill", tint: .ok, label: "PS5",
                         value: model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? String(localized: "Not set up"), live: model.console != nil)
                Button { path.append(.target) } label: {
                    StatTile(symbol: model.settings.output == .computer ? "iphone" : "tv", tint: .accent, label: "Subtitles",
                             value: targetName, emphasis: .active)
                }
                .buttonStyle(.plain)
                .tourTarget(.target)
                packsTile
                    .bentoWide()
                    .tourTarget(.packs)
                StatTile(symbol: "globe", label: "Translation", value: engineName)
                StatTile(symbol: "clock.arrow.circlepath", label: "Last session", value: lastSession)
            }
            if model.tvAppMissing { MobileNote(text: String(localized: "To install the TV app for the first time, use CouchSubs on a computer once. After that this phone is enough.")) }
            // Dil paketi yalnız Apple çevirisinin kullanılabildiği sistemde (iOS 26 ve sonrası) istenir.
            if model.translatorStatus == .needsDownload, #available(iOS 26, *) {
                LanguagePackTile()
            }
            if model.translatorStatus == .unsupported, !Translator.isAvailable {
                MobileNote(text: String(localized: "Apple's free translation needs iOS 26 or later. Game packs, DeepL and AI translation work on this device."))
            }
        } bottom: {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.start() }
            } label: {
                Label("Start translating", systemImage: "play.fill")
            }
            .buttonStyle(.mobilePrimary)
            .disabled(model.isStarting || !model.canStart)
            .tourTarget(.start)
        }
        .task {
            app.analytics.screen("home")
            await model.refreshTranslatorStatus()
        }
    }

    /// Oyun paketleri karosu (mor: paketlerin rengi); herkese ücretsiz.
    private var packsTile: some View {
        Button { path.append(.packs) } label: {
            Tile(emphasis: .pro) {
                HStack(spacing: Mobile.Space.gap) {
                    MobileTileIcon(symbol: "bolt.fill", tint: .pro)
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        Text("Instant subtitles with ready packs").font(Mobile.TypeScale.headline)
                        Text(model.installedPacks.isEmpty ? String(localized: "GTA V, RDR2, Mafia and 3 more games")
                             : PacksScreen.summary(model.installedPacks))
                            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                    Spacer()
                    MobilePill(text: String(localized: "Free"), kind: .pro)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var targetName: String {
        if model.settings.output == .computer { return String(localized: "This phone") }
        return model.hasTV ? model.tv?.name ?? "TV" : String(localized: "Not set up")
    }

    private var engineName: String {
        model.settings.translationEngine == .free ? String(localized: "Free") : model.settings.translationEngine.displayName
    }

    private var lastSession: String {
        guard let seconds = model.lastSessionSeconds else { return "—" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

// MARK: - 9 Çeviri sürüyor

struct RunningScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Binding var path: [Route]
    @State private var showSubtitles = false

    var body: some View {
        MobileScreen {
            HomeHeader(path: $path)
        } content: {
            HStack(spacing: Mobile.Space.inline) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    MobilePill(text: String(format: String(localized: "Translating · %@"), elapsed(at: context.date)),
                         kind: model.sessionState == .streaming ? .ok : .accent, dot: model.sessionState == .streaming)
                }
                if model.packsActive { MobilePill(text: String(localized: "Ready translation"), kind: .pro) }
            }
            if model.sessionState != .streaming {
                MobileNote(text: model.ps5StatusText, tone: Mobile.Palette.secondary)
            }
            Tile(emphasis: .active) {
                ScanLine()
                Text("Now").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                if let current = model.recentLines.first {
                    Text(verbatim: current.translation)
                        .font(Mobile.TypeScale.subtitle(landscape: false, scale: scale))
                        .shadow(color: Mobile.Palette.accent.opacity(0.35), radius: 9)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    HStack {
                        Text(verbatim: current.source).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        Spacer()
                        if current.fromPack { MobilePill(text: String(localized: "ready translation"), kind: .pro, compact: true) }
                    }
                } else {
                    Text("Subtitles will appear here while you play.").font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.recentLines.first?.id)
            if model.recentLines.count > 1 {
                Tile(spacing: 0) {
                    ForEach(Array(model.recentLines.dropFirst().prefix(8).enumerated()), id: \.element.id) { index, line in
                        if index > 0 { RowDivider() }
                        HStack(alignment: .top, spacing: Mobile.Space.gap) {
                            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                                Text(verbatim: line.translation).font(Mobile.TypeScale.headline)
                                Text(verbatim: line.source).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                            }
                            Spacer()
                            MobilePill(text: line.fromPack ? String(localized: "ready") : engineName, kind: line.fromPack ? .pro : .neutral, compact: true)
                        }
                        .padding(.vertical, Mobile.Space.gap)
                    }
                }
            }
            BentoGrid {
                Tile {
                    Text("From ready translation").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Text(verbatim: "\(model.sessionPackLines) / \(model.sessionLines)").font(Mobile.TypeScale.title)
                }
                Tile {
                    Text(model.settings.output.showsOnTV ? "TV" : "Screen").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Text(verbatim: model.settings.output.showsOnTV ? model.tvStatusText : String(localized: "This phone"))
                        .font(Mobile.TypeScale.title).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Text("Keep CouchSubs open on the screen while you play. iOS stops the connection when the app goes to the background; the screen stays on while translating.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        } bottom: {
            if model.settings.output.showsOnComputer {
                Button { showSubtitles = true } label: { Label("Subtitle screen", systemImage: "rectangle.landscape.rotate") }
                    .buttonStyle(.mobileSecondary)
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.stop()
            } label: {
                Label("Stop translating", systemImage: "stop.fill")
            }
            .buttonStyle(.mobileDestructive)
        }
        .fullScreenCover(isPresented: $showSubtitles) { SubtitleScreen() }
        .onAppear { if model.settings.output == .computer { showSubtitles = true } }
    }

    private var scale: Double { Double(model.settings.style.fontSize) / Double(SubtitleStyle().fontSize) }

    private var engineName: String {
        model.settings.translationEngine == .free ? String(localized: "Free") : model.settings.translationEngine.displayName
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(model.runningSince ?? date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Canlı altyazı karosunun üst kenarında soldan sağa akan ince amber çizgi (azaltılmış harekette yok).
struct ScanLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -0.6

    var body: some View {
        GeometryReader { proxy in
            if !reduceMotion {
                LinearGradient(colors: [.clear, Mobile.Palette.accent, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.6, height: 2)
                    .offset(x: proxy.size.width * (0.2 + offset))
                    .onAppear { withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { offset = 0.6 } }
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - 10 Yatay altyazı ekranı

struct SubtitleScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var savedBrightness: CGFloat?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VStack(spacing: Mobile.Space.inline) {
                ForEach(Array(model.phoneLines.enumerated()), id: \.element.id) { index, line in
                    Text(verbatim: line.text)
                        .font(Mobile.TypeScale.subtitle(landscape: true, scale: scale))
                        .foregroundStyle(textColor)
                        .opacity(line.fading ? 0.4 : index < model.phoneLines.count - 1 ? 0.6 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(.horizontal, Mobile.Space.screen)
            .padding(.bottom, Mobile.Space.screen * 2)
            Text("The screen stays on · brightness is lowered automatically")
                .font(Mobile.TypeScale.caption)
                .foregroundStyle(Mobile.Palette.secondary.opacity(0.6))
                .padding(.bottom, Mobile.Space.inline)
        }
        .overlay(alignment: .topLeading) {
            MobilePill(text: statusText, kind: model.sessionState == .streaming ? .ok : .accent, dot: model.sessionState == .streaming)
                .padding(Mobile.Space.screen)
        }
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", label: "Close") { dismiss() }.padding(Mobile.Space.screen)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            Orientation.request(.landscape)
            dim(true)
        }
        .onDisappear {
            Orientation.request(.portrait)
            dim(false)
        }
    }

    private var statusText: String {
        guard model.sessionState == .streaming else { return model.ps5StatusText }
        return model.packsActive ? String(localized: "PS5 connected · ready translation") : String(localized: "PS5 connected")
    }

    private var scale: Double { Double(model.settings.style.fontSize) / Double(SubtitleStyle().fontSize) }

    private var textColor: Color {
        switch model.settings.style.textColor {
        case .yellow: Mobile.Palette.accent
        case .white: Mobile.Palette.text
        }
    }

    /// Altyazı ekranı açıkken parlaklık kısılır (pil ve göz); kapanınca eski değer döner.
    private func dim(_ on: Bool) {
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return }
        if on {
            savedBrightness = screen.brightness
            screen.brightness = min(screen.brightness, 0.4)
        } else if let savedBrightness {
            screen.brightness = savedBrightness
        }
    }
}

/// Altyazı ekranı açılınca telefon yataya döner.
enum Orientation {
    @MainActor
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

// MARK: - 7 Kullanım turu (ilk açılışta bir kez, 4 adım)

struct CoachTour: View {
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void
    @State private var step = 0

    private let steps: [(title: LocalizedStringKey, text: LocalizedStringKey)] = [
        ("Start translating here", "Tap after you open the game on the PS5. The phone takes the picture, reads the subtitles and translates them."),
        ("Where the subtitles appear", "On the TV over the game, or on this phone. Tap to change it."),
        ("Ready packs", "In popular games the subtitles come from ready translations, without waiting."),
        ("Profile and settings", "Your devices, PSN account and translation settings are here."),
    ]

    var body: some View {
        GeometryReader { proxy in
            let target = TourTarget(rawValue: step) ?? .start
            let rect = anchors[target].map { proxy[$0].insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                // %70 karartma, vurgulanan öğenin çevresinde 16 yarıçaplı delik.
                Color.black.opacity(0.7)
                    .reverseMask {
                        if let rect {
                            RoundedRectangle(cornerRadius: Mobile.Radius.control).frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                if let rect {
                    RoundedRectangle(cornerRadius: Mobile.Radius.control)
                        .strokeBorder(Mobile.Palette.accent, lineWidth: 2)
                        .shadow(color: Mobile.Palette.accentGlow, radius: 14)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                card
                    .padding(.horizontal, Mobile.Space.screen)
                    .frame(maxWidth: .infinity)
                    .position(x: proxy.size.width / 2, y: cardY(rect: rect, height: proxy.size.height))
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func cardY(rect: CGRect?, height: CGFloat) -> CGFloat {
        guard let rect else { return height / 2 }
        // Kart vurgulanan öğenin karşı yarısında durur.
        return rect.midY > height / 2 ? max(140, rect.minY - 120) : min(height - 140, rect.maxY + 120)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.gap) {
            HStack {
                MobilePill(text: "\(step + 1) / \(steps.count)", kind: .accent)
                Spacer()
                Button("Skip", action: onFinish).buttonStyle(.mobileGhost)
            }
            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                Text(steps[step].title).font(Mobile.TypeScale.title)
                Text(steps[step].text).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                PageDots(count: steps.count, current: step)
                Spacer()
                Button(step == steps.count - 1 ? "Done" : "Next") {
                    if step == steps.count - 1 { onFinish() } else { withAnimation { step += 1 } }
                }
                .buttonStyle(MobileButtonStyle(kind: .primary))
                .frame(width: 120)
            }
        }
        .padding(Mobile.Space.tile)
        .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.tile).strokeBorder(Mobile.Palette.border))
    }
}

extension View {
    /// Verilen şekli görünümden oyar (turdaki delik).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup()
        }
    }
}
