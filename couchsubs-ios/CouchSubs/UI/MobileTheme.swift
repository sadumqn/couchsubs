// SPDX-License-Identifier: AGPL-3.0-only
// Mobil tasarım sistemi (bento): TASARIM-MOBIL.md'deki tokenlar ve bileşenler (Android ile ortak belge; onaylı tuval
// "CouchSubs Mobil ve Windows Tasarımı"). Mobilde bu belge design/tokens.json'un üstüne geçer. Ekranlar sabit değer
// kullanmaz; ölçü, renk ve efektler buradan gelir.

import SwiftUI
import UIKit

enum Mobile {
    enum Space {
        static let screen: CGFloat = 20
        static let gap: CGFloat = 12
        static let tile: CGFloat = 16
        static let inline: CGFloat = 8
        static let hair: CGFloat = 4
    }

    enum Radius {
        static let tile: CGFloat = 24
        static let control: CGFloat = 16
        static let inner: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Control {
        static let button: CGFloat = 52
        static let buttonSmall: CGFloat = 44
        static let icon: CGFloat = 44
        static let field: CGFloat = 52
        static let row: CGFloat = 52
        static let iconBadge: CGFloat = 36
    }

    enum Palette {
        static let bg = Color(hex: 0x141518)
        static let surface = Color(hex: 0x1C1E23)
        static let surface2 = Color(hex: 0x25282F)
        static let border = Color.white.opacity(0.07)
        static let borderStrong = Color(hex: 0x30333A)
        static let text = Color(hex: 0xF3EEE4)
        static let secondary = Color(hex: 0xA9A59C)
        static let accent = Color(hex: 0xF5B83D)
        static let accentHi = Color(hex: 0xFFCF6B)
        static let onAccent = Color(hex: 0x17181B)
        static let accentGlow = Color(hex: 0xF5B83D).opacity(0.45)
        static let pro = Color(hex: 0xA78BFA)
        static let proGlow = Color(hex: 0xA78BFA).opacity(0.45)
        static let success = Color(hex: 0x62C990)
        static let warning = Color(hex: 0xF2A55A)
        static let danger = Color(hex: 0xF28B82)
    }

    /// Yalnız bu beş arayüz boyu (altyazı içeriği hariç).
    enum TypeScale {
        static let display = Font.system(size: 32, weight: .bold)
        static let title = Font.system(size: 22, weight: .semibold).monospacedDigit()
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        static let caption = Font.system(size: 13, weight: .medium)
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

// MARK: - Düğmeler (§5)

struct MobileButtonStyle: ButtonStyle {
    enum Kind { case primary, pro, secondary, ghost, destructive, apple }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Mobile.TypeScale.headline)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foreground)
            .frame(maxWidth: kind == .ghost ? nil : .infinity, minHeight: kind == .ghost ? Mobile.Control.buttonSmall : Mobile.Control.button)
            .padding(.horizontal, kind == .ghost ? Mobile.Space.hair : Mobile.Space.screen)
            .background { background }
            .overlay {
                switch kind {
                case .secondary: RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.borderStrong)
                case .destructive: RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.danger.opacity(0.5))
                default: EmptyView()
                }
            }
            .shadow(color: isEnabled ? glow.opacity(pressed ? 0.5 : 1) : .clear, radius: 12)
            .shadow(color: isEnabled ? glow.opacity(pressed ? 0.25 : 0.55) : .clear, radius: 12, y: 8)
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Mobile.Radius.control))
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .pro: Mobile.Palette.onAccent
        case .secondary: Mobile.Palette.text
        case .ghost: Mobile.Palette.accent
        case .destructive: Mobile.Palette.danger
        case .apple: .black
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Mobile.Radius.control)
        switch kind {
        case .primary: shape.fill(LinearGradient(colors: [Mobile.Palette.accentHi, Mobile.Palette.accent], startPoint: .top, endPoint: .bottom))
        case .pro: shape.fill(LinearGradient(colors: [Mobile.Palette.pro, Mobile.Palette.accent], startPoint: .leading, endPoint: .trailing))
        case .secondary: shape.fill(Mobile.Palette.surface2)
        case .ghost: Color.clear
        case .destructive: shape.fill(Mobile.Palette.danger.opacity(0.12))
        case .apple: shape.fill(Color.white)
        }
    }

    private var glow: Color {
        switch kind {
        case .primary: Mobile.Palette.accentGlow
        case .pro: Mobile.Palette.proGlow
        default: .clear
        }
    }
}

extension ButtonStyle where Self == MobileButtonStyle {
    static var mobilePrimary: MobileButtonStyle { MobileButtonStyle(kind: .primary) }
    static var mobilePro: MobileButtonStyle { MobileButtonStyle(kind: .pro) }
    static var mobileSecondary: MobileButtonStyle { MobileButtonStyle(kind: .secondary) }
    static var mobileGhost: MobileButtonStyle { MobileButtonStyle(kind: .ghost) }
    static var mobileDestructive: MobileButtonStyle { MobileButtonStyle(kind: .destructive) }
}

/// 44×44 simge düğmesi (ayarlar, kapat, geri).
struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Mobile.Palette.text)
                .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
                .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Profil düğmesi: baş harfler, Pro'da mor halka.
struct AvatarButton: View {
    let initials: String
    var pro = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if initials.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: 16, weight: .semibold))
                } else {
                    Text(verbatim: initials).font(Mobile.TypeScale.caption.weight(.bold))
                }
            }
            .foregroundStyle(Mobile.Palette.onAccent)
            .frame(width: Mobile.Control.icon, height: Mobile.Control.icon)
            .background(LinearGradient(colors: [Mobile.Palette.accentHi, Mobile.Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
            .overlay(Circle().strokeBorder(pro ? Mobile.Palette.pro.opacity(0.7) : .clear, lineWidth: 2).padding(-2))
            .shadow(color: pro ? Mobile.Palette.proGlow : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
    }
}

// MARK: - Karolar (§6, §7)

/// Karonun vurgusu: etkin (amber) ya da Pro (mor→amber).
enum TileEmphasis { case none, active, pro }

/// Bento karosu: yüzey, üstten hafif beyaz degrade, ince çerçeve; etkin ya da Pro ise parıltı.
struct Tile<Content: View>: View {
    var emphasis: TileEmphasis = .none
    var spacing: CGFloat = Mobile.Space.inline
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Mobile.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Mobile.Space.tile)
            .background {
                switch emphasis {
                case .pro:
                    shape.fill(LinearGradient(colors: [Mobile.Palette.pro.opacity(0.10), Mobile.Palette.surface], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7)))
                default:
                    shape.fill(Mobile.Palette.surface)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))))
                }
            }
            .overlay {
                switch emphasis {
                case .none: shape.strokeBorder(Mobile.Palette.border)
                case .active: shape.strokeBorder(Mobile.Palette.accent.opacity(0.55))
                case .pro: shape.strokeBorder(LinearGradient(colors: [Mobile.Palette.pro, Mobile.Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .shadow(color: emphasis == .active ? Mobile.Palette.accent.opacity(0.35) : emphasis == .pro ? Mobile.Palette.proGlow : .clear, radius: 14)
    }
}

/// Kare karo: üstte simge, altta etiket + büyük değer (ana ekran, cihazlar).
struct StatTile: View {
    let symbol: String
    var tint: MobileTileIcon.Tint = .neutral
    let label: LocalizedStringKey
    let value: String
    var emphasis: TileEmphasis = .none
    var live = false

    var body: some View {
        Tile(emphasis: emphasis) {
            VStack(alignment: .leading, spacing: Mobile.Space.inline) {
                HStack {
                    MobileTileIcon(symbol: symbol, tint: tint)
                    Spacer()
                    if live { MobileLiveDot() }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                    Text(label).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Text(verbatim: value).font(Mobile.TypeScale.title).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 36'lık simge rozeti.
struct MobileTileIcon: View {
    enum Tint { case neutral, ok, accent, pro, danger }
    let symbol: String
    var tint: Tint = .neutral

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: Mobile.Control.iconBadge, height: Mobile.Control.iconBadge)
            .background(background, in: RoundedRectangle(cornerRadius: Mobile.Radius.inner))
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch tint {
        case .neutral: Mobile.Palette.text
        case .ok: Mobile.Palette.success
        case .accent: Mobile.Palette.accent
        case .pro: Mobile.Palette.pro
        case .danger: Mobile.Palette.danger
        }
    }

    private var background: Color {
        switch tint {
        case .neutral: Mobile.Palette.surface2
        case .ok: Mobile.Palette.success.opacity(0.14)
        case .accent: Mobile.Palette.accent.opacity(0.14)
        case .pro: Mobile.Palette.pro.opacity(0.16)
        case .danger: Mobile.Palette.danger.opacity(0.14)
        }
    }
}

/// Oyun kısaltması rozeti ("GTA").
struct GameMonogram: View {
    let code: String
    var size: CGFloat = 44

    var body: some View {
        Text(verbatim: code)
            .font(Mobile.TypeScale.caption.weight(.bold))
            .foregroundStyle(Mobile.Palette.pro)
            .frame(width: size, height: size)
            .background(Mobile.Palette.pro.opacity(0.16), in: RoundedRectangle(cornerRadius: Mobile.Radius.inner))
    }
}

/// Durum hapı.
struct MobilePill: View {
    enum Kind { case neutral, ok, accent, pro }
    let text: String
    var kind: Kind = .neutral
    var dot = false
    var compact = false

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            if dot { MobileLiveDot() }
            Text(verbatim: text).font(Mobile.TypeScale.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Mobile.Space.gap)
        .frame(height: compact ? 24 : 28)
        .background(background, in: Capsule())
    }

    private var color: Color {
        switch kind {
        case .neutral: Mobile.Palette.secondary
        case .ok: Mobile.Palette.success
        case .accent: Mobile.Palette.accent
        case .pro: Mobile.Palette.pro
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: Mobile.Palette.surface2
        case .ok: Mobile.Palette.success.opacity(0.14)
        case .accent: Mobile.Palette.accent.opacity(0.14)
        case .pro: Mobile.Palette.pro.opacity(0.16)
        }
    }
}

/// Canlı nokta: 8 pt yeşil, 1,6 sn'de bir genişleyip sönen halka (azaltılmış harekette sabit).
struct MobileLiveDot: View {
    var color: Color = Mobile.Palette.success
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if !reduceMotion {
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .scaleEffect(pulse ? 1.2 : 0.4)
                        .opacity(pulse ? 0 : 0.8)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

/// Sayfa göstergesi (karşılama, tur).
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Mobile.Palette.accent : Mobile.Palette.borderStrong)
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .shadow(color: index == current ? Mobile.Palette.accent.opacity(0.6) : .clear, radius: 5)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

/// Segmentli seçim (kayıt/giriş, çeviri motoru).
struct SegmentedTabs<Value: Hashable>: View {
    let options: KeyValuePairs<Value, LocalizedStringKey>
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Mobile.Space.hair) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.key == selection
                Button { selection = option.key } label: {
                    Text(option.value)
                        .font(Mobile.TypeScale.body.weight(.semibold))
                        .foregroundStyle(selected ? Mobile.Palette.text : Mobile.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Mobile.Radius.inner)
                                    .fill(Mobile.Palette.surface)
                                    .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.inner).strokeBorder(Mobile.Palette.accent.opacity(0.45)))
                                    .shadow(color: Mobile.Palette.accent.opacity(0.5), radius: 8)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .selectionFeedback(trigger: selected)
            }
        }
        .padding(Mobile.Space.hair)
        .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
    }
}

/// 52'lik giriş alanı.
struct MobileFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Mobile.TypeScale.headline.weight(.regular))
            .foregroundStyle(Mobile.Palette.text)
            .padding(.horizontal, Mobile.Space.tile)
            .frame(minHeight: Mobile.Control.field)
            .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.borderStrong))
    }
}

/// Geniş karonun içindeki 52'lik liste satırı.
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
            Spacer(minLength: Mobile.Space.inline)
            if let detail { Text(verbatim: detail).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary) }
            trailing
        }
        .frame(minHeight: Mobile.Control.row)
        .contentShape(Rectangle())
    }
}

extension ListRow where Trailing == AnyView {
    /// Gidilecek bir ekranı olan satır (sağda ok).
    init(symbol: String, tint: MobileTileIcon.Tint = .neutral, title: LocalizedStringKey, detail: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) {
            AnyView(Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Mobile.Palette.secondary))
        }
    }
}

/// Satırlar arası 1 px ayraç.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Mobile.Palette.borderStrong).frame(height: 1) }
}

// MARK: - Ekran iskeleti

/// Ekran zemini: sağ üstte amber, sol altta mor hareketsiz ışık (§7).
struct MobileBackground: View {
    var body: some View {
        ZStack {
            Mobile.Palette.bg
            RadialGradient(colors: [Mobile.Palette.accent.opacity(0.16), .clear], center: UnitPoint(x: 0.88, y: -0.06),
                           startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Mobile.Palette.pro.opacity(0.12), .clear], center: UnitPoint(x: -0.12, y: 1.06),
                           startRadius: 0, endRadius: 340)
        }
        .ignoresSafeArea()
    }
}

/// Ekran yapısı: güvenli alan + 20 → üst satır → 12 → içerik (12 aralıkla, kayar) → alt düğme bölgesi → 20.
struct MobileScreen<Header: View, Content: View, Bottom: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Mobile.Space.screen)
                .padding(.top, Mobile.Space.inline)
            ScrollView {
                VStack(alignment: .leading, spacing: Mobile.Space.gap) { content }
                    .padding(.horizontal, Mobile.Space.screen)
                    .padding(.top, Mobile.Space.gap)
                    .padding(.bottom, Mobile.Space.screen)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: Mobile.Space.gap) { bottom }
                .padding(.horizontal, Mobile.Space.screen)
                .padding(.bottom, Mobile.Space.screen)
        }
        .foregroundStyle(Mobile.Palette.text)
        .background(MobileBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Başlık bloğu: ekran başına bir `display` başlık + açıklama.
struct ScreenTitle: View {
    var caption: LocalizedStringKey?
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
            if let caption { Text(caption).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary) }
            Text(title).font(Mobile.TypeScale.display).tracking(-0.4).fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alt sayfaların üst satırı: geri düğmesi ve `title` boyunda başlık.
struct BackHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: Mobile.Space.gap) {
            IconButton(symbol: "chevron.left", label: "Back") { dismiss() }
            Text(title).font(Mobile.TypeScale.title)
            Spacer()
            trailing
        }
        .frame(height: Mobile.Control.icon)
    }
}

extension BackHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) { self.init(title: title) { EmptyView() } }
}

/// Hata ya da uyarı satırı.
struct MobileNote: View {
    let text: String
    var tone: Color = Mobile.Palette.warning

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Mobile.TypeScale.caption)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Bento ızgara (§6)

private struct BentoWideKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Karo iki sütunu kaplar (geniş/kahraman karo).
    func bentoWide() -> some View { layoutValue(key: BentoWideKey.self, value: true) }
}

/// İki sütunlu bento ızgara: aralık 12; `bentoWide()` karolar tam satır. Bir satırdaki karoların yüksekliği eşittir.
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
