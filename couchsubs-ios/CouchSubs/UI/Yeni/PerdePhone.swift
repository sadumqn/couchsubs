// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI
import UIKit

// Perde tasarım dili, iPhone'a özgü parçalar (tuval DL-iPhone-* panoları): üç sekmeli cam sekme çubuğu (Ana Ekran ·
// Geçmiş · Ayarlar; Mac'teki üst sekmelerle aynı yapı), dokunsal geri bildirimler (seçim, başarı, hata), ortam ışığı
// anahtarı, başarı anı katmanı, hesap kartları ve paket kapağı yığını. Ortak bileşenler Perde.swift'te (Mac ile aynı).

// MARK: Sekmeler

/// Uygulamanın üç ana sekmesi (Mac'teki üst sekmelerle aynı sıra ve ad).
enum PhoneTab: Hashable, CaseIterable {
    case home, history, settings

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .settings: "slider.horizontal.3"
        }
    }
}

extension Route {
    /// Bu sayfa hangi sekmenin altında sayılır (sekme çubuğunda vurgulanır); nil: açıldığı sekmede kalır.
    var tab: PhoneTab? {
        switch self {
        case .history: .history
        case .settings, .profile, .settingsPage, .about: .settings
        default: nil
        }
    }
}

/// Yüzen cam sekme çubuğu: seçili sekmede amber yumuşak hap (sekmeler arasında kayar), amber simge ve yazı. Sekme
/// değişince seçim titreşimi. Hareket azaltılmışken hap kaymaz, yalnız solar.
struct PerdeTabBar: View {
    let active: PhoneTab
    let select: (PhoneTab) -> Void
    @Namespace private var pill
    @Environment(\.dsMotionGate) private var gate

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases, id: \.self) { tab in
                let on = tab == active
                Button {
                    if !on { Haptics.selection() }
                    select(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: on ? tab.icon + (tab == .home ? ".fill" : "") : tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Color.dsAmberText : Color.dsMuted)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if on {
                            Capsule(style: .circular)
                                .fill(Color.dsAmberSoft)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .modifier(TabTourAnchor(tab: tab))
            }
        }
        .padding(6)
        .dsGlass(in: Capsule(style: .circular))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .animation(gate.reduced ? DS.animation(.short, gate: gate) : DS.spring(reduced: false), value: active)
        // Sekme yazıları en büyük Dinamik Yazı boylarında çubuğu taşırmaz.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Sekme çubuğunun durumu; kök görünüm verir, her ekranın alt çubuğu (MobileScreen) reklam şeridinin altında çizer.
struct PerdeTabBarState {
    let active: PhoneTab
    let select: (PhoneTab) -> Void
}

private struct PerdeTabBarKey: EnvironmentKey {
    static let defaultValue: PerdeTabBarState? = nil
}

extension EnvironmentValues {
    /// nil: bu ekranda sekme çubuğu yok (kurulum adımları, açılış, klavye açıkken).
    var perdeTabBar: PerdeTabBarState? {
        get { self[PerdeTabBarKey.self] }
        set { self[PerdeTabBarKey.self] = newValue }
    }
}

/// Kullanım turunun "Profil ve ayarlar" adımı Ayarlar sekmesini gösterir.
private struct TabTourAnchor: ViewModifier {
    let tab: PhoneTab

    func body(content: Content) -> some View {
        if tab == .settings { content.tourTarget(.profile) } else { content }
    }
}

// MARK: Dokunsal geri bildirim

/// Üç dokunsal geri bildirim: seçim (sekme, seçici), başarı (Eşleşti, Paket Kuruldu, Kurulum Tamam), hata.
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: Ortam ışığı

private struct PerdeAmbientKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Ekran zemininde ortam ışığı (projeksiyon ışığı + çok yavaş süzülen sıcak lekeler). Hareket kapısı çeviri sürerken,
    /// uygulama arka plandayken ve hareket azaltılmışken lekeleri durdurur.
    var perdeAmbient: Bool {
        get { self[PerdeAmbientKey.self] }
        set { self[PerdeAmbientKey.self] = newValue }
    }
}

extension View {
    /// Bu ekranın zemininde ortam ışığı olsun (ana ekran, karşılama, kurulum adımları).
    func perdeAmbient(_ on: Bool = true) -> some View { environment(\.perdeAmbient, on) }
}

// MARK: Başarı anı

/// Ekranın üstünde kısa başarı anı (≤ 1 sn ışın + yaylı tik + başarı titreşimi; hareket azaltılmışken yalnız tik): cam
/// kartta DSSuccessMoment. Çağıran gösterir ve süre dolunca kaldırır.
struct PerdeSuccessOverlay: View {
    let title: LocalizedStringKey
    var message: String?

    var body: some View {
        ZStack {
            Color.dsScrim.opacity(0.5).ignoresSafeArea()
            VStack(spacing: DS.space("s")) {
                DSCelebration(size: 72)
                Text(title).font(.dsH3).foregroundStyle(Color.dsText).multilineTextAlignment(.center)
                if let message {
                    Text(verbatim: message).dsMutedSmall().multilineTextAlignment(.center)
                }
            }
            .padding(DS.space("l"))
            .frame(maxWidth: 300)
            .dsGlass(in: RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .transition(.opacity)
    }
}

// MARK: Hesap kartı (Ayarlar'ın en üstü)

/// Ayarlar'ın en üstündeki hesap kartı (bento): girişliyse yükseltilmiş kart, amber halkalı rozet ve yeşil durum hapı;
/// değilse düz kart, nötr durum ve amber "+ eylem" satırı. Dokununca hesabın sayfası açılır.
struct PerdeAccountTile: View {
    let badge: String
    let symbol: String
    let title: String
    var detail: String?
    let on: Bool
    let status: LocalizedStringKey
    var call: LocalizedStringKey?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        VStack(alignment: .leading, spacing: DS.space("s")) {
            // Dar ekranda (SE) durum hapı rozetin yanına sığmazsa altına iner; kart hiçbir boyda taşmaz.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.space("xs")) {
                    avatar
                    Spacer(minLength: 0)
                    chip
                }
                VStack(alignment: .leading, spacing: DS.space("xs")) {
                    avatar
                    chip
                }
            }
            VStack(alignment: .leading, spacing: DS.space("line")) {
                Text(verbatim: title).font(.dsBodyStrong).foregroundStyle(Color.dsText).lineLimit(1).minimumScaleFactor(0.8)
                if let detail {
                    Text(verbatim: detail).font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1).truncationMode(.middle)
                }
                if let call {
                    Label(call, systemImage: "plus").font(.dsCaption.weight(.semibold)).foregroundStyle(Color.dsAmberText).lineLimit(1)
                }
            }
        }
        .padding(DS.space("m"))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dsElevation(on ? .raised : .card, in: shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var chip: some View {
        DSStatusChip(status, tone: on ? .ok : .muted, dot: !on, icon: on ? "checkmark" : nil)
    }

    @ViewBuilder private var avatar: some View {
        if on {
            Text(verbatim: badge)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.dsOnAmber)
                .frame(width: 36, height: 36)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.796, blue: 0.388), .dsPeach],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().inset(by: -4).strokeBorder(Color.dsAmber, lineWidth: 1.5))
                .padding(4)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsMuted)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.dsField))
                .padding(4)
                .accessibilityHidden(true)
        }
    }
}

/// Ayarlar'ın en üstündeki iki hesap kartı: ikinci hesap (PSN ya da Microsoft) ve konsol. Dokununca giriş ya da eşleme
/// sayfası açılır (eski Profil'deki karolarla aynı yerler).
struct PerdeAccountCards: View {
    @EnvironmentObject private var model: PhoneModel
    @Binding var path: [Route]

    var body: some View {
        HStack(alignment: .top, spacing: DS.space("s")) {
            Button { path.append(model.isXbox ? .ps5 : .psn) } label: {
                if model.isXbox {
                    PerdeAccountTile(badge: "XB", symbol: "person.crop.circle", title: "Microsoft", detail: "Xbox (Beta)",
                                     on: model.xboxSignedIn, status: model.xboxSignedIn ? "Signed in" : "Not signed in",
                                     call: model.xboxSignedIn ? nil : "Sign In")
                } else {
                    PerdeAccountTile(badge: "PS", symbol: "person.crop.circle", title: String(localized: "PSN account"),
                                     detail: model.console.map { $0.name.isEmpty ? "PS5" : $0.name },
                                     on: model.accountId != nil, status: model.accountId != nil ? "Signed in" : "Not signed in",
                                     call: model.accountId != nil ? nil : "Sign In")
                }
            }
            Button { path.append(.ps5) } label: {
                let paired = model.isXbox ? model.xboxConsole != nil : model.console != nil
                let name = (model.isXbox ? model.xboxConsole?.name : model.console?.name).flatMap { $0.isEmpty ? nil : $0 }
                PerdeAccountTile(badge: model.isXbox ? "XB" : "PS5", symbol: "gamecontroller",
                                 title: name ?? (model.isXbox ? "Xbox" : "PS5"),
                                 detail: model.isXbox ? model.xboxConsole?.model : model.console?.host,
                                 on: paired, status: paired ? "Paired" : "Not set up",
                                 call: paired ? nil : model.isXbox ? "Choose your Xbox" : "Pair the PS5")
            }
        }
        .buttonStyle(DSFocusPlainStyle())
    }
}

// MARK: Kapak yığını

/// Paket satırındaki üç eğik küçük kapak (oyun enerjisi kapaklarda, krom nötr).
struct PerdeCoverStack: View {
    let titles: [String]

    var body: some View {
        // Üç kapak birbirinden farklı renkte olsun: aynı palete düşen ad, farklı palet bulunana dek uzatılır.
        var used = [DSCoverArt.palettes.count - 1]  // gri palet yığında kullanılmaz
        let shown: [String] = titles.prefix(3).map { title in
            var seed = title
            for _ in 0..<12 where used.contains(Self.paletteIndex(seed)) { seed += " " }
            used.append(Self.paletteIndex(seed))
            return seed
        }
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, title in
                DSCoverArt(seed: title)
                    .frame(width: 28, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.dsSurface, lineWidth: 1.5))
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * 12)
                    .zIndex(Double(index))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
        }
        .frame(width: 60, height: 44)
        .accessibilityHidden(true)
    }

    /// DSCoverArt.palette ile aynı kararlı karma.
    static func paletteIndex(_ seed: String) -> Int {
        Int(seed.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % UInt32(DSCoverArt.palettes.count))
    }
}

// MARK: Bölüm başlığı

/// Sekme kökündeki büyük sayfa başlığı (Ayarlar, Geçmiş): 28 yarı kalın, sola yaslı.
struct PerdeLargeTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.dsH1)
            .tracking(-0.4)
            .foregroundStyle(Color.dsText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
