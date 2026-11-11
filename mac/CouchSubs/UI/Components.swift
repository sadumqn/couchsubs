// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

// Ortak bileşenler. Ölçü ve renkler Theme'den (design/tokens.json) gelir; ekranlar sabit değer kullanmaz.
// Bileşenlerin tarifi docs/TASARIM.md'de; Windows sürümü aynı bileşenleri aynı adlarla kurar.

/// Uygulamanın logosu (kanepe + altyazı).
struct LogoView: View {
    var size: CGFloat = 40

    var body: some View {
        // Simge dosyası macOS ızgarasına göre kenar boşluğu içerir (1024'te 824'lük kare); uygulama içinde kırpılır.
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
            .clipped()
            // Koyu temada logonun kenarı zeminden ayrılsın.
            .overlay(RoundedRectangle(cornerRadius: size * 186 / 824, style: .continuous).strokeBorder(Color.csBorder))
            .accessibilityHidden(true)
    }
}

/// Düğme türleri: birincil (sarı, parıltılı), ikincil (yüzey-2, çerçeveli), tehlikeli (kırmızı tonlu), hayalet (yalnız yazı).
struct CSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, ghost }
    var kind: Kind = .secondary
    var fullWidth = false
    /// "buttonHeight" (44), "buttonLarge" (52) ya da ana ekrandaki büyük düğme için "primaryActionHeight".
    var height = "buttonHeight"
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous)
        let pressed = configuration.isPressed
        return configuration.label
            .font(.csButton)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .ghost ? Theme.space("s") : Theme.space("tile"))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Theme.size(height))
            .background(background, in: shape)
            .overlay { border(shape) }
            .compositingGroup()
            .glow("primary", enabled: kind == .primary && isEnabled && !pressed)
            .glow("primaryDrop", enabled: kind == .primary && isEnabled && !pressed)
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    @ViewBuilder private func border(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .secondary: shape.strokeBorder(Color.csBorder)
        case .danger: shape.strokeBorder(Color.csDangerBorder)
        case .primary, .ghost: EmptyView()
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .csOnAccent
        case .secondary: .csText
        case .danger: .csDanger
        case .ghost: .csAccentText
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(LinearGradient(colors: [.csAccentHi, .csAccent], startPoint: .top, endPoint: .bottom))
        case .secondary: AnyShapeStyle(Color.csSurface2)
        case .danger: AnyShapeStyle(Color.csDangerSoft)
        case .ghost: AnyShapeStyle(Color.clear)
        }
    }
}

extension ButtonStyle where Self == CSButtonStyle {
    static var primary: CSButtonStyle { CSButtonStyle(kind: .primary) }
    static var secondary: CSButtonStyle { CSButtonStyle(kind: .secondary) }
    static var danger: CSButtonStyle { CSButtonStyle(kind: .danger) }
    static var ghost: CSButtonStyle { CSButtonStyle(kind: .ghost) }
}

/// Karolarla aynı dilde metin alanı: yüzey-2 zemin, ince çerçeve, yuvarlak köşe.
struct CSTextFieldStyle: TextFieldStyle {
    var font: Font = .csBody
    var height: CGFloat = 44

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous)
        return configuration
            .textFieldStyle(.plain)
            .font(font)
            .padding(.horizontal, Theme.space("l"))
            .frame(minHeight: height)
            .background(Color.csSurface2, in: shape)
            .overlay(shape.strokeBorder(Color.csBorder))
    }
}

/// Karonun görünümü: düz, etkin (sarı çerçeve ve parıltı: canlı altyazı, seçili seçenek) ya da paket (mor→sarı çerçeve).
enum TileStyle {
    case plain, active, pro
}

/// Bento karosu: yüzey, üstten hafif ışık, ince çerçeve, büyük köşe.
struct TileBackground: ViewModifier {
    var style: TileStyle = .plain
    var padding: CGFloat = Theme.space("tile")

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous)
        return content
            .padding(padding)
            .background(fill, in: shape)
            .overlay(shape.fill(Self.sheen).allowsHitTesting(false))
            .overlay(border(shape))
            // Parıltı karonun yalnız dışına düşsün (içindeki yazılara ayrı ayrı gölge düşmesin).
            .compositingGroup()
            .glow("activeTile", enabled: style == .active)
            .glow("pro", enabled: style == .pro)
    }

    /// Üstten aşağı %4 beyaz ışık (koyu temada karoyu zeminden ayırır).
    private static let sheen = LinearGradient(colors: [.white.opacity(0.04), .white.opacity(0)], startPoint: .top, endPoint: .center)

    private var fill: AnyShapeStyle {
        switch style {
        case .pro: AnyShapeStyle(LinearGradient(colors: [.csProSoft, .csSurface], startPoint: .top, endPoint: .bottom))
        case .plain, .active: AnyShapeStyle(Color.csSurface)
        }
    }

    @ViewBuilder private func border(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .plain: shape.strokeBorder(Color.csTileBorder)
        case .active: shape.strokeBorder(Theme.glow("activeBorder").color)
        case .pro: shape.strokeBorder(LinearGradient(colors: [.csPro, .csAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

extension View {
    func tile(_ style: TileStyle = .plain, padding: CGFloat = Theme.space("tile")) -> some View {
        modifier(TileBackground(style: style, padding: padding))
    }
}

/// Başlıklı ya da başlıksız içerik karosu.
struct Card<Content: View>: View {
    var title: LocalizedStringKey?
    var style: TileStyle = .plain
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            if let title {
                Text(title).font(.csHeadline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(style)
    }
}

/// Yumuşak sarı zeminde simge (sihirbaz adımının başı).
struct IconBadge: View {
    let symbol: String

    var body: some View {
        TileIcon(symbol: symbol, tint: .csAccentText, background: .csAccentSoft, size: Theme.size("iconBadge"))
    }
}

/// Karonun köşesindeki küçük simge: renkli simge, aynı rengin yumuşak zemini.
struct TileIcon: View {
    let symbol: String
    var tint: Color = .csText
    var background: Color = .csSurface2
    var size: CGFloat = Theme.size("tileIcon")

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radius("inner"), style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Durum hapı: yuvarlak uçlu, renkli zemin üstünde kısa yazı.
struct Pill: View {
    enum Tone { case accent, pro, success, muted }
    let text: String
    var tone: Tone = .muted
    var live = false

    var body: some View {
        HStack(spacing: Theme.space("inline")) {
            if live { LiveDot() }
            Text(verbatim: text).lineLimit(1)
        }
        .font(.csCaption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.space("m"))
        .frame(height: 28)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .accent: .csAccentText
        case .pro: .csPro
        case .success: .csSuccess
        case .muted: .csSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .accent: .csAccentSoft
        case .pro: .csProSoft
        case .success: .csSuccessSoft
        case .muted: .csSurface2
        }
    }
}

/// Canlı nokta: yeşil nokta ve 1,6 sn'de bir genişleyip sönen halka (azaltılmış harekette halka yok).
struct LiveDot: View {
    var color: Color = .csSuccess
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let size = Theme.size("statusDot")
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if !reduceMotion {
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: size + 12, height: size + 12)
                        .scaleEffect(pulsing ? 1.2 : 0.4)
                        .opacity(pulsing ? 0 : 0.8)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
            }
            .accessibilityHidden(true)
    }
}

/// Sihirbaz adımlarının ortak düzeni: simge, başlık, açıklama, içerik.
struct StepLayout<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("l")) {
            IconBadge(symbol: symbol)
            Text(title)
                .font(.csDisplay)
                .tracking(-0.4)
                .padding(.top, Theme.space("xs"))
            Text(message)
                .font(.csBody)
                .foregroundStyle(Color.csSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            content
                .padding(.top, Theme.space("s"))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Numaralı talimat satırı.
struct NumberedRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space("m")) {
            Text("\(number)")
                .font(.csCallout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.csAccentText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.csAccentSoft))
            Text(text)
                .font(.csBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Durum noktasının rengi: bağlı (yeşil), sorun var (turuncu), boşta (gri).
enum StatusTone: Equatable {
    case idle, warning, good

    var color: Color {
        switch self {
        case .good: .csSuccess
        case .warning: .csWarning
        case .idle: .csSecondary
        }
    }
}

/// Renkli durum noktası, adı ve değeri.
struct StatusRow: View {
    let title: LocalizedStringKey
    let value: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            Circle()
                .fill(tone.color)
                .frame(width: Theme.size("statusDot"), height: Theme.size("statusDot"))
            Text(title).font(.csBody.weight(.semibold))
            Spacer()
            Text(value)
                .font(.csBody)
                .foregroundStyle(tone == .good ? Color.csText : Color.csSecondary)
                .lineLimit(1)
        }
    }
}

/// Bento durum karosu: üstte simge (bağlıysa canlı nokta), altında küçük ad ve değer.
struct StatusTile<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    var tone: StatusTone = .idle
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("s")) {
            HStack {
                TileIcon(symbol: symbol, tint: iconTint, background: iconBackground)
                Spacer()
                if tone == .good { LiveDot() }
                else if tone == .warning { Circle().fill(Color.csWarning).frame(width: Theme.size("statusDot"), height: Theme.size("statusDot")) }
            }
            Text(title).font(.csCaption).foregroundStyle(Color.csSecondary)
            Text(verbatim: value)
                .font(.csHeadline)
                .fixedSize(horizontal: false, vertical: true)
            accessory
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tile()
        .accessibilityElement(children: .combine)
    }

    private var iconTint: Color { tone == .good ? .csSuccess : .csText }
    private var iconBackground: Color { tone == .good ? .csSuccessSoft : .csSurface2 }
}

extension StatusTile where Accessory == EmptyView {
    init(symbol: String, title: LocalizedStringKey, value: String, tone: StatusTone = .idle) {
        self.init(symbol: symbol, title: title, value: value, tone: tone) { EmptyView() }
    }
}

/// Tamamlanan bir adımın onayı.
struct DoneLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.csBody.weight(.semibold))
            .foregroundStyle(Color.csSuccess)
    }
}

/// İkincil açıklama metni.
struct HintText: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.csCallout)
            .foregroundStyle(Color.csSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Bir işlem başarısız olunca gösterilen hata metni.
struct ErrorText: View {
    let error: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.csCallout)
                .foregroundStyle(Color.csWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Pencere zemini: sağ üstte sarı, sol altta mor yumuşak ışık (hareketsiz).
struct BackgroundGlow: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.csBackground
                spot("backgroundAccent", center: UnitPoint(x: 0.88, y: -0.06), in: size)
                spot("backgroundPro", center: UnitPoint(x: -0.12, y: 1.06), in: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func spot(_ name: String, center: UnitPoint, in size: CGSize) -> some View {
        let glow = Theme.glow(name)
        // tokens.json'daki yarıçap CSS biçiminde; Theme.glow yarısını verir.
        return RadialGradient(colors: [glow.color, glow.color.opacity(0)], center: center, startRadius: 0, endRadius: glow.radius * 2 * 0.62)
    }
}

/// Uygulamanın tamamına zemin rengi, yazı rengi ve temel yazı boyutunu verir.
struct AppSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.csBody)
            .foregroundStyle(Color.csText)
            .tint(Color.csAccentText)
            .background(BackgroundGlow())
    }
}

extension View {
    func appSurface() -> some View { modifier(AppSurface()) }
}
