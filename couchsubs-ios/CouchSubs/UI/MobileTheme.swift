// SPDX-License-Identifier: AGPL-3.0-only
// Telefonun tasarım katmanı, yeni arayüzün dilinde (design/yeni-arayuz/tasarim.json; Mac ve Windows aynı dosyayı okur).
// Eski adlar (Mobile.*, Tile, StatTile, MobileScreen…) korunur, görünümleri DS bileşenleriyle çizilir: krem/koyu zemin,
// ince çerçeveli kartlar, tam yuvarlak düğme ve giriş kutuları, bej iz + beyaz hap seçici, amber yalnız ana eylemde.
// Açık ve koyu görünüm sistemden gelir. Ekranlar sabit değer kullanmaz.

import SwiftUI
import UIKit

enum Mobile {
    /// Telefonun tek boşluk seti (Mac'le aynı değerler; tasarim-yenileme › boşluk tablosu). Görünümler ham sayı yazmaz,
    /// bu adları kullanır (SpacingTokenTests denetler).
    enum Space {
        /// Ekran kenarı.
        static let screen: CGFloat = 16
        /// Kart iç boşluğu.
        static let tile: CGFloat = 20
        /// Kartlar arası.
        static let cards: CGFloat = 16
        /// Bölümler arası (sayfa başlığı → ilk kart, büyük gruplar).
        static let section: CGFloat = 32
        /// Ayar birimleri arası (açıklama olsa da olmasa da aynı).
        static let unit: CGFloat = 24
        /// İlişkili ardışık düğmeler, soru başlığı → ilk düğme, liste öğeleri, simge → yazı.
        static let gap: CGFloat = 12
        /// Birim içi: başlık → denetim, satır içi öğeler.
        static let inline: CGFloat = 8
        /// Başlık → gövde, denetim → açıklama.
        static let titleToBody: CGFloat = 6
        static let controlToHint: CGFloat = 6
        /// En sıkı aralık (etiket → değer, iki satırlı küçük yazı).
        static let hair: CGFloat = 4
        static let micro: CGFloat = 2
    }

    enum Radius {
        static let tile: CGFloat = DS.radius("card")
        static let control: CGFloat = DS.radius("control")
        static let inner: CGFloat = DS.radius("chip")
        static let tag: CGFloat = 6
        static let pill: CGFloat = 999
    }

    enum Control {
        static let button: CGFloat = DS.size("button")
        static let buttonSmall: CGFloat = 44
        static let icon: CGFloat = 44
        static let field: CGFloat = DS.size("input")
        static let row: CGFloat = 52
        static let tag: CGFloat = DS.size("badge")
    }

    /// Yeni arayüzün renkleri (açık ve koyu görünüm). Eski adlar korunur; ekranlar bunları kullanır.
    enum Palette {
        static let deep = Color.dsBackground
        static let bg = Color.dsBackground
        static let surface = Color.dsSurface
        /// Alan zemini (giriş kutusu, seçici izi, simge zemini).
        static let surface2 = Color.dsField
        /// İnce çizgi: kart ve alan çerçevesi, ayraç.
        static let border = Color.dsBorder
        /// Kapalı anahtar, boş adım, sayfa noktası.
        static let borderStrong = Color.dsSwitchOff
        static let text = Color.dsText
        static let secondary = Color.dsMuted
        static let tertiary = Color.dsFaint
        /// Amber dolgu (ana düğme, anahtar, seçili halka). Yazı rengi olarak `accentText`.
        static let accent = Color.dsAmber
        static let accentHi = Color.dsAmberHover
        static let accentText = Color.dsAmberText
        static let accentSoft = Color.dsAmberSoft
        static let onAccent = Color.dsOnAmber
        /// Paket/hazır çeviri: yeni dilde ayrı mor yok, amber yazı.
        static let pro = Color.dsAmberText
        static let proSoft = Color.dsAmberSoft
        static let success = Color.dsSuccess
        static let successText = Color.dsSuccessText
        static let warning = Color.dsAmberText
        static let danger = Color.dsLiveText
        static let dangerSoft = Color.dsLiveSoft
    }

    /// Yazı ölçeği (tasarim.json › font; telefonda sistem metin stilleriyle, Dinamik Yazı'yla büyür, kökte `accessibility2`
    /// ile sınırlı): sayfa başlığı 28, kart başlığı 17, satır başlığı 15 orta, gövde 15, açıklama 13.
    enum TypeScale {
        static let display = Font.dsH1
        static let title = Font.system(.title3, weight: .semibold).monospacedDigit()
        static let cardTitle = Font.dsCardTitle
        static let headline = Font.dsBodyStrong
        static let body = Font.dsBody
        static let caption = Font.dsSmall
        /// Altyazı içeriği: dikeyde canlı satır 28, yatay altyazı ekranında 36; kullanıcı %80–%160 ölçekler.
        static func subtitle(landscape: Bool, scale: Double) -> Font {
            .system(size: (landscape ? 36 : 28) * min(1.6, max(0.8, scale)), weight: .semibold)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Düğmeler

/// Yeni dilde düğmeler (DSButtonStyle): ana amber, ikincil yüzey + ince halka, hayalet amber yazı, tehlikeli/durdur kırmızı
/// tonlu; hepsi tam yuvarlak ve en az 48. `compact`: bir satırdaki küçük ikincil düğmeler (simge üstte, yazı altta).
struct MobileButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }
    var kind: Kind = .primary
    var compact = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if compact {
            CompactButtonBody(configuration: configuration, kind: kind)
        } else {
            DSButtonStyle(kind: dsKind).makeBody(configuration: configuration)
        }
    }

    private var dsKind: DSButtonStyle.Kind {
        switch kind {
        case .primary: .primary
        case .secondary: .secondary
        case .ghost: .ghost
        case .destructive: .danger
        }
    }
}

/// Küçük düğme: simge üstte, en çok iki satır ortalı yazı altta; 16 köşe, yüzey zemin, ince halka.
private struct CompactButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: MobileButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .labelStyle(StackedLabelStyle())
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(kind == .destructive ? Color.dsLiveText : kind == .primary ? Color.dsOnAmber : Color.dsText)
            .padding(.horizontal, Mobile.Space.inline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(kind == .primary ? Color.dsAmber : pressed ? Color.dsField : Color.dsSurface, in: shape)
            .overlay(shape.strokeBorder(kind == .destructive ? Color.dsLiveRing : Color.dsBorder))
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(shape)
            .animation(DS.animation(.short, reduced: reduceMotion), value: pressed)
    }
}

private struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: Mobile.Space.hair) {
            configuration.icon
            configuration.title
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Mobile.Space.inline)
    }
}

extension ButtonStyle where Self == MobileButtonStyle {
    static var mobilePrimary: MobileButtonStyle { MobileButtonStyle(kind: .primary) }
    static var mobileSecondary: MobileButtonStyle { MobileButtonStyle(kind: .secondary) }
    static var mobileGhost: MobileButtonStyle { MobileButtonStyle(kind: .ghost) }
    static var mobileDestructive: MobileButtonStyle { MobileButtonStyle(kind: .destructive) }
}

/// 44×44 yuvarlak simge düğmesi (ayarlar, kapat, geri): yüzey zemin, ince halka.
struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color = Mobile.Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
                .dsGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DSFocusPlainStyle(cornerRadius: Mobile.Control.icon / 2))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Kartlar

/// Kartın vurgusu: seçili (amber halka + hafif amber dolgu), uyarı (amber ince çerçeve + %6 ton), tehlike/deneysel
/// (kırmızı ince çerçeve + %5 ton). Sol renk şeridi kullanılmaz; çerçeve kartı köşe yarıçapıyla komple sarar.
enum TileEmphasis { case none, selected, warning, danger }

/// Kart: yüzey zemin, 1 pt ince çerçeve, 24 köşe, 20 iç boşluk.
struct Tile<Content: View>: View {
    var emphasis: TileEmphasis = .none
    var spacing: CGFloat = Mobile.Space.inline
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Mobile.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Satır listesi kartı (aralık 0, satırlar ayraçlı ve en az 52): satırın kendi yüksekliği boşluğu verir, üst ve
            // altta yalnız küçük pay kalır.
            .padding(.horizontal, Mobile.Space.tile)
            .padding(.vertical, spacing == 0 ? Mobile.Space.hair : Mobile.Space.tile)
            // Perde e1: yüzey + kıl çizgi + koyu temada üst kenar parlaması; vurguda tonlu zemin ve komple saran halka.
            .background(shape.fill(tint))
            .dsElevation(.card, in: shape)
            .overlay {
                if emphasis != .none {
                    shape.strokeBorder(ring, lineWidth: emphasis == .selected ? 2 : 1.5).allowsHitTesting(false)
                }
            }
            .shadow(color: emphasis == .selected ? Color.dsAmberGlow.opacity(0.6) : .clear, radius: 11)
    }

    private var ring: Color {
        switch emphasis {
        case .none: Mobile.Palette.border
        case .selected, .warning: Color.dsAmber
        case .danger: Color.dsLive
        }
    }

    private var tint: Color {
        switch emphasis {
        case .none: .clear
        case .selected: Color.dsAmber.opacity(0.08)
        case .warning: Color.dsAmber.opacity(0.06)
        case .danger: Color.dsLive.opacity(0.05)
        }
    }
}

/// Bölüm/kart başlığı (cümle düzeni, 17 orta kalın); altındaki içerikle arası kartın kendi aralığına ek 4.
struct SectionTitle: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(Mobile.TypeScale.cardTitle)
            .foregroundStyle(Mobile.Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Mobile.Space.hair)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Ayar birimi: başlık üstte (15 orta), 8 altında denetim, 6 altında isteğe bağlı açıklama (anahtar ve kaydırıcı hariç:
/// onlar kendi satırında). Birimler `SettingUnits` içinde 24 arayla dizilir; açıklama olsa da olmasa da değişmez.
struct SettingUnit<Control: View>: View {
    let title: LocalizedStringKey
    var hint: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Mobile.Space.inline)
            control
            if let hint { Text(hint).dsMuted().padding(.top, Mobile.Space.controlToHint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ayar birimlerini 24 arayla dizer.
struct SettingUnits<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.unit) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// İlişkili ardışık düğmeler (ör. "Evet, Görüyorum" / "Görmüyorum"): aralarında 12, tam genişlik.
struct ButtonStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Mobile.Space.gap) { content }
            .frame(maxWidth: .infinity)
    }
}

/// Önemli uyarı/bilgi kutusu (MobileNote ile aynı bileşen).
typealias InfoBox = MobileNote

/// Değer kartı: üstte etiket satırı (simge + etiket [+ durum noktası] [+ `›`]), altında değer. Dokununca bir sayfa açan
/// kartta `chevron` sağ üstte `›` gösterir (tıklanabilir olduğu belli olsun). Uzun değer küçültülmez, iki satıra iner.
struct StatTile: View {
    let symbol: String
    var tint: MobileTileIcon.Tint = .neutral
    let label: LocalizedStringKey
    let value: String
    var live = false
    var chevron = false
    /// Değerin altında durum hapı (Perde: "Bağlı", "LG · Hazır"); verilmezse `live` iken yalnız yeşil nokta.
    var status: String?
    var statusOK = true

    var body: some View {
        Tile(spacing: Mobile.Space.gap) {
            HStack(spacing: Mobile.Space.inline) {
                DSIconSquare(symbol: symbol, tone: iconTone, size: 26)
                Text(label).font(Font.dsLabel).foregroundStyle(Mobile.Palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if live && status == nil { MobileLiveDot(pulses: false) }
                if chevron { RowChevron() }
            }
            Text(verbatim: value).font(Mobile.TypeScale.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let status {
                DSStatusChip(LocalizedStringKey(status), tone: statusOK ? .ok : .muted)
            }
        }
    }

    private var iconTone: DSIconSquare.Tone {
        switch tint {
        case .neutral: .gray
        case .ok: live ? .teal : .gray
        case .accent, .pro: .amber
        case .danger: .peach
        }
    }
}

/// Gidilecek bir sayfası olan satırın ve kartın `›` işareti.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Mobile.Palette.tertiary)
            .accessibilityHidden(true)
    }
}

/// Bilgi kartının satırı: solda ad (gövde, ikincil), sağda değer (orta kalın) ve `›`. En az 52 yükseklik.
struct MobileInfoRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            Text(title).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
            Spacer(minLength: Mobile.Space.gap)
            Text(verbatim: value)
                .font(Mobile.TypeScale.headline)
                .monospacedDigit()
                .foregroundStyle(Mobile.Palette.text)
                .lineLimit(1)
            RowChevron()
        }
        .frame(minHeight: Mobile.Control.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Bilgi kartı: üstte simge + başlık, altında açıklama. Bir sayfa açan kartta `chevron` (›), seçenek olan kartta `option`
/// (sağda seçim yuvarlağı); düz bilgi kartında ikisi de yok, tıklanabilir gibi görünmez.
struct InfoTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    var emphasis: TileEmphasis = .none
    var chevron = false
    var option = false

    var body: some View {
        Tile(emphasis: emphasis) {
            HStack(spacing: Mobile.Space.inline) {
                MobileTileIcon(symbol: symbol, tint: chevron || option ? .accent : .neutral)
                Text(title).font(Mobile.TypeScale.cardTitle).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if chevron { RowChevron() }
                if option { DSRadio(on: emphasis == .selected) }
            }
            Text(caption).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Karttaki simge: kutusuz, ikincil renkte; paket ve öneri amber, hata kırmızı.
struct MobileTileIcon: View {
    enum Tint { case neutral, ok, accent, pro, danger }
    let symbol: String
    var tint: Tint = .neutral

    var body: some View {
        Image(systemName: symbol)
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch tint {
        case .neutral, .ok: Mobile.Palette.secondary
        case .accent, .pro: Mobile.Palette.accentText
        case .danger: Mobile.Palette.danger
        }
    }
}

/// Oyun kısaltması rozeti ("GTA").
struct GameMonogram: View {
    let code: String
    var size: CGFloat = 44

    var body: some View {
        Text(verbatim: code)
            .font(Mobile.TypeScale.caption.weight(.semibold))
            .foregroundStyle(Mobile.Palette.text)
            .frame(width: size, height: size)
            .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: DS.radius("control"), style: .continuous))
    }
}

/// Etiket ya da durum. Etiket: 24 yükseklik, tam yuvarlak rozet (paket için amber). Durum (`dot`/`live`): yüzey zeminli
/// hap içinde 8 pt nokta ve kelime; `live` ise nokta atar (yalnız canlı çeviride).
struct MobilePill: View {
    enum Kind { case neutral, ok, accent, pro }
    let text: String
    var kind: Kind = .neutral
    var dot = false
    var live = false
    var compact = false

    var body: some View {
        if dot || live {
            HStack(spacing: Mobile.Space.inline) {
                MobileLiveDot(pulses: live)
                Text(verbatim: text).font(Mobile.TypeScale.caption).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(Mobile.Palette.text)
            .padding(.horizontal, Mobile.Space.gap)
            .frame(minHeight: 32)
            .background(Mobile.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Mobile.Palette.border))
        } else {
            DSBadge(text: text, tone: kind == .pro || kind == .accent ? .amber : kind == .ok ? .ok : .unknown)
        }
    }
}

/// Durum noktası: 8 pt yeşil. `pulses` ise 2 sn'de bir genişleyip sönen halka (azaltılmış harekette sabit).
struct MobileLiveDot: View {
    var color: Color = Mobile.Palette.success
    var pulses = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }

    var body: some View {
        // Perde canlı nabzı (Core Animation; hareket kapısı kapalıyken sabit nokta).
        if pulses && !reduceMotion {
            DSPulseDot(color: color, size: 8)
        } else {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
        }
    }
}

/// İlerleme noktaları (karşılama, tur): etkin nokta amber ve uzun.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Mobile.Palette.accent : Mobile.Palette.borderStrong)
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

/// Tek seçimli seçici: her yerde aynı bileşen (DSTabs: bej iz, beyaz yükseltilmiş hap).
struct SegmentedTabs<Value: Hashable>: View {
    let options: [(key: Value, value: LocalizedStringKey)]
    @Binding var selection: Value

    init(options: KeyValuePairs<Value, LocalizedStringKey>, selection: Binding<Value>) {
        self.options = options.map { ($0.key, $0.value) }
        _selection = selection
    }

    /// Seçenekleri çalışırken gelen listeden (ör. ai-models.json'daki modeller) kurar.
    init(options: [(key: Value, value: LocalizedStringKey)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    var body: some View {
        DSTabs(selection: $selection, items: options.map { ($0.key, $0.value) })
    }
}

/// Giriş kutusu: tam yuvarlak, 48, alan zemini; odakta amber halka.
struct MobileFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        DSFieldChrome { configuration }
    }
}

/// Kartın içindeki 52'lik liste satırı.
struct ListRow<Trailing: View>: View {
    let symbol: String
    var tint: MobileTileIcon.Tint = .neutral
    let title: LocalizedStringKey
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Mobile.Space.gap) {
            MobileTileIcon(symbol: symbol, tint: tint)
            Text(title).font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Mobile.Space.inline)
            if let detail {
                Text(verbatim: detail).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary).lineLimit(1)
            }
            trailing
        }
        .frame(minHeight: Mobile.Control.row)
        .contentShape(Rectangle())
    }
}

extension ListRow where Trailing == AnyView {
    /// Gidilecek bir sayfası olan satır (sağda ok).
    init(symbol: String, tint: MobileTileIcon.Tint = .neutral, title: LocalizedStringKey, detail: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) {
            AnyView(RowChevron())
        }
    }
}

/// Satırlar arası 1 pt ayraç.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Mobile.Palette.border).frame(height: 1).accessibilityHidden(true) }
}

// MARK: - Ekran iskeleti

/// Ekran zemini: düz krem (koyu görünümde kömür).
struct MobileBackground: View {
    @Environment(\.perdeAmbient) private var ambient

    var body: some View {
        ZStack {
            Mobile.Palette.bg
            // Perde ortam ışığı: üstten sızan amber projeksiyon ışığı + çok yavaş süzülen sıcak lekeler (yalnız boşta).
            if ambient {
                DSAmbientGlow(intensity: 0.8)
                DSProjectorLight()
            }
        }
        .ignoresSafeArea()
    }
}

private struct AdBandKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Sayfanın altında reklam şeridi gösterilsin mi: yalnız uygulama ve ayar sayfalarında (ana ekranın gezinme yığını)
    /// true; kurulum, açılış, çeviri ve oyun görüntüsü ekranlarında false.
    var mobileAdBand: Bool {
        get { self[AdBandKey.self] }
        set { self[AdBandKey.self] = newValue }
    }
}

/// Ekran yapısı: güvenli alan + 8 → üst satır → 12 → içerik (16 aralıkla, kayar) → alt düğme bölgesi → reklam şeridi.
/// İçerik ekranın en üstüne ve en altına kadar kayar; üst satır, alt düğmeler ve reklam şeridi içeriğin üstünde yüzer.
/// Son öğe düğmelerin ve reklamın altında kalmaz: çubukların yüksekliği kaydırmanın iç boşluğuna eklenir.
struct MobileScreen<Header: View, Content: View, Bottom: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom
    @Environment(\.mobileAdBand) private var adBand
    @Environment(\.perdeTabBar) private var tabBar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Mobile.Space.cards) { content }
                .padding(.horizontal, Mobile.Space.screen)
                .padding(.top, Mobile.Space.gap)
                .padding(.bottom, Mobile.Space.screen)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .softScrollEdges()
        .edgeBar(.top) {
            header
                .padding(.horizontal, Mobile.Space.screen)
                .padding(.top, Mobile.Space.inline)
                .padding(.bottom, Mobile.Space.hair)
        }
        .edgeBar(.bottom) {
            VStack(spacing: Mobile.Space.gap) {
                bottom
                if adBand { DSAdBand() }
                // Perde cam sekme çubuğu: reklam şeridinin altında, ekranın en altında.
                if let tabBar { PerdeTabBar(active: tabBar.active, select: tabBar.select) }
            }
            .padding(.horizontal, Mobile.Space.screen)
            .padding(.top, tabBar != nil || adBand ? Mobile.Space.gap : 0)
            .padding(.bottom, tabBar != nil ? Mobile.Space.hair : adBand ? Mobile.Space.inline : Mobile.Space.screen)
            // Ana eylem, reklam şeridi ve sekme çubuğu tek cam bölge: içerik arkasından kayar (iOS sekme çubuğu gibi) ama
            // yoğun malzeme + zemin rengi arkadaki yazıyı okunur gürültü olmaktan çıkarır; düğme hiçbir kartın yazısını yarım
            // bırakacak biçimde içeriğin üstünde yüzmez, cam bölgenin parçasıdır.
            .background { if tabBar != nil || adBand { BottomGlass() } }
        }
        .foregroundStyle(Mobile.Palette.text)
        .background(MobileBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// Kaydırmanın üstünde yüzen kenar çubuğu. iOS 26+: `safeAreaBar` (kaydırma kenarı efektini sistem çizer);
    /// öncesi: `safeAreaInset` ve çubuğun arkasında içe doğru sönen bulanık malzeme (`EdgeFade`).
    @ViewBuilder func edgeBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: edge, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: edge, spacing: 0) { bar().background { EdgeFade(edge: edge) } }
        }
    }

    /// iOS 26+: kenarda içerik sert kesilmez, yumuşakça bulanıp söner.
    @ViewBuilder func softScrollEdges() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

/// Alt cam bölge (ana eylem + reklam şeridi + sekme çubuğu): ekranın altına kadar, üst kenarda kıl çizgi ve kısa yumuşak
/// geçiş. Malzeme arkadaki içeriği bulandırır; zemin rengi koyu ve açık temada yazıyı bastırır (iOS sekme çubuğu yoğunluğu).
struct BottomGlass: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Mobile.Palette.bg.opacity(0.82)
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.dsBorder).frame(height: 0.5) }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// iOS 26 öncesi kaydırma kenarı: ekranın kenarında (güvenli alan dahil) bulanık malzeme ve zemin rengi, çubuğun içerik
/// tarafına doğru saydamlaşır; düz şerit ve sert çizgi oluşmaz.
private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        let outer: UnitPoint = edge == .top ? .top : .bottom
        let inner: UnitPoint = edge == .top ? .bottom : .top
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Mobile.Palette.bg.opacity(0.7)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                     .init(color: .clear, location: 1)], startPoint: outer, endPoint: inner))
        .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

/// Sayfa başlığı: üstte isteğe bağlı küçük adım etiketi (başlığa yakın), 28 başlık, 4 altında gri açıklama.
struct ScreenTitle: View {
    var caption: LocalizedStringKey?
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
            if let caption {
                Text(caption).font(Font.dsLabel).foregroundStyle(Mobile.Palette.secondary)
                    .padding(.bottom, Mobile.Space.hair)
            }
            Text(title).font(Mobile.TypeScale.display).tracking(-0.4).fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(Mobile.TypeScale.body)
                    .foregroundStyle(Mobile.Palette.secondary)
                    .tracking(DS.mutedTracking)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alt sayfaların üst satırı: yuvarlak geri düğmesi ve sayfa adı.
struct BackHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss
    /// Gezinme yığınının kökünde (sekme sayfası: Geçmiş, Ayarlar) false: geri düğmesi yok, büyük sayfa başlığı.
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        HStack(spacing: Mobile.Space.gap) {
            if isPresented {
                IconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Text(title).font(Font.dsH3).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                PerdeLargeTitle(title: title)
            }
            Spacer()
            trailing
        }
        .frame(minHeight: Mobile.Control.icon)
    }
}

extension BackHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) { self.init(title: title) { EmptyView() } }
}

/// Uyarı ve bilgi kutusu: ince çerçeveli, köşesi yuvarlak; solda simge, yanında metin (ana renkte, okunaklı).
/// Önemli uyarı (varsayılan): amber çerçeve + hafif amber ton + ünlem. `tone: Mobile.Palette.secondary`: nötr bilgi
/// (ince gri çerçeve + bilgi simgesi). `Mobile.Palette.danger`: kırmızı çerçeve + ton.
struct MobileNote: View {
    let text: String
    var tone: Color = Mobile.Palette.warning

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: Mobile.Space.gap) {
            Image(systemName: kind.symbol)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(kind.icon)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Mobile.TypeScale.caption)
                .foregroundStyle(Mobile.Palette.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Mobile.Space.tile - 4)
        .padding(.vertical, Mobile.Space.gap)
        .background(kind.fill, in: shape)
        .overlay(shape.strokeBorder(kind.ring))
        .accessibilityElement(children: .combine)
    }

    private enum Kind {
        case warning, info, danger

        var symbol: String {
            switch self {
            case .warning, .danger: "exclamationmark.triangle.fill"
            case .info: "info.circle"
            }
        }

        var icon: Color {
            switch self {
            case .warning: Color.dsAmberText
            case .info: Mobile.Palette.secondary
            case .danger: Color.dsLiveText
            }
        }

        var ring: Color {
            switch self {
            case .warning: Color.dsAmber
            case .info: Mobile.Palette.border
            case .danger: Color.dsLiveRing
            }
        }

        var fill: Color {
            switch self {
            case .warning: Color.dsAmber.opacity(0.06)
            case .info: Mobile.Palette.surface
            case .danger: Color.dsLive.opacity(0.05)
            }
        }
    }

    private var kind: Kind {
        if tone == Mobile.Palette.secondary || tone == Mobile.Palette.tertiary { return .info }
        if tone == Mobile.Palette.danger { return .danger }
        return .warning
    }
}

extension View {
    /// Mobil ekran zemini.
    func mobileScreen() -> some View { background(MobileBackground()) }
}

extension View {
    /// Alttan açılan sayfanın zemini. `presentationBackground` iOS 16.4'te geldi; öncesinde içerik zemini kenara kadar
    /// boyanır (görünüm aynı).
    @ViewBuilder func sheetBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(color)
        } else {
            background(color.ignoresSafeArea())
        }
    }

    /// Küçük bilgi sayfası içeriği kadar açılır (`.medium`/`.large`'daki boş alan olmaz); üstte tutamaç görünür.
    /// İçerik yüksekliği ölçülür, değişince (ör. bir alan gizlenince) sayfa da uyar.
    func fittedSheet() -> some View { modifier(FittedSheet()) }

    /// Seçim değişince hafif dokunsal geri bildirim. `sensoryFeedback` iOS 17'de geldi; iOS 16'da UIKit'in üreteciyle
    /// (yalnız seçilen düğmede, bir kez).
    @ViewBuilder func selectionFeedback(trigger selected: Bool) -> some View {
        if #available(iOS 17, *) {
            sensoryFeedback(.selection, trigger: selected)
        } else {
            onChange(of: selected) { now in
                if now { UISelectionFeedbackGenerator().selectionChanged() }
            }
        }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Özel yükseklik alttaki güvenli alanı içermez; ölçülen içerik yüksekliği doğrudan kullanılır.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(SheetHeightKey.self) { value in
                if value > 0 { height = value.rounded(.up) }
            }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - Bento ızgara

private struct BentoWideKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Kart iki sütunu kaplar (geniş/kahraman kart).
    func bentoWide() -> some View { layoutValue(key: BentoWideKey.self, value: true) }
}

/// İki sütunlu bento ızgara: aralık 12; `bentoWide()` kartlar tam satır. Bir satırdaki kartların yüksekliği eşittir.
struct BentoGrid: Layout {
    var spacing: CGFloat = Mobile.Space.gap

    private func rows(_ subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        for index in subviews.indices {
            if subviews[index][BentoWideKey.self] {
                if !current.isEmpty { rows.append(current); current = [] }
                rows.append([index])
            } else {
                current.append(index)
                if current.count == 2 { rows.append(current); current = [] }
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func heights(_ rows: [[Int]], width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let column = (width - spacing) / 2
        return rows.map { row in
            let cellWidth = row.count == 1 && subviews[row[0]][BentoWideKey.self] ? width : column
            return row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 350
        let rowHeights = heights(rows(subviews), width: width, subviews: subviews)
        let total = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let allRows = rows(subviews)
        let rowHeights = heights(allRows, width: bounds.width, subviews: subviews)
        let column = (bounds.width - spacing) / 2
        var y = bounds.minY
        for (row, height) in zip(allRows, rowHeights) {
            for (position, index) in row.enumerated() {
                let wide = subviews[index][BentoWideKey.self]
                let width = wide ? bounds.width : column
                let x = bounds.minX + (wide ? 0 : CGFloat(position) * (column + spacing))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }
}
