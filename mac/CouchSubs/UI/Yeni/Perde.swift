// SPDX-License-Identifier: AGPL-3.0-only

import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Perde tasarım dili (23 Kas 2026; tuval DL-* panoları, design/yeni-arayuz/tasarim.json v2). Mac ve iPhone aynı dosyayı
// derler; adlar ve ölçüler iki platformda birebir. İçerik:
//   • Perde renkleri (yükseltilmiş yüzey, ışıma, cam, bilgi, altyazı plakası …)
//   • Tek hareket kapısı (DSMotionGate): çeviri sürerken, hareket azaltılmışken, Geçiş Animasyonları kapalıyken ya da
//     pencere/uygulama arka plandayken sürekli animasyonlar durur; yalnız kısa geri bildirimler kalır.
//   • Efektler: yükselti (e1/e2), cam (e3), ana ışıma, seçili ışıma, odak halkası, projeksiyon ışığı, ortam ışığı.
//   • Yeni bileşenler: canlı nokta, durum hapı, sayı rozeti, bilgi/uyarı/hata kutusu, çubuk yükleyici, arama halkası,
//     ilerleme çubuğu, adım çizelgesi, başarı anı, altyazı plakası, perde önizlemesi, oyun kapağı + raf, TV kartı.
// Sürekli animasyonlar TimelineView ile en çok 30 kare/sn (ortam ışığı 15), kapı kapalıyken durağan tek kare çizer.

// MARK: Renkler

extension Color {
    static let dsSurfaceRaised = DS.color("surfaceRaised")
    static let dsSurfaceHigh = DS.color("surfaceHigh")
    /// Seçicinin seçili hapı (açıkta beyaz, koyuda #3A3C44).
    static let dsSegPill = DS.color("segPill")
    static let dsBorderStrong = DS.color("borderStrong")
    /// Koyu temada kartın üst kenar parlaması (açıkta saydam).
    static let dsTopHighlight = DS.color("topHighlight")
    static let dsAmberGlow = DS.color("amberGlow")
    static let dsAmberRing = DS.color("amberRing")
    static let dsInfo = DS.color("info")
    static let dsInfoSoft = DS.color("infoSoft")
    static let dsInfoText = DS.color("infoText")
    static let dsGlass = DS.color("glass")
    static let dsGlassBorder = DS.color("glassBorder")
    static let dsCharTeal = DS.color("charTeal")
    static let dsCharPeach = DS.color("charPeach")
    static let dsSubtitlePlate = DS.color("subtitlePlate")
    static let dsSubtitleText = DS.color("subtitleText")
    static let dsCoverScrim = DS.color("coverScrim")
}

// MARK: Hareket kapısı

/// Uygulamanın tek hareket kapısı. Kökte `.dsMotionGate(translating:)` bir kez kurulur; bileşenler
/// `@Environment(\.dsMotionGate)` okur.
/// - `reduced`: sistemde "Hareketi azalt" açık ya da Ayarlar › Geçiş Animasyonları kapalı → geçişler 0–100 ms solma.
/// - `ambient`: boşta süren efektler (ortam ışığı, parıltı, ışın, arama halkası, çubuk yükleyici, logo nefesi) oynar mı.
/// - `live`: canlı nabız oynar mı (çeviri sürerken de atar; ekrandaki tek sürekli animasyon).
struct DSMotionGate: Equatable {
    var reduced = false
    var translating = false
    var active = true

    var ambient: Bool { Self.forced ?? (!reduced && !translating && active) }
    var live: Bool { Self.forced ?? (!reduced && active) }

    /// Yalnız testler (işlemci ölçümü, ekran görüntüsü): kapıyı zorla aç/kapat.
    nonisolated(unsafe) static var forced: Bool?
}

private struct DSMotionGateKey: EnvironmentKey {
    static let defaultValue = DSMotionGate()
}

extension EnvironmentValues {
    var dsMotionGate: DSMotionGate {
        get { self[DSMotionGateKey.self] }
        set { self[DSMotionGateKey.self] = newValue }
    }
}

/// Kökteki kapı: sistem ayarı, uygulama ayarı (`dsMotionOff`, dışarıda kurulur), çeviri durumu ve pencerenin/uygulamanın
/// önde olup olmadığı birleşir.
private struct DSMotionGateRoot: ViewModifier {
    let translating: Bool?
    @ObservedObject private var shared = DSMotionState.shared
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.dsMotionOff) private var app
    #if os(macOS)
    @Environment(\.controlActiveState) private var state
    private var active: Bool { state != .inactive }
    #else
    @Environment(\.scenePhase) private var phase
    private var active: Bool { phase == .active }
    #endif

    func body(content: Content) -> some View {
        content.environment(\.dsMotionGate, DSMotionGate(reduced: system || app, translating: translating ?? shared.translating,
                                                         active: active))
    }
}

/// Çeviri sürüyor mu (uygulamanın modeli günceller); ana pencere dışındaki pencereler kapıyı buradan kurar.
final class DSMotionState: ObservableObject {
    static let shared = DSMotionState()
    @Published var translating = false
}

extension View {
    /// Hareket kapısını kurar. `dsMotionOff` (Geçiş Animasyonları) bu çağrının dışında verilmelidir. `translating`
    /// verilmezse uygulamanın çeviri durumu (`DSMotionState.shared`) kullanılır.
    func dsMotionGate(translating: Bool? = nil) -> some View { modifier(DSMotionGateRoot(translating: translating)) }
}

extension DS {
    /// Hareket kapısına göre animasyon: azaltılmışsa kısa solma.
    static func animation(_ motion: Motion, gate: DSMotionGate) -> Animation { animation(motion, reduced: gate.reduced) }

    /// Başarı tiki ve küçük "oturma" geri bildirimleri: hafif aşmalı yay (tasarim.json › motion.spring, 600 ms).
    static func spring(reduced: Bool) -> Animation {
        if reduced { return .easeOut(duration: tokens.motion.reduced / 1000) }
        let c = tokens.motion.spring
        return .timingCurve(c[0], c[1], c[2], c[3], duration: tokens.motion.celebrate / 1000)
    }

    /// effect › ad › alan (ör. effect("sheen", "period")).
    static func effect(_ name: String, _ field: String, _ fallback: Double) -> Double { tokens.effect[name]?[field] ?? fallback }
}

/// Sürekli animasyonların saati: `running` iken en çok `fps` kare/sn zaman verir, değilse `nil` (durağan kare).
struct DSClock<Content: View>: View {
    let running: Bool
    var fps: Double = 30
    let content: (Double?) -> Content

    init(running: Bool, fps: Double = 30, @ViewBuilder content: @escaping (Double?) -> Content) {
        self.running = running
        self.fps = fps
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps, paused: !running)) { context in
            content(running ? context.date.timeIntervalSinceReferenceDate : nil)
        }
    }
}

// MARK: Yükselti, cam, ışıma, odak

enum DSElevation {
    /// e1 · kart: yüzey + kıl çizgi + (koyuda) üst kenar parlaması, (açıkta) çok hafif gölge.
    case card
    /// e2 · yükseltilmiş: yükseltilmiş yüzey + güçlü kıl çizgi + derin gölge (hesap kartı, açılır menü, odak kartı).
    case raised
}

extension View {
    /// Yüzey ve kenarlık; koyu temada derinlik gölgeyle değil ışıkla (üst kenar parlaması).
    func dsElevation<S: InsettableShape>(_ level: DSElevation, in shape: S) -> some View {
        modifier(DSElevationModifier(level: level, shape: shape))
    }

    /// e3 · cam: yalnız katmanlar (sekme çubuğu, sheet, perde hapları). Bulanıklık sistemin malzemesi (statik).
    func dsGlass<S: InsettableShape>(in shape: S) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.dsGlass)
            }
        }
        .overlay(shape.strokeBorder(Color.dsGlassBorder))
        .overlay(DSTopEdge(shape: shape).allowsHitTesting(false))
    }

    /// Ana eylemin amber ışıması (0 10 28 -8 amberGlow).
    func dsPrimaryGlow(_ strength: CGFloat = 1) -> some View {
        shadow(color: Color.dsAmberGlow.opacity(Double(strength)), radius: 14 * strength, y: 8 * strength)
    }

    /// Seçili seçenek: 2 pt amber iç kenar + amber yumuşak dolgu + hafif ışıma.
    func dsSelectedGlow<S: InsettableShape>(_ on: Bool, in shape: S) -> some View {
        overlay {
            if on {
                shape.fill(Color.dsAmberSoft)
                    .overlay(shape.strokeBorder(Color.dsAmber, lineWidth: 2))
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: on ? Color.dsAmberGlow.opacity(0.7) : .clear, radius: 11)
    }

    /// Odak (klavye / kumanda): 2 pt aralıklı 2 pt amber halka + ışıma + %4 büyüme, 150 ms. Fareyle tıklamada görünmez:
    /// çağıran yalnız klavye odağında `focused` verir (`@Environment(\.isFocused)` ya da `@FocusState`).
    func dsFocusRing<S: InsettableShape>(_ focused: Bool, in shape: S) -> some View {
        modifier(DSFocusRingModifier(focused: focused, shape: shape))
    }
}

private struct DSElevationModifier<S: InsettableShape>: ViewModifier {
    let level: DSElevation
    let shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let raised = level == .raised
        content
            .background {
                shape.fill(raised ? Color.dsSurfaceRaised : Color.dsSurface)
                    .shadow(color: shadowColor, radius: raised ? 22 : 1, y: raised ? 14 : 1)
            }
            .overlay(shape.strokeBorder(raised ? Color.dsBorderStrong : Color.dsBorder).allowsHitTesting(false))
            .overlay(DSTopEdge(shape: shape).allowsHitTesting(false))
    }

    private var shadowColor: Color {
        switch (level, scheme) {
        case (.raised, .dark): .black.opacity(0.45)
        case (.raised, _): Color(red: 0.235, green: 0.157, blue: 0.039).opacity(0.16)
        case (.card, .dark): .clear
        case (.card, _): Color(red: 0.235, green: 0.157, blue: 0.039).opacity(0.04)
        }
    }
}

/// Koyu temada yüzeyin üst kenarındaki ince ışık (inset 0 1 0 topHighlight); açık temada saydam.
private struct DSTopEdge<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape.inset(by: 0.5)
            .stroke(LinearGradient(colors: [Color.dsTopHighlight, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            .accessibilityHidden(true)
    }
}

private struct DSFocusRingModifier<S: InsettableShape>: ViewModifier {
    let focused: Bool
    let shape: S
    @Environment(\.dsMotionGate) private var gate

    func body(content: Content) -> some View {
        content
            .overlay {
                if focused {
                    shape.inset(by: -4).strokeBorder(Color.dsAmber, lineWidth: 2)
                        .shadow(color: Color.dsAmberGlow, radius: 12)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(focused && !gate.reduced ? 1.04 : 1)
            .animation(DS.animation(.short, gate: gate), value: focused)
    }
}

/// Projeksiyon ışığı: üst kenardan düşen geniş, yumuşak amber ışık (radyal; koyuda %16, açıkta %22). Durağandır.
struct DSProjectorLight: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let alpha = DS.effect("projectorLight", scheme == .dark ? "dark" : "light", scheme == .dark ? 0.16 : 0.22)
        EllipticalGradient(colors: [Color.dsAmber.opacity(alpha), Color.dsAmber.opacity(0)],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadiusFraction: 0, endRadiusFraction: 0.6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Ortam ışığı: amber, şeftali ve gök mavisi üç yumuşak leke 24 sn'lik döngüde çok yavaş süzülür (Core Animation);
/// kapı kapalıyken (çeviri, hareketi azalt, arka plan) durağan. Bulanıklık süzgeci yok, radyal degrade.
struct DSAmbientGlow: View {
    var intensity: Double = 1
    @Environment(\.dsMotionGate) private var gate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if gate.ambient {
                DSAmbientLayers(intensity: intensity, dark: scheme == .dark, running: true).id(scheme)
            } else {
                // Durağan: aynı lekeler düz SwiftUI degradesiyle (katman yok).
                GeometryReader { geometry in
                    let size = geometry.size
                    let span = max(size.width, size.height)
                    ZStack {
                        ForEach(Array(DSAmbientLayers.blobs.enumerated()), id: \.offset) { _, blob in
                            let (name, x, y, scale, alpha, _, _) = blob
                            RadialGradient(colors: [DS.color(name).opacity(alpha * intensity), DS.color(name).opacity(0)],
                                           center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: span * scale)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Core Animation katmanları

// Sürekli efektler (ortam ışığı, canlı nabız) Core Animation ile: hareketi pencere sunucusu çizer, uygulamanın işlemcisi
// kare başına çalışmaz (TimelineView'da ortam ışığı tek başına ~%5 tutuyordu). Kapı kapanınca animasyonlar kaldırılır.

#if os(macOS)
typealias DSPlatformView = NSView
#else
typealias DSPlatformView = UIView
#endif

/// Kendi katmanını boyutuna göre kuran düz görünüm.
final class DSLayerView: DSPlatformView {
    let root = CALayer()
    var onLayout: ((CALayer, CGSize) -> Void)?
    private var laidOut = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        layer?.addSublayer(root)
        #else
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(root)
        #endif
        root.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        relayout()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }
    #endif

    func relayout(force: Bool = false) {
        guard force || bounds.size != laidOut else { return }
        laidOut = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        onLayout?(root, bounds.size)
        CATransaction.commit()
    }
}

extension DS {
    /// tasarim.json rengi, verilen temada Core Animation rengi olarak.
    static func cgColor(_ name: String, dark: Bool, alpha: Double = 1) -> CGColor {
        let pair = tokens.color[name]
        let (r, g, b, a) = DSTokens.rgba((dark ? pair?.dark : pair?.light) ?? "#000000") ?? (0, 0, 0, 1)
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a * alpha)
    }
}

/// Ortam ışığı lekeleri: radyal degrade katmanları, 24 sn'lik döngüde (gidiş-dönüş) birkaç yüzde kayar.
private struct DSAmbientLayers {
    let intensity: Double
    let dark: Bool
    let running: Bool

    static let blobs: [(String, CGFloat, CGFloat, CGFloat, Double, CGFloat, CGFloat)] = [
        ("amber", 0.25, 0.2, 0.42, 0.18, 0.04, 0.03),
        ("peach", 0.8, 0.1, 0.36, 0.12, -0.04, 0.03),
        ("sky", 0.7, 0.9, 0.42, 0.06, 0.04, -0.03),
    ]

    func make() -> DSLayerView {
        let view = DSLayerView(frame: .zero)
        configure(view)
        return view
    }

    func configure(_ view: DSLayerView) {
        let (dark, intensity, running) = (dark, intensity, running)
        view.onLayout = { root, size in
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let span = max(size.width, size.height)
            let half = DS.tokens.motion.ambient / 2000
            for (index, blob) in Self.blobs.enumerated() {
                let (name, x, y, scale, alpha, dx, dy) = blob
                let radius = span * scale
                let layer = CAGradientLayer()
                layer.type = .radial
                layer.colors = [DS.cgColor(name, dark: dark, alpha: alpha * intensity), DS.cgColor(name, dark: dark, alpha: 0)]
                layer.startPoint = CGPoint(x: 0.5, y: 0.5)
                layer.endPoint = CGPoint(x: 1, y: 1)
                layer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
                let start = CGPoint(x: size.width * x, y: size.height * y)
                layer.position = start
                if running {
                    let move = CABasicAnimation(keyPath: "position")
                    move.fromValue = NSValue(dsPoint: start)
                    move.toValue = NSValue(dsPoint: CGPoint(x: start.x + size.width * dx, y: start.y + size.height * dy))
                    move.duration = half
                    move.autoreverses = true
                    move.repeatCount = .infinity
                    move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    move.timeOffset = half * Double(index) * 0.66
                    // Birkaç yüzdelik, 12 sn'lik süzülme 15 kare/sn'de de akıcı; pencere her karede yeniden birleştirilmez.
                    move.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 15)
                    layer.add(move, forKey: "drift")
                }
                root.addSublayer(layer)
            }
        }
        view.relayout(force: true)
    }
}

/// Canlı nabız katmanları: dolu nokta + 1,6 sn'de bir dışa yayılıp sönen halka.
private struct DSPulseLayers {
    let color: Color
    let size: CGFloat
    let running: Bool

    func make() -> DSLayerView {
        let view = DSLayerView(frame: .zero)
        configure(view)
        return view
    }

    func configure(_ view: DSLayerView) {
        #if os(macOS)
        var fill = NSColor(color).cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { fill = NSColor(color).cgColor }
        #else
        let fill = UIColor(color).resolvedColor(with: view.traitCollection).cgColor
        #endif
        let (size, running) = (size, running)
        view.onLayout = { root, area in
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let center = CGPoint(x: area.width / 2, y: area.height / 2)
            let ring = CALayer()
            ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            ring.position = center
            ring.cornerRadius = size / 2
            ring.backgroundColor = fill
            ring.opacity = 0
            let dot = CALayer()
            dot.bounds = ring.bounds
            dot.position = center
            dot.cornerRadius = size / 2
            dot.backgroundColor = fill
            root.addSublayer(ring)
            root.addSublayer(dot)
            guard running else { return }
            let period = DS.tokens.motion.livePulse / 1000
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = (size + 2 * DS.effect("livePulse", "ring", 6)) / size
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.55
            fade.toValue = 0
            for part in [grow, fade] {
                part.duration = period * 0.7
                part.timingFunction = CAMediaTimingFunction(name: .easeOut)
            }
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = period
            group.repeatCount = .infinity
            ring.add(group, forKey: "pulse")
        }
        view.relayout(force: true)
    }
}

private extension NSValue {
    convenience init(dsPoint point: CGPoint) {
        #if os(macOS)
        self.init(point: point)
        #else
        self.init(cgPoint: point)
        #endif
    }
}

#if os(macOS)
extension DSAmbientLayers: NSViewRepresentable {
    func makeNSView(context: Context) -> DSLayerView { make() }
    func updateNSView(_ view: DSLayerView, context: Context) { configure(view) }
}

extension DSPulseLayers: NSViewRepresentable {
    func makeNSView(context: Context) -> DSLayerView { make() }
    func updateNSView(_ view: DSLayerView, context: Context) { configure(view) }
}
#else
extension DSAmbientLayers: UIViewRepresentable {
    func makeUIView(context: Context) -> DSLayerView { make() }
    func updateUIView(_ view: DSLayerView, context: Context) { configure(view) }
}

extension DSPulseLayers: UIViewRepresentable {
    func makeUIView(context: Context) -> DSLayerView { make() }
    func updateUIView(_ view: DSLayerView, context: Context) { configure(view) }
}
#endif

// MARK: Canlı nokta

/// Canlı/çalışıyor noktası: 1,6 sn'de bir dışa yayılan halka (nabız; Core Animation, işlemciye yük bindirmez). Çeviri
/// sürerken de atar; hareket azaltılmışken ya da arka planda sabit nokta.
struct DSPulseDot: View {
    var color: Color = .dsLiveDot
    var size: CGFloat = 8
    @Environment(\.dsMotionGate) private var gate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if gate.live {
                // Halka noktanın dışına taşar; katman kırpılmaz.
                DSPulseLayers(color: color, size: size, running: true).id(scheme)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Durum hapı, sayı rozeti

/// Durum hapı: renk + nokta/simge + yazı birlikte (durum rengi tek başına anlam taşımaz). Canlı tonunda nokta nabız atar.
struct DSStatusChip: View {
    enum Tone { case ok, live, amber, info, muted, glass }
    let text: LocalizedStringKey
    var tone: Tone = .muted
    var dot = true
    var icon: String?

    init(_ text: LocalizedStringKey, tone: Tone = .muted, dot: Bool = true, icon: String? = nil) {
        self.text = text
        self.tone = tone
        self.dot = dot
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: DS.space("unitHint")) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .heavy)).accessibilityHidden(true)
            } else if dot {
                if tone == .live {
                    DSPulseDot(color: .dsLiveDot, size: 7)
                } else {
                    Circle().fill(foreground).frame(width: 7, height: 7).accessibilityHidden(true)
                }
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            if tone == .glass {
                Capsule(style: .circular).fill(.ultraThinMaterial)
                Capsule(style: .circular).fill(Color.black.opacity(0.45))
            } else {
                Capsule(style: .circular).fill(background)
            }
        }
        .overlay { if tone == .glass { Capsule(style: .circular).strokeBorder(Color.white.opacity(0.10)) } }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch tone {
        case .ok: .dsSuccessText
        case .live: .dsLiveText
        case .amber: .dsAmberText
        case .info: .dsInfoText
        case .muted: .dsMuted
        case .glass: Color(red: 0.953, green: 0.933, blue: 0.894)
        }
    }

    private var background: Color {
        switch tone {
        case .ok: .dsSuccessSoft
        case .live: .dsLiveSoft
        case .amber: .dsAmberSoft
        case .info: .dsInfoSoft
        case .muted, .glass: .dsField
        }
    }
}

/// Sayı rozeti (ör. Oyun Paketleri 6): amber dolu ya da nötr.
struct DSCountBadge: View {
    let count: Int
    var neutral = false

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(neutral ? Color.dsMuted : Color.dsOnAmber)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(neutral ? Color.dsField : Color.dsAmber, in: Capsule(style: .circular))
            .fixedSize()
    }
}

// MARK: Bilgi / uyarı / hata kutusu

/// Bilgi, uyarı, hata ya da başarı kutusu: tonlu yumuşak zemin, kutuyu köşe yarıçapıyla komple saran ince (1 pt) renkli
/// kenarlık, solda simge; isteğe bağlı kalın başlık, metin (Markdown **kalın**) ve altta düğmeler.
struct DSNoticeBox<Actions: View>: View {
    enum Tone { case info, warning, error, success }
    var tone: Tone = .warning
    var title: LocalizedStringKey?
    let text: LocalizedStringKey
    @ViewBuilder var actions: Actions

    init(tone: Tone = .warning, title: LocalizedStringKey? = nil, text: LocalizedStringKey, @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.title = title
        self.text = text
        self.actions = actions()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        HStack(alignment: .top, spacing: DS.space("s")) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.space("titleBody")) {
                if let title { Text(title).font(.dsBodyStrong).foregroundStyle(titleColor).fixedSize(horizontal: false, vertical: true) }
                Text(text)
                    .font(.dsSmall)
                    .foregroundStyle(title == nil ? Color.dsText : Color.dsMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if Actions.self != EmptyView.self {
                    HStack(spacing: DS.space("xs")) { actions }.padding(.top, DS.space("xxs"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.space("m"))
        .padding(.vertical, DS.space("s") + 2)
        .background(soft, in: shape)
        .overlay(shape.strokeBorder(ring, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch tone {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch tone {
        case .info: .dsInfoText
        case .warning: .dsAmberText
        case .error: .dsLiveText
        case .success: .dsSuccessText
        }
    }

    private var titleColor: Color { tone == .error ? .dsLiveText : .dsText }

    private var soft: Color {
        switch tone {
        case .info: .dsInfoSoft
        case .warning: .dsAmberSoft
        case .error: .dsLiveSoft
        case .success: .dsSuccessSoft
        }
    }

    private var ring: Color {
        switch tone {
        case .info: Color.dsInfo.opacity(0.45)
        case .warning: .dsAmberRing
        case .error: .dsLiveRing
        case .success: .dsSuccessRing
        }
    }
}

extension DSNoticeBox where Actions == EmptyView {
    init(tone: Tone = .warning, title: LocalizedStringKey? = nil, text: LocalizedStringKey) {
        self.init(tone: tone, title: title, text: text) { EmptyView() }
    }
}

// MARK: Yükleyiciler

/// Çubuk yükleyici: logodaki iki amber altyazı çubuğu sırayla daralıp genişler (1,2 sn). Kapı kapalıyken durağan.
struct DSBarsLoader: View {
    var scale: CGFloat = 1
    var color: Color = .dsAmber
    @Environment(\.dsMotionGate) private var gate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if gate.ambient {
                DSLoaderLayers(kind: .bars(scale), color: color, running: true).id(scheme)
            } else {
                VStack(spacing: 3 * scale) {
                    Capsule(style: .circular).fill(color).frame(width: 18 * scale, height: 4 * scale)
                    Capsule(style: .circular).fill(color).frame(width: 12 * scale, height: 4 * scale)
                }
            }
        }
            .frame(width: 18 * scale, height: 11 * scale)
            .accessibilityHidden(true)
    }
}

/// Arama halkası dalgası: merkezdeki ışımalı amber noktadan üç halka 0,8 sn arayla dışa yayılır (2,4 sn; Core Animation).
/// Kapı kapalıyken tek durağan halka.
struct DSSearchRings: View {
    var size: CGFloat = 56
    @Environment(\.dsMotionGate) private var gate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if gate.ambient {
                DSLoaderLayers(kind: .rings, color: .dsAmber, running: true).id(scheme)
            } else {
                Circle().strokeBorder(Color.dsAmber.opacity(0.5), lineWidth: 2).scaleEffect(0.82)
            }
        }
            .overlay {
                Circle().fill(Color.dsAmber)
                    .frame(width: size - 36, height: size - 36)
                    .shadow(color: Color.dsAmberGlow, radius: 8)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Yükleyici katmanları (çubuklar, arama halkaları).
private struct DSLoaderLayers {
    enum Kind { case bars(CGFloat), rings }
    let kind: Kind
    let color: Color
    let running: Bool

    func make() -> DSLayerView {
        let view = DSLayerView(frame: .zero)
        configure(view)
        return view
    }

    func configure(_ view: DSLayerView) {
        #if os(macOS)
        var fill = NSColor(color).cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { fill = NSColor(color).cgColor }
        #else
        let fill = UIColor(color).resolvedColor(with: view.traitCollection).cgColor
        #endif
        let (kind, running) = (kind, running)
        view.onLayout = { root, area in
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            switch kind {
            case let .bars(scale):
                let period = DS.effect("barsLoader", "period", 1200) / 1000
                for (index, width) in [CGFloat(18), 12].enumerated() {
                    let bar = CALayer()
                    bar.bounds = CGRect(x: 0, y: 0, width: width * scale, height: 4 * scale)
                    bar.cornerRadius = 2 * scale
                    bar.backgroundColor = fill
                    bar.position = CGPoint(x: area.width / 2, y: (2 + CGFloat(index) * 7) * scale)
                    if running {
                        let squeeze = CABasicAnimation(keyPath: "transform.scale.x")
                        squeeze.fromValue = 1
                        squeeze.toValue = 0.45
                        squeeze.duration = period / 2
                        squeeze.autoreverses = true
                        squeeze.repeatCount = .infinity
                        squeeze.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        squeeze.timeOffset = index == 0 ? 0 : period - 0.18
                        bar.add(squeeze, forKey: "squeeze")
                    }
                    root.addSublayer(bar)
                }
            case .rings:
                let period = DS.effect("searchRings", "period", 2400) / 1000
                let stagger = DS.effect("searchRings", "stagger", 800) / 1000
                let count = running ? Int(DS.effect("searchRings", "count", 3)) : 1
                for index in 0..<count {
                    let ring = CALayer()
                    ring.bounds = CGRect(origin: .zero, size: area)
                    ring.position = CGPoint(x: area.width / 2, y: area.height / 2)
                    ring.cornerRadius = area.width / 2
                    ring.borderWidth = 2
                    ring.borderColor = fill
                    if running {
                        ring.opacity = 0
                        let grow = CABasicAnimation(keyPath: "transform.scale")
                        grow.fromValue = 0.3
                        grow.toValue = 1.25
                        let fade = CABasicAnimation(keyPath: "opacity")
                        fade.fromValue = 0.9
                        fade.toValue = 0
                        let group = CAAnimationGroup()
                        group.animations = [grow, fade]
                        group.duration = period
                        group.repeatCount = .infinity
                        // Giriş eğrisi (0.05, 0.7, 0.1, 1): hızlı açılır, yavaşça söner.
                        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
                        group.timeOffset = period - Double(index) * stagger
                        ring.add(group, forKey: "ring")
                    } else {
                        ring.opacity = 0.5
                        ring.transform = CATransform3DMakeScale(0.82, 0.82, 1)
                    }
                    root.addSublayer(ring)
                }
            }
        }
        view.relayout(force: true)
    }
}

#if os(macOS)
extension DSLoaderLayers: NSViewRepresentable {
    func makeNSView(context: Context) -> DSLayerView { make() }
    func updateNSView(_ view: DSLayerView, context: Context) { configure(view) }
}
#else
extension DSLoaderLayers: UIViewRepresentable {
    func makeUIView(context: Context) -> DSLayerView { make() }
    func updateUIView(_ view: DSLayerView, context: Context) { configure(view) }
}
#endif

// MARK: İlerleme çubuğu

/// İlerleme çubuğu: 8 pt iz (alan rengi), amber degrade dolgu + ışıma; `running` iken dolgunun üstünden 1,8 sn'de bir
/// ışık geçer (yalnız sürerken ve kapı açıkken).
struct DSProgressBar: View {
    let value: Double
    var running = true
    @Environment(\.dsMotionGate) private var gate

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule(style: .circular).fill(Color.dsField)
                Capsule(style: .circular)
                    .fill(LinearGradient(colors: [.dsAmber, .dsAmberHover], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .shadow(color: Color.dsAmberGlow, radius: 6)
                    .overlay {
                        if running && gate.ambient && width > 0 {
                            DSClock(running: true) { time in
                                let period = DS.effect("sheen", "period", 1800) / 1000
                                let p = (time ?? 0).truncatingRemainder(dividingBy: period) / period
                                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: max(width * 0.6, 24))
                                    .offset(x: (CGFloat(p) * 2 - 1) * width)
                            }
                            .frame(width: width)
                            .clipShape(Capsule(style: .circular))
                        }
                    }
            }
        }
        .frame(height: 8)
        .animation(DS.animation(.medium, gate: gate), value: value)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "%\(Int((value * 100).rounded()))"))
    }
}

/// Başlıklı ilerleme: solda durum ("İndiriliyor…"), sağda mono amber yüzde, 6 pt altında çubuk.
struct DSProgressRow: View {
    let title: LocalizedStringKey
    let value: Double
    var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("titleBody")) {
            HStack {
                Text(title).font(.dsSmall).foregroundStyle(Color.dsText)
                Spacer(minLength: DS.space("s"))
                Text(verbatim: "%\(Int((value * 100).rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Color.dsAmberText)
            }
            DSProgressBar(value: value, running: running)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Adım çizelgesi

/// Adım çizelgesi: biten adım amber dolu + tik (çizgisi amber), şimdiki adım yükseltilmiş + amber halka ve ışıma, sıradaki
/// soluk. Tıklanmaz; seçenek gibi görünmez.
struct DSStepTimeline: View {
    enum Phase { case done, current, todo }

    struct Step: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        var detail: LocalizedStringKey?
        let state: Phase
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: DS.space("s")) {
                    dot(step.state, number: index + 1)
                    VStack(alignment: .leading, spacing: DS.space("line")) {
                        Text(step.title)
                            .font(step.state == .current ? .dsBodyStrong : .dsBody)
                            .foregroundStyle(step.state == .todo ? Color.dsMuted : Color.dsText)
                        if let detail = step.detail { Text(detail).dsMutedSmall() }
                    }
                    .padding(.top, DS.space("line"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, index == steps.count - 1 ? 0 : DS.space("m"))
                .background(alignment: .topLeading) {
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(step.state == .done ? Color.dsAmber : Color.dsBorderStrong)
                            .frame(width: 2)
                            .padding(.top, 26)
                            .padding(.bottom, 2)
                            .padding(.leading, 11)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func dot(_ state: Phase, number: Int) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Color.dsAmber)
                    .overlay(Circle().inset(by: -4).strokeBorder(Color.dsAmberSoft, lineWidth: 4))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.dsOnAmber)
            case .current:
                Circle().fill(Color.dsSurfaceRaised)
                    .overlay(Circle().strokeBorder(Color.dsAmber, lineWidth: 2))
                    .shadow(color: Color.dsAmberGlow, radius: 7)
                Text(verbatim: "\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dsAmberText)
            case .todo:
                Circle().fill(Color.dsField)
                Text(verbatim: "\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dsMuted)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Küçük gri açıklama (13, -0.5 harf aralığı).
    func dsMutedSmall() -> some View {
        font(.dsSmall).foregroundStyle(Color.dsMuted).tracking(DS.mutedTracking).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Başarı anı

/// Başarı anı (Eşleşti, Paket Kuruldu, Kurulum Tamam): arkada amber ışınlar bir kez döner ve söner, ortadaki amber
/// yuvarlakta tik yayla oturur; iPhone'da başarı titreşimi. Hepsi en çok 1 sn. Hareket azaltılmışken (ya da çeviri
/// sürerken) yalnız tik. Yeniden oynatmak için çağıran `.id(...)` değiştirir.
struct DSCelebration: View {
    var size: CGFloat = 64
    @Environment(\.dsMotionGate) private var gate
    @State private var start = Date()
    @State private var finished = false
    @State private var seated = false

    static let duration: Double = 1

    var body: some View {
        ZStack {
            if gate.ambient && !finished {
                DSClock(running: true) { time in
                    let elapsed = max(0, (time ?? start.timeIntervalSinceReferenceDate) - start.timeIntervalSinceReferenceDate)
                    Canvas { canvas, area in Self.rays(&canvas, size: area, elapsed: elapsed) }
                }
                .frame(width: size * 3.2, height: size * 3.2)
                .allowsHitTesting(false)
            }
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.824, blue: 0.478), Color(red: 0.941, green: 0.663, blue: 0.173)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().inset(by: -8).strokeBorder(Color.dsAmberSoft, lineWidth: 8))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .heavy))
                        .foregroundStyle(Color.dsOnAmber)
                        .scaleEffect(seated || gate.reduced ? 1 : 0.3)
                        .opacity(seated || gate.reduced ? 1 : 0)
                }
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear {
            start = Date()
            withAnimation(DS.spring(reduced: gate.reduced)) { seated = true }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
            finished = true
        }
        .accessibilityHidden(true)
    }

    /// Konik ışınlar (8° ışın / 24° adım), merkezden yumuşakça söner; 12 sn'lik tam tur hızında döner, son 0,3 sn'de solar.
    static func rays(_ canvas: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let rotate = elapsed / (DS.effect("celebrate", "rayRotate", 12000) / 1000) * 2 * .pi
        let fadeIn = min(elapsed / 0.2, 1)
        let fadeOut = elapsed > duration - 0.3 ? max(0, (duration - elapsed) / 0.3) : 1
        let alpha = 0.22 * fadeIn * fadeOut
        guard alpha > 0 else { return }
        let gradient = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [.init(color: Color.dsAmber.opacity(alpha), location: 0.25), .init(color: Color.dsAmber.opacity(0), location: 1)]),
            center: center, startRadius: 0, endRadius: radius)
        var path = Path()
        for index in 0..<15 {
            let a = rotate + Double(index) * 24 * .pi / 180
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: .radians(a), endAngle: .radians(a + 8 * .pi / 180), clockwise: false)
            path.closeSubpath()
        }
        canvas.fill(path, with: gradient)
    }
}

/// Başarı anı kartı: başarı anı + başlık + kısa özet (tek büyük simge, iki satır; düğme çağıranda).
struct DSSuccessMoment: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: DS.space("s")) {
            DSCelebration()
            Text(title).font(.dsH3).foregroundStyle(Color.dsText).multilineTextAlignment(.center)
            if let message { Text(message).dsMutedSmall().multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Altyazı plakası ve perde önizlemesi

/// Altyazı plakası: her temada aynı koyu yarı saydam plaka, sıcak beyaz yarı kalın yazı, konuşan adı renkli.
struct DSSubtitlePlate: View {
    var speaker: String?
    let line: String
    var speakerColor: Color = .dsAmber
    var size: CGFloat = 17

    var body: some View {
        (Text(verbatim: speaker.map { $0 + " " } ?? "").foregroundColor(speakerColor).fontWeight(.bold)
            + Text(verbatim: line).foregroundColor(.dsSubtitleText))
            .font(.system(size: size, weight: .semibold))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.space("s"))
            .padding(.vertical, DS.space("unitHint"))
            .background(Color.dsSubtitlePlate, in: RoundedRectangle(cornerRadius: DS.radius("small"), style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
    }
}

/// Perde (oyun görüntüsü/TV önizlemesi): 16:9, 20 köşe, sahne (görüntü yoksa sıcak sahne degradesi), üstte durağan
/// projeksiyon ışığı, isteğe bağlı kesikli amber "Okunan Alan", altta altyazı plakası. `overlay` sağ üst haplar için.
struct DSPerdePreview<Overlay: View>: View {
    var image: Image?
    var showArea = false
    var speaker: String?
    var line: String?
    var speakerColor: Color = .dsAmber
    var textSize: CGFloat = 15
    @ViewBuilder var overlay: Overlay

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("preview"), style: .continuous)
        Color(red: 0.043, green: 0.043, blue: 0.051)
            .aspectRatio(16 / 9, contentMode: .fit)
            // Yığında sıkıştırılmasın: genişliğe göre 16:9 yükseklik.
            .fixedSize(horizontal: false, vertical: true)
            .overlay { stage }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.06)))
    }

    private var stage: some View {
        ZStack {
            if let image {
                image.resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
            } else {
                DSPerdeScene()
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .black.opacity(0.35), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geometry in
                let h = geometry.size.height
                ZStack(alignment: .bottom) {
                    if showArea {
                        RoundedRectangle(cornerRadius: DS.radius("control"), style: .continuous)
                            .strokeBorder(Color.dsAmber.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .frame(width: geometry.size.width * 0.76, height: max(h * 0.2, 40))
                            .overlay(alignment: .topLeading) {
                                Text("Area Read")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.dsOnAmber)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Color.dsAmber, in: Capsule(style: .circular))
                                    .offset(x: 10, y: -11)
                            }
                            .padding(.bottom, h * 0.05)
                    }
                    if let line {
                        DSSubtitlePlate(speaker: speaker, line: line, speakerColor: speakerColor, size: textSize)
                            .padding(.horizontal, DS.space("m"))
                            .padding(.bottom, max(h * 0.05, 8) + (showArea ? max(h * 0.2, 40) / 2 - 18 : 0))
                    }
                }
                .frame(width: geometry.size.width, height: h, alignment: .bottom)
            }
            VStack {
                HStack {
                    Spacer()
                    overlay
                }
                Spacer()
            }
            .padding(DS.space("s"))
        }
    }
}

extension DSPerdePreview where Overlay == EmptyView {
    init(image: Image? = nil, showArea: Bool = false, speaker: String? = nil, line: String? = nil,
         speakerColor: Color = .dsAmber, textSize: CGFloat = 15) {
        self.init(image: image, showArea: showArea, speaker: speaker, line: line, speakerColor: speakerColor, textSize: textSize) {
            EmptyView()
        }
    }
}

/// Görüntü gelmeden önceki sahne: özgün, soyut sinematik manzara (telifli görsel yok, tamamıyla çizim). Alacakaranlık
/// göğü, ufukta batan güneş ve göğe vuran ışık hüzmeleri, katman katman tepeler, ufka koşan yol ve ince amber ufuk
/// çizgisi. Durağan (hareket yok; hareket kapısına yük getirmez).
struct DSPerdeScene: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let horizon = h * 0.6
            let sunX = w * 0.66
            ZStack(alignment: .topLeading) {
                DSSceneSky()
                // Işık hüzmeleri: güneşten göğe yelpaze.
                DSSceneBeams(origin: CGPoint(x: sunX, y: horizon))
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.2), .clear],
                                         startPoint: .bottom, endPoint: .top))
                // Güneş ve hâlesi.
                RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.47).opacity(0.8),
                                        Color(red: 0.95, green: 0.5, blue: 0.25).opacity(0.22), .clear],
                               center: UnitPoint(x: 0.66, y: 0.6), startRadius: 0, endRadius: max(w, h) * 0.42)
                Circle().fill(Color(red: 1, green: 0.9, blue: 0.72))
                    .frame(width: h * 0.16, height: h * 0.16)
                    .position(x: sunX, y: horizon)
                // Uzak ve yakın tepeler (güneşin altını örter).
                DSSceneRidge(base: horizon, amplitude: h * 0.07, phase: 0.2, waves: 2.3)
                    .fill(Color(red: 0.231, green: 0.153, blue: 0.188).opacity(0.92))
                DSSceneRidge(base: horizon + h * 0.035, amplitude: h * 0.05, phase: 1.4, waves: 3.1)
                    .fill(Color(red: 0.122, green: 0.09, blue: 0.118))
                DSSceneGround(top: horizon + h * 0.05)
                    .fill(LinearGradient(colors: [Color(red: 0.122, green: 0.09, blue: 0.118), Color(red: 0.035, green: 0.035, blue: 0.043)],
                                         startPoint: .top, endPoint: .bottom))
                // Ufka koşan yol (perspektif) ve ince amber ufuk çizgisi.
                DSSceneRoad(vanish: CGPoint(x: sunX, y: horizon + h * 0.05))
                    .fill(LinearGradient(colors: [Color.dsAmber.opacity(0.3), Color.dsAmber.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                DSSceneGround(top: horizon + h * 0.05, height: 1)
                    .fill(LinearGradient(colors: [.clear, Color.dsAmber.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// Gök: üstte gece mavisi, ufka doğru kızıl-amber.
private struct DSSceneSky: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Color(red: 0.067, green: 0.078, blue: 0.122), location: 0),
                               .init(color: Color(red: 0.188, green: 0.149, blue: 0.188), location: 0.36),
                               .init(color: Color(red: 0.62, green: 0.329, blue: 0.231), location: 0.52),
                               .init(color: Color(red: 0.937, green: 0.612, blue: 0.29), location: 0.62),
                               .init(color: Color(red: 0.937, green: 0.612, blue: 0.29), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Güneşten yukarı açılan beş ince ışık kaması.
private struct DSSceneBeams: Shape {
    let origin: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spans: [(CGFloat, CGFloat)] = [(-0.8, -0.66), (-0.44, -0.33), (-0.1, 0.0), (0.2, 0.28), (0.52, 0.66)]
        for (from, to) in spans {
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + rect.width * from, y: rect.minY))
            path.addLine(to: CGPoint(x: origin.x + rect.width * to, y: rect.minY))
            path.closeSubpath()
        }
        return path
    }
}

/// Yumuşak dalgalı tepe sırası (iki sinüsün toplamı), alta kadar dolu.
private struct DSSceneRidge: Shape {
    let base: CGFloat
    let amplitude: CGFloat
    let phase: CGFloat
    let waves: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 48
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let wave = 0.6 * sin(t * .pi * waves + phase) + 0.4 * sin(t * .pi * waves * 2.7 + phase * 1.7)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: base - amplitude * wave - amplitude * 0.3))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Ön plan zemini (`height` verilirse yalnız o kalınlıkta bir şerit: ufuk çizgisi).
private struct DSSceneGround: Shape {
    let top: CGFloat
    var height: CGFloat?

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: top, width: rect.width, height: height ?? max(rect.maxY - top, 0)))
    }
}

/// Ufuktaki kaçış noktasına daralan yol.
private struct DSSceneRoad: Shape {
    let vanish: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: vanish.x - 1.5, y: vanish.y))
        path.addLine(to: CGPoint(x: vanish.x + 1.5, y: vanish.y))
        path.addLine(to: CGPoint(x: vanish.x + rect.width * 0.2, y: rect.maxY))
        path.addLine(to: CGPoint(x: vanish.x - rect.width * 0.34, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Oyun kapağı

/// Oyun kapağı: kapak görseli yoksa oyunun adından ÖZGÜN TİPOGRAFİK kapak (gerçek kapak/logo kullanılmaz; telif ve
/// mağaza riski). Her oyuna kararlı bir degrade (adın karmasından), çapraz ışık bandı ve oyunun kısaltması (GTA, RDR; sıra numarası yanında küçük)
/// iri, sıkı aralıklı ağır yazıyla. Küçük boyda (simge karesi, kapak yığını) yalnız kısaltma ortada okunur.
struct DSCoverArt: View {
    let seed: String
    var image: Image?

    /// (üst, alt, ışık, yazı). Son palet (gri) iPhone kapak yığınında kullanılmaz.
    static let palettes: [(Color, Color, Color, Color)] = [
        (Color(red: 0.957, green: 0.6, blue: 0.267), Color(red: 0.6, green: 0.157, blue: 0.157), Color(red: 1, green: 0.851, blue: 0.6), Color(red: 1, green: 0.957, blue: 0.886)),
        (Color(red: 0.878, green: 0.243, blue: 0.396), Color(red: 0.247, green: 0.071, blue: 0.247), Color(red: 1, green: 0.616, blue: 0.69), Color(red: 1, green: 0.925, blue: 0.937)),
        (Color(red: 0.204, green: 0.431, blue: 0.851), Color(red: 0.059, green: 0.098, blue: 0.282), Color(red: 0.592, green: 0.792, blue: 1), Color(red: 0.902, green: 0.949, blue: 1)),
        (Color(red: 0.137, green: 0.682, blue: 0.651), Color(red: 0.035, green: 0.184, blue: 0.231), Color(red: 0.588, green: 0.969, blue: 0.894), Color(red: 0.89, green: 1, blue: 0.976)),
        (Color(red: 0.537, green: 0.333, blue: 0.91), Color(red: 0.122, green: 0.075, blue: 0.29), Color(red: 0.792, green: 0.69, blue: 1), Color(red: 0.957, green: 0.937, blue: 1)),
        (Color(red: 0.961, green: 0.749, blue: 0.239), Color(red: 0.71, green: 0.31, blue: 0.075), Color(red: 1, green: 0.941, blue: 0.69), Color(red: 0.165, green: 0.086, blue: 0.035)),
        (Color(red: 0.937, green: 0.4, blue: 0.29), Color(red: 0.318, green: 0.094, blue: 0.408), Color(red: 1, green: 0.749, blue: 0.588), Color(red: 1, green: 0.937, blue: 0.91)),
        (Color(red: 0.42, green: 0.455, blue: 0.51), Color(red: 0.11, green: 0.122, blue: 0.149), Color(red: 0.8, green: 0.82, blue: 0.86), Color(red: 0.937, green: 0.945, blue: 0.957)),
    ]

    /// Kararlı karma (Swift'in hashValue'su her açılışta değişir).
    static func palette(for seed: String) -> (Color, Color, Color, Color) {
        palettes[paletteIndex(seed)]
    }

    static func paletteIndex(_ seed: String) -> Int {
        let sum = seed.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Int(sum % UInt32(palettes.count))
    }

    /// Oyunun kısaltması (yalnız harf, en çok 3): baştaki büyük harf kısaltma (GTA V → GTA), yoksa en çok üç anlamlı
    /// sözcüğün baş harfi (Grand Theft Auto VI → GTA, Red Dead Redemption 2 → RDR); tek sözcük → ilk iki harf (Mafia → Ma).
    /// Sondaki sayı ya da Roma rakamı ayrı (`numeral`): kapakta kısaltmanın yanında küçük yazılır (V ile VI karışmaz).
    static func monogram(_ title: String) -> String {
        let words = words(title)
        guard let first = words.first else { return "?" }
        let english = Locale(identifier: "en_US")
        if (2...4).contains(first.count), first == first.uppercased(with: english), first.allSatisfy(\.isLetter), !isRoman(first) {
            return String(first.prefix(3))
        }
        let skip: Set<String> = ["the", "of", "a", "an", "and", "to", "in", "on", "for"]
        let significant = words.filter { !skip.contains($0.lowercased(with: english)) && !isNumeral($0) }
        if significant.count >= 2 {
            return significant.prefix(3).map { $0.prefix(1).uppercased(with: english) }.joined()
        }
        let word = significant.first ?? first
        return word.prefix(1).uppercased(with: english) + word.dropFirst().prefix(1).lowercased(with: english)
    }

    /// Adın sonundaki sayı ya da Roma rakamı (Red Dead Redemption 2 → 2, Grand Theft Auto VI → VI); yoksa nil.
    static func numeral(_ title: String) -> String? {
        let words = words(title)
        guard words.count > 1, let last = words.last, isNumeral(last), last.count <= 4 else { return nil }
        return last
    }

    /// Kesme işaretli ekler ("Assassin's" → "s") sözcük sayılmaz.
    private static func words(_ title: String) -> [String] {
        title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count > 1 || $0.first?.isUppercase == true || $0.first?.isNumber == true }
    }

    private static func isNumeral(_ word: String) -> Bool {
        word.allSatisfy(\.isNumber) || isRoman(word)
    }

    private static func isRoman(_ word: String) -> Bool {
        !word.isEmpty && word.count <= 4 && word.allSatisfy { "IVX".contains($0) }
    }

    var body: some View {
        if let image {
            image.resizable().aspectRatio(contentMode: .fill)
        } else {
            GeometryReader { geometry in
                DSTypeCover(seed: seed, size: geometry.size)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Tipografik kapağın çizimi (DSCoverArt): degrade, köşe ışığı, çapraz bant, kısaltma.
private struct DSTypeCover: View {
    let seed: String
    let size: CGSize

    var body: some View {
        let (top, bottom, light, ink) = DSCoverArt.palette(for: seed)
        let w = size.width
        let h = size.height
        let span = max(w, h)
        let mark = DSCoverArt.monogram(seed)
        let small = min(w, h) < 72
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [top, bottom], startPoint: UnitPoint(x: 0.15, y: 0), endPoint: UnitPoint(x: 0.85, y: 1))
            RadialGradient(colors: [light.opacity(0.7), .clear], center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: span * 0.7)
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: span * 0.3, height: span * 2.2)
                .rotationEffect(.degrees(28))
                .position(x: w * 0.64, y: h * 0.4)
            if small {
                Text(verbatim: mark)
                    .font(.system(size: min(w, h) * (mark.count > 2 ? 0.34 : 0.44), weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: w, height: h)
            } else {
                // İri kısaltma üst bölgede; altında kısa çizgi. Başlık (DSGameCover) alttaki scrim'in üstünde kalır.
                let fontSize = w * (mark.count > 2 ? 0.42 : 0.56)
                VStack(alignment: .leading, spacing: fontSize * 0.1) {
                    Text(verbatim: mark)
                        .font(.system(size: fontSize, weight: .black))
                        .tracking(-fontSize * 0.03)
                        .foregroundStyle(ink.opacity(0.94))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .shadow(color: bottom.opacity(0.5), radius: w * 0.03, y: w * 0.015)
                    HStack(alignment: .center, spacing: w * 0.04) {
                        Capsule().fill(ink.opacity(0.75)).frame(width: w * 0.2, height: max(2, w * 0.02))
                        if let numeral = DSCoverArt.numeral(seed) {
                            Text(verbatim: numeral)
                                .font(.system(size: w * 0.13, weight: .heavy))
                                .foregroundStyle(ink.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, w * 0.09)
                .padding(.trailing, w * 0.06)
                .padding(.top, h * 0.1)
            }
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

/// Oyun kapağı kartı: 3:4 kapak, alttan scrim üstünde kalın beyaz başlık, sol üstte isteğe bağlı cam durum hapı. Seçili
/// ya da odaktayken amber halka, arkasında kapağın renginden durağan ışıma (bulanık kopya; yalnız bu kartta).
struct DSGameCover: View {
    let title: String
    var image: Image?
    var status: LocalizedStringKey?
    var selected = false
    var width: CGFloat = DS.size("coverWidthRail")

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("cover"), style: .continuous)
        let height = width / DS.size("coverAspect")
        ZStack(alignment: .bottomLeading) {
            DSCoverArt(seed: title, image: image)
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .dsCoverScrim, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Text(verbatim: title)
                .font(.system(size: width < 110 ? 12 : 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(alignment: .topLeading) {
            if let status { DSStatusChip(status, tone: .glass, dot: false).scaleEffect(0.85, anchor: .topLeading).padding(6) }
        }
        .overlay {
            if selected {
                shape.inset(by: -4).strokeBorder(Color.dsAmber, lineWidth: 2)
            }
        }
        .background {
            if selected {
                DSCoverArt(seed: title, image: image)
                    .frame(width: width * 0.84, height: height * 0.94)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .blur(radius: DS.effect("coverGlow", "blur", 26) * 0.7)
                    .opacity(DS.effect("coverGlow", "opacity", 0.55))
                    .offset(y: height * 0.11)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Kapak rafı: başlık (cümle düzeni) + sağda isteğe bağlı "Tümü", altında yatay kayan kapaklar (12 aralık).
struct DSCoverShelf<Content: View>: View {
    let title: LocalizedStringKey
    var showAll: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("s")) {
            HStack {
                Text(title).font(.dsCardTitle).foregroundStyle(Color.dsText).accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.space("s"))
                if let showAll {
                    Button(action: showAll) {
                        HStack(spacing: DS.space("xxs")) {
                            Text("All")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.dsRow)
                        .foregroundStyle(Color.dsAmberText)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: DS.space("s")) { content }
                    // Seçili kapağın halkası ve ışıması kırpılmasın.
                    .padding(.vertical, DS.space("s"))
                    .padding(.horizontal, DS.space("xxs"))
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: Simge karesi, TV kartı

/// Renkli simge karesi (ayar menüsü, liste satırı, TV kartı): degrade tonlu yuvarlak kare, beyaz simge (amberde koyu).
struct DSIconSquare: View {
    enum Tone { case peach, olive, teal, plum, sky, amber, gray }
    let symbol: String
    var tone: Tone = .gray
    var size: CGFloat = 32

    var body: some View {
        let (top, bottom) = colors
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tone == .amber ? Color(red: 0.114, green: 0.118, blue: 0.133) : .white)
            }
            .accessibilityHidden(true)
    }

    private var colors: (Color, Color) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        return switch tone {
        case .peach: (c(244, 162, 122), c(224, 123, 74))
        case .olive: (c(180, 190, 106), c(142, 154, 69))
        case .teal: (c(92, 194, 183), c(58, 158, 148))
        case .plum: (c(184, 146, 220), c(156, 108, 196))
        case .sky: (c(120, 174, 226), c(79, 143, 203))
        case .amber: (c(255, 203, 99), c(233, 165, 42))
        case .gray: (c(138, 141, 150), c(90, 93, 102))
        }
    }
}

/// TV kartı (seçenek): simge karesi, ad + mono ayrıntı (marka · adres), sağda durum hapı ve isteğe bağlı eylem. Her
/// zaman kıl çizgi; seçiliyken 2 pt amber kenar + amber yumuşak dolgu + ışıma, simge amber. Dokununca `action`.
struct DSTVCard<Trailing: View>: View {
    let name: String
    let detail: String
    var status: LocalizedStringKey?
    var statusTone: DSStatusChip.Tone = .ok
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false
    @Environment(\.dsMotionGate) private var gate

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let card = HStack(spacing: DS.space("s")) {
            DSIconSquare(symbol: "tv", tone: selected ? .amber : .gray, size: 36)
            VStack(alignment: .leading, spacing: DS.space("line")) {
                Text(verbatim: name).font(.dsBodyStrong).foregroundStyle(Color.dsText).lineLimit(1)
                Text(verbatim: detail).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Color.dsMuted)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status { DSStatusChip(status, tone: statusTone) }
            trailing
        }
        .padding(DS.space("s"))
        .frame(minHeight: DS.size("option"))
        .dsElevation(.card, in: shape)
        .overlay(hovering && !selected ? shape.strokeBorder(Color.dsBorderStrong) : nil)
        .dsSelectedGlow(selected, in: shape)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(DS.animation(.short, gate: gate), value: selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        if let action {
            Button(action: action) { card }.buttonStyle(DSFocusPlainStyle(cornerRadius: 18))
        } else {
            card
        }
    }
}

extension DSTVCard where Trailing == EmptyView {
    init(name: String, detail: String, status: LocalizedStringKey? = nil, statusTone: DSStatusChip.Tone = .ok, selected: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(name: name, detail: detail, status: status, statusTone: statusTone, selected: selected, action: action) { EmptyView() }
    }
}

/// Düz düğme (kart, kapak): basılınca hafif soluklaşır; klavye/kumanda odağında amber odak halkası.
struct DSFocusPlainStyle: ButtonStyle {
    var cornerRadius: CGFloat = DS.radius("tile")

    func makeBody(configuration: Configuration) -> some View {
        DSFocusPlainBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct DSFocusPlainBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .dsFocusRing(focused, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
