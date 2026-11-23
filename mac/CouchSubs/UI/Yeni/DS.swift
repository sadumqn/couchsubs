// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI

// Yeni arayüzün tasarım sistemi (onaylı tuval, 22 Kas 2026). Değerler design/yeni-arayuz/tasarim.json'dan gelir; Windows
// aynı dosyayı okur. Ekranlar sabit renk ya da ölçü yazmaz, buradaki adları kullanır. Metinler: design/yeni-arayuz/METINLER.md.
// Eski ekranların Theme/Components'i iPhone'la ortaktır ve değişmez.

// DSTokens (dosyanın okunuşu) iPhone'la ortak: DSTokens.swift. Perde belirteçleri, hareket kapısı ve yeni bileşenler:
// Perde.swift (o da ortak).

enum DS {
    static let tokens: DSTokens = {
        guard let url = Bundle.main.url(forResource: "tasarim", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tokens = try? JSONDecoder().decode(DSTokens.self, from: data) else {
            fatalError("tasarim.json uygulama paketinde yok ya da bozuk")
        }
        return tokens
    }()

    static func color(_ name: String) -> Color {
        guard let pair = tokens.color[name] else { fatalError("Bilinmeyen renk: \(name)") }
        return Color(nsColor: NSColor(name: NSColor.Name("ds." + name)) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? pair.dark : pair.light
            let (r, g, b, a) = DSTokens.rgba(hex) ?? (0, 0, 0, 1)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        })
    }

    static func font(_ name: String) -> Font {
        guard let token = tokens.font[name] else { fatalError("Bilinmeyen yazı biçimi: \(name)") }
        let weight: Font.Weight = switch token.weight {
        case "bold": .bold
        case "semibold": .semibold
        case "medium": .medium
        default: .regular
        }
        return .system(size: token.size, weight: weight, design: token.design == "monospaced" ? .monospaced : .default)
    }

    static func tracking(_ name: String) -> CGFloat { CGFloat(tokens.font[name]?.tracking ?? 0) }
    static func space(_ name: String) -> CGFloat { CGFloat(tokens.space[name] ?? 0) }
    static func radius(_ name: String) -> CGFloat { CGFloat(tokens.radius[name] ?? 0) }
    static func size(_ name: String) -> CGFloat { CGFloat(tokens.size[name] ?? 0) }
    /// Dikey ritim (tasarim.json › space): ayar biriminde başlık → denetim 8, denetim → açıklama 6; birimler arası 24.
    static var unitTitleGap: CGFloat { space("unitTitle") }
    static var unitHintGap: CGFloat { space("unitHint") }
    static var unitGap: CGFloat { space("unitGap") }
    static var mutedTracking: CGFloat { CGFloat(tokens.mutedTracking) }

    // MARK: Hareket

    /// Giriş eğrisi (0.05, 0.7, 0.1, 1); çıkış (0.3, 0, 0.8, 0.15) girişin yaklaşık yarısı sürer.
    static func enter(_ ms: Double) -> Animation {
        let c = tokens.motion.enter
        return .timingCurve(c[0], c[1], c[2], c[3], duration: ms / 1000)
    }

    static func exit(_ ms: Double) -> Animation {
        let c = tokens.motion.exit
        return .timingCurve(c[0], c[1], c[2], c[3], duration: ms / 1000)
    }

    enum Motion { case short, medium, page }

    /// Hareketi azalt açıksa (sistem ya da Ayarlar › Geçiş Animasyonları kapalı) yalnız kısa solma kalır.
    static func animation(_ motion: Motion, reduced: Bool) -> Animation {
        if reduced { return .easeOut(duration: tokens.motion.reduced / 1000) }
        switch motion {
        case .short: return enter(tokens.motion.short)
        case .medium: return enter(tokens.motion.medium)
        case .page: return enter(tokens.motion.page)
        }
    }
}

extension Color {
    static let dsBackground = DS.color("background")
    static let dsSurface = DS.color("surface")
    static let dsField = DS.color("field")
    static let dsBorder = DS.color("border")
    static let dsTileBorder = DS.color("tileBorder")
    static let dsScrollThumb = DS.color("scrollThumb")
    static let dsText = DS.color("text")
    static let dsMuted = DS.color("muted")
    static let dsFaint = DS.color("faint")
    static let dsCharcoal = DS.color("charcoal")
    static let dsOnCharcoal = DS.color("onCharcoal")
    static let dsLogoBack = DS.color("logoBack")
    static let dsLogoSeat = DS.color("logoSeat")
    static let dsAmber = DS.color("amber")
    static let dsAmberHover = DS.color("amberHover")
    static let dsAmberLine = DS.color("amberLine")
    static let dsOnAmber = DS.color("onAmber")
    static let dsAmberText = DS.color("amberText")
    static let dsAmberSoft = DS.color("amberSoft")
    static let dsSwitchOff = DS.color("switchOff")
    static let dsSuccess = DS.color("success")
    static let dsSuccessText = DS.color("successText")
    static let dsSuccessSoft = DS.color("successSoft")
    static let dsSuccessRing = DS.color("successRing")
    static let dsLive = DS.color("live")
    static let dsLiveText = DS.color("liveText")
    static let dsLiveSoft = DS.color("liveSoft")
    static let dsLiveRing = DS.color("liveRing")
    static let dsLiveDot = DS.color("liveDot")
    /// Çeviriyi durduran dolu düğme (Durdur): canlı turuncu-kırmızı zemin, beyaz yazı (iki temada ≥ 3:1, kalın yazı).
    static let dsStopFill = DS.color("stopFill")
    static let dsOnStop = DS.color("onStop")
    static let dsScreenFrame = DS.color("screenFrame")
    static let dsScrim = DS.color("scrim")
    static let dsPeach = DS.color("peach")
    static let dsOlive = DS.color("olive")
    static let dsTeal = DS.color("teal")
    static let dsPlum = DS.color("plum")
    static let dsSky = DS.color("sky")
}

extension Font {
    static let dsH1 = DS.font("h1")
    static let dsH2 = DS.font("h2")
    static let dsH3 = DS.font("h3")
    static let dsSubtitle = DS.font("subtitle")
    static let dsCardTitle = DS.font("cardTitle")
    static let dsLabel = DS.font("label")
    static let dsBody = DS.font("body")
    static let dsBodyStrong = DS.font("bodyStrong")
    static let dsButton = DS.font("button")
    static let dsButtonSecondary = DS.font("buttonSecondary")
    static let dsTab = DS.font("tab")
    static let dsRow = DS.font("row")
    static let dsSmall = DS.font("small")
    static let dsCaption = DS.font("caption")
    static let dsMono = DS.font("mono")
    static let dsMonoValue = DS.font("monoValue")
    static let dsAdTag = DS.font("adTag")
}

// MARK: Hareket tercihi

/// Ayarlar › Geçiş Animasyonları kapalıysa ya da sistemde "Hareketi azalt" açıksa true.
private struct DSReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Uygulamanın kendi "Geçiş Animasyonları" ayarı kapalı (sistem ayarı ayrıca `accessibilityReduceMotion`'dan okunur).
    var dsMotionOff: Bool {
        get { self[DSReducedMotionKey.self] }
        set { self[DSReducedMotionKey.self] = newValue }
    }
}

/// Bir görünümde hareket azaltılmış mı (sistem ya da uygulama ayarı).
struct DSMotion {
    let reduced: Bool

    func callAsFunction(_ motion: DS.Motion) -> Animation { DS.animation(motion, reduced: reduced) }
}

private struct DSMotionReader<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.dsMotionOff) private var app
    let content: (DSMotion) -> Content

    var body: some View { content(DSMotion(reduced: system || app)) }
}

/// Hareket tercihine göre içerik kurar: `WithDSMotion { motion in ... .animation(motion(.medium), value: x) }`.
struct WithDSMotion<Content: View>: View {
    let content: (DSMotion) -> Content

    init(@ViewBuilder content: @escaping (DSMotion) -> Content) {
        self.content = content
    }

    var body: some View { DSMotionReader(content: content) }
}

// MARK: Yazı biçimleri

extension View {
    /// Gri açıklama/ipucu yazısı: ikincil renk, -0.5 harf aralığı, satıra iner.
    func dsMuted(_ font: Font = .dsSmall) -> some View {
        self.font(font)
            .foregroundStyle(Color.dsMuted)
            .tracking(DS.mutedTracking)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Küçük bölüm etiketi (tablo sütunu, kart üstü küçük ad): sistem yazısı 13 orta kalın, cümle düzeni, gri. Adı eski;
/// mono büyük harf artık kullanılmaz (mono yalnız kısayol rozeti ve teknik değerde).
struct DSMonoLabel: View {
    let text: LocalizedStringKey
    var color: Color = .dsMuted

    init(_ text: LocalizedStringKey, color: Color = .dsMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.dsLabel)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Başlık + altında 4 pt açıklama (satır başlıkları, seçenek kartları).
struct DSTitleBlock: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var titleFont: Font = .dsBody.weight(.medium)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("xxs")) {
            Text(title).font(titleFont).foregroundStyle(Color.dsText).fixedSize(horizontal: false, vertical: true)
            if let subtitle { Text(subtitle).dsMuted() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sayfa başlığı: üstte isteğe bağlı mono adım etiketi (başlığa yakın), 32 pt başlık, 4 pt altında açıklama.
struct DSPageTitle: View {
    var eyebrow: String?
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("xxs")) {
            if let eyebrow {
                Text(verbatim: eyebrow)
                    .font(.dsLabel)
                    .foregroundStyle(Color.dsMuted)
                    .padding(.bottom, DS.space("xxs"))
            }
            Text(title)
                .font(.dsH1)
                .tracking(DS.tracking("h1"))
                .foregroundStyle(Color.dsText)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.dsBody)
                    .foregroundStyle(Color.dsMuted)
                    .tracking(DS.mutedTracking)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.space("xxs"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
