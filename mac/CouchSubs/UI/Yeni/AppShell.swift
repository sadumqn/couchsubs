// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI

/// Ana pencerenin sekmeleri. Ayarlar ve Geçmiş eskiden ayrı sayfa (sheet) idi; menüdeki "Ayarlar" (⌘,) ve
/// `openSettings(_:)` aynı bayraklarla sekmeyi açar.
enum ShellTab: Hashable {
    case home, history, settings
}

/// Yeni arayüzün kabuğu: cam üst çubuk (başlık çubuğu + 72 pt logo, Ana Ekran/Geçmiş/Ayarlar sekmeleri, durum hapı),
/// tam boy içerik ve cam alt çubukta reklam bandı. En küçük pencere 1200 × 760; büyüyünce içerik en fazla 1680
/// genişlikte ortalanır, cam çubuklar pencere boyu.
struct AppShell: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Açılır reklam (günde en çok bir; açılışta ya da çeviri durunca).
    @State private var popupAd: PopupAd?

    private var tab: Binding<ShellTab> {
        Binding(get: { model.showSettings ? .settings : model.showHistory ? .history : .home },
                set: { value in
                    model.showSettings = value == .settings
                    model.showHistory = value == .history
                })
    }

    /// Üst cam çubuk: başlık çubuğu (trafik ışıkları) + 72 pt sekme satırı.
    static var topBar: CGFloat { DSChrome.titlebar + DS.size("header") }
    /// Alt cam çubuk: reklam bandı ve çevresindeki boşluk (reklam yoksa çubuk da yok).
    static var bottomBar: CGFloat { AdCatalog.band.isEmpty ? 0 : DS.size("adBand") + DS.space("xs") + DS.space("m") }

    var body: some View {
        // Sayfa pencerenin tamamını kaplar; üst ve alt çubuk camdır, içerik ikisinin de arkasından kayar (iOS gibi).
        Group {
            switch tab.wrappedValue {
            case .home: HomeView()
            case .history: HistoryPage()
            case .settings: SettingsPage(section: Binding(get: { model.settingsSection }, set: { model.settingsSection = $0 }))
            }
        }
        .transition(.opacity)
        .id(tab.wrappedValue)
        .environment(\.dsChromeInsets, EdgeInsets(top: Self.topBar, leading: 0, bottom: Self.bottomBar, trailing: 0))
        .frame(maxWidth: DS.size("contentMax"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: DSChrome.titlebar)
                ShellHeader(tab: tab).frame(maxWidth: DS.size("contentMax"))
            }
            .frame(maxWidth: .infinity)
            .background(DSGlassBar(edge: .top))
        }
        .overlay(alignment: .bottom) {
            if Self.bottomBar > 0 {
                DSAdBand()
                    .padding(.horizontal, DS.space("l"))
                    .padding(.top, DS.space("xs"))
                    .padding(.bottom, DS.space("m"))
                    .frame(maxWidth: DS.size("contentMax"))
                    .frame(maxWidth: .infinity)
                    .background(DSGlassBar(edge: .bottom))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(DSFullSizeWindow())
        // Ortam ışığı: amber, şeftali ve gök mavisi lekeler çok yavaş süzülür (Core Animation) — yalnız Ana Ekran'da;
        // Geçmiş ve Ayarlar'da aynı lekeler durağan (boşta ≤ %2 işlemci). Çeviri sürerken, hareketi azaltta ve pencere
        // arka plandayken her sayfada durağan.
        .background {
            if tab.wrappedValue == .home {
                DSAmbientGlow(intensity: 0.8)
            } else {
                DSAmbientGlow(intensity: 0.8).environment(\.dsMotionGate, DSMotionGate(reduced: true))
            }
        }
        .background(Color.dsBackground)
        .animation(DS.animation(.page, reduced: reduceMotion || !model.settings.transitionAnimations), value: tab.wrappedValue)
        // Tek hareket kapısı: çeviri sürerken, hareketi azaltta, Geçiş Animasyonları kapalıyken ya da pencere önde
        // değilken sürekli animasyonlar durur.
        .dsMotionGate(translating: model.isRunning)
        .environment(\.dsMotionOff, !model.settings.transitionAnimations)
        .overlay {
            if let popupAd {
                ZStack {
                    Color.dsScrim.ignoresSafeArea().onTapGesture { self.popupAd = nil }
                    PopupAdView(ad: popupAd) { self.popupAd = nil }
                        .shadow(color: .black.opacity(0.28), radius: 32, y: 24)
                }
                .transition(.opacity)
            }
        }
        .animation(DS.animation(.page, reduced: reduceMotion || !model.settings.transitionAnimations), value: popupAd)
        .onAppear { popupAd = PopupAdSchedule.next(model: model) }
        .onChange(of: model.isRunning) { running in
            // Çeviri başlayınca açık reklam kapanır; çeviri durunca (günde bir) gösterilebilir.
            popupAd = running ? nil : PopupAdSchedule.next(model: model)
        }
        .newLook()
        .alert(item: $model.tvPairingRequest) { ticket in
            Alert(title: Text("Pair this TV?"),
                  message: Text(String(format: String(localized: "TV code: %@. You don't type this code anywhere: if your TV shows the same code, approve it here."), ticket.code)),
                  primaryButton: .default(Text("Approve")) { model.resolveTVPairing(ticket, accept: true) },
                  secondaryButton: .cancel(Text("Reject")) { model.resolveTVPairing(ticket, accept: false) })
        }
    }
}

/// Üst çubuk: üç sütun (sol logo, orta sekmeler, sağ durum hapı); yanlarda 24.
private struct ShellHeader: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: ShellTab

    var body: some View {
        HStack(spacing: DS.space("m")) {
            DSBrand().frame(maxWidth: .infinity, alignment: .leading)
            DSTabs(selection: $tab, items: [(.home, "Home"), (.history, "History"), (.settings, "Settings")], fill: false)
                .fixedSize()
            HStack(spacing: DS.space("xs")) {
                let status = ShellStatus(model: model)
                LogCopyButton()
                DSStatusPill(text: status.text, dot: status.dot, pulse: status.live)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, DS.space("l"))
        .frame(height: DS.size("header"))
    }
}

/// Durum hapının yanındaki "Günlüğü Kopyala": hapla aynı yükseklikte ikincil hap; günlükler maskelenip zip'lenir, zip
/// dosyası panoya konur ve altında kısa onay + "Finder'da Göster" açılır. Dar pencerede yalnız simge (ipucu aynı).
private struct LogCopyButton: View {
    @State private var hovering = false
    @State private var working = false
    @State private var result: URL?
    @State private var failed = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(showsTitle: true)
            pill(showsTitle: false)
        }
        .popover(isPresented: Binding(get: { result != nil || failed }, set: { if !$0 { result = nil; failed = false } }),
                 arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.space("s")) {
                if let result {
                    Label("Log copied; you can paste it into GitHub or an email.", systemImage: "checkmark.circle.fill")
                        .font(.dsBody)
                        .foregroundStyle(Color.dsText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                        .buttonStyle(.link)
                        .font(.dsSmall)
                } else {
                    Text("The log couldn't be collected. Try again.").font(.dsBody).foregroundStyle(Color.dsLive)
                }
            }
            .padding(DS.space("m"))
            .frame(width: 300, alignment: .leading)
        }
    }

    private func pill(showsTitle: Bool) -> some View {
        Button(action: copy) {
            HStack(spacing: DS.space("xs")) {
                Image(systemName: working ? "hourglass" : "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                if showsTitle { Text(working ? "Copying…" : "Copy Log").font(.dsSmall).lineLimit(1) }
            }
            .foregroundStyle(Color.dsMuted)
            .padding(.horizontal, showsTitle ? DS.space("m") : 0)
            .frame(width: showsTitle ? nil : DS.size("tab"), height: DS.size("tab"))
            .background(hovering ? Color.dsField : Color.dsSurface, in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(Color.dsBorder))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .disabled(working)
        .onHover { hovering = $0 }
        .help(Text("Copies CouchSubs's logs as a zip file (personal data masked) so you can paste them into a bug report."))
        .accessibilityLabel(Text("Copy Log"))
        .fixedSize()
    }

    private func copy() {
        working = true
        let header = "CouchSubs \(AppIdentity.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        Task.detached(priority: .userInitiated) {
            let file = try? LogArchive.make(header: header)
            await MainActor.run {
                working = false
                if let file {
                    LogArchive.copyToPasteboard(file)
                    result = file
                } else {
                    failed = true
                }
            }
        }
    }
}

/// Durum hapının metni ve rengi (METINLER.md › Pencere kabuğu).
struct ShellStatus {
    let text: LocalizedStringKey
    let dot: Color
    /// Çeviri sorunsuz akıyor: nokta canlı nabız atar (ekrandaki tek sürekli animasyon).
    var live = false

    @MainActor init(model: AppModel) {
        if model.demoMode {
            (text, dot) = ("Demo Mode", .dsAmber)
        } else if model.isRunning {
            switch model.sessionState {
            case .streaming:
                (text, dot) = HomeProblem.current(model) == nil ? ("Translation On", .dsLiveDot) : ("Needs Attention", .dsLive)
                live = HomeProblem.current(model) == nil
            case .connecting:
                (text, dot) = ("Connecting…", .dsAmber)
            case .disconnected:
                (text, dot) = ("Needs Attention", .dsLive)
            }
        } else if model.isStarting {
            (text, dot) = ("Connecting…", .dsAmber)
        } else if !model.canStart {
            (text, dot) = ("Setup Incomplete", .dsFaint)
        } else {
            (text, dot) = ("Ready", .dsFaint)
        }
    }
}
