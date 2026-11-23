// SPDX-License-Identifier: AGPL-3.0-only
// Mac ve iPhone'un ortak ayar değerleri: hız ön ayarları, altyazı renk listeleri, açılış sesi (iPhone project.yml bu dosyayı
// da derler; Android ve Windows aynı değerleri kullanır).

import AVFoundation
import CouchSubsCore
import SwiftUI

/// Hızlı / Dengeli / Doğru: bozuk ve yarım okunan satır beklemelerinin hazır değerleri (Gelişmiş'teki kaydırıcılarla aynı
/// iki ayar; Windows aynı değerleri kullanır, METINLER.md).
enum TranslationPace: Hashable, CaseIterable {
    case fast, balanced, accurate

    var waits: (misread: Int, partial: Int) {
        switch self {
        case .fast: (400, 0)
        case .balanced: (SubtitlePipeline.packWaitMs, SubtitlePipeline.cleanWaitMs)
        case .accurate: (1000, 800)
        }
    }

    static func of(_ settings: UserSettings) -> TranslationPace? {
        allCases.first { $0.waits.misread == settings.misreadWaitMs && $0.waits.partial == settings.partialWaitMs }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .fast: "Subtitles arrive as fast as possible; you may rarely see half a sentence."
        case .balanced: "Recommended for most games. Speed and accuracy balanced."
        case .accurate: "Translated once the sentence is complete; arrives about half a second later."
        }
    }
}

/// Tuvaldeki renk listeleri (Windows aynı değerleri kullanır).
enum SubtitlePalette {
    struct Swatch: Hashable {
        /// Katalog anahtarı (İngilizce).
        let name: String
        let hex: String?

        static func == (lhs: Swatch, rhs: Swatch) -> Bool { lhs.hex == rhs.hex }
        func hash(into hasher: inout Hasher) { hasher.combine(hex) }
    }

    static let backgrounds: [Swatch] = [
        Swatch(name: "Black", hex: "#101014"), Swatch(name: "Navy", hex: "#0E1A30"), Swatch(name: "Dark Gray", hex: "#2B2D33"),
        Swatch(name: "Brown", hex: "#2A1F14"), Swatch(name: "White", hex: "#FFFFFF"), Swatch(name: "Cream", hex: "#F3EEE4"),
        Swatch(name: "No Background", hex: nil),
    ]
    static let texts: [Swatch] = [
        Swatch(name: "White", hex: "#FFFFFF"), Swatch(name: "Cream", hex: "#F3EEE4"), Swatch(name: "Yellow", hex: "#FFE066"),
        Swatch(name: "Light Blue", hex: "#BFE3FF"), Swatch(name: "Black", hex: "#111114"), Swatch(name: "Navy", hex: "#0E1A30"),
        Swatch(name: "Dark Gray", hex: "#2B2D33"),
    ]
    static let names: [Swatch] = [
        Swatch(name: "Amber", hex: "#F5B83D"), Swatch(name: "Turquoise", hex: "#4FD1C5"), Swatch(name: "Pink", hex: "#FF8FAB"),
        Swatch(name: "Purple", hex: "#B794F6"), Swatch(name: "Green", hex: "#68D391"), Swatch(name: "Orange", hex: "#F6874F"),
        Swatch(name: "Red", hex: "#F56565"), Swatch(name: "Blue", hex: "#63B3ED"),
    ]
    /// Koyuluk: Açık / Orta / Koyu (Koyu tam örter, İngilizce altyazı görünmez).
    static let darkness: [Int] = [45, 75, 100]

    static func color(_ hex: String?) -> Color? {
        guard let hex, let (r, g, b, a) = DSTokens.rgba(hex) else { return nil }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Yeni kaydırıcı (16–50) ile TV'nin yazı boyu (1920'de 16–90 piksel) arasında doğrusal eşleme; eski büyük boylar kaybolmaz.
    static func display(_ fontSize: Int) -> Int { Int((16 + Double(min(max(fontSize, 16), 90) - 16) * 34 / 74).rounded()) }
    static func fontSize(_ display: Int) -> Int { Int((16 + Double(min(max(display, 16), 50) - 16) * 74 / 34).rounded()) }

    /// Seçili yazı rengi (eski kayıtta textHex yok: beyaz ya da sarı).
    static func textHex(_ style: SubtitleStyle) -> String { style.textHex ?? (style.textColor == .yellow ? "#FFE066" : "#FFFFFF") }

    /// Yarı saydam zemin TV görüntüsüyle karışır: kontrast karışık renge göre (WCAG 4.5).
    static func lowContrast(_ style: SubtitleStyle) -> Bool {
        let scene = (109.0 / 255, 106.0 / 255, 93.0 / 255)
        let alpha = Double(max(0, min(100, style.background))) / 100
        let bg = DSTokens.rgba(style.backgroundColor) ?? (0, 0, 0, 1)
        let mixed = (bg.0 * alpha + scene.0 * (1 - alpha), bg.1 * alpha + scene.1 * (1 - alpha), bg.2 * alpha + scene.2 * (1 - alpha))
        let text = DSTokens.rgba(textHex(style)) ?? (1, 1, 1, 1)
        func lum(_ c: (Double, Double, Double)) -> Double {
            func l(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * l(c.0) + 0.7152 * l(c.1) + 0.0722 * l(c.2)
        }
        let (x, y) = (lum((text.0, text.1, text.2)), lum(mixed))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05) < 4.5
    }
}

/// Önizlemedeki örnek satırlar (tuvaldeki gibi).
enum SubtitleSample {
    static let lines: [(who: String, text: String)] = [
        ("Jason", "Tamam. Gidelim."), ("Lucia", "Yakınımda kal. Bunu birlikte yapacağız."), ("Cal", "Bir sürü silah sesi duyuyorum!"),
    ]
}

/// Açılış sesi: iki notalı kısa, yumuşak bir çan (2,4 sn; dosya yok, sesi uygulama üretir). Yalnız ilk kurulumun
/// açılış adımında ve Ayarlar › Temel › Açılış Sesi açıkken çalar.
@MainActor
final class StartupChime {
    static let shared = StartupChime()
    private var engine: AVAudioEngine?

    func play() {
        stop()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let frames = AVAudioFrameCount(rate * 3.4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        Self.render(into: data, count: Int(frames), rate: rate)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return }
        player.scheduleBuffer(buffer)
        player.play()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
    }

    /// Tuvaldeki açılış sesi (Main.dc.html): 0–0,85 sn yükselen hava (bant geçiren gürültü 250 → 3200 Hz), 0,78 sn derin
    /// vuruş (140 → 42 Hz), 0,80 ve 0,94 sn iki parlak tık (1318,5 / 1760 Hz), 1,15 sn'de yavaş sönen sıcak akor.
    private static func render(into data: UnsafeMutablePointer<Float>, count: Int, rate: Double) {
        var noiseState: (low: Double, band: Double) = (0, 0)
        var seed: UInt32 = 0x2545F491
        var kickPhase = 0.0
        var chordLow = [Double](repeating: 0, count: 5)
        let chord: [Double] = [110, 164.81, 220, 277.18, 329.63]
        func ramp(_ t: Double, _ a: Double, _ b: Double, from v0: Double, to v1: Double) -> Double {
            // Üstel geçiş (Web Audio exponentialRampToValueAtTime gibi).
            guard t > a else { return v0 }
            guard t < b else { return v1 }
            return v0 * pow(v1 / v0, (t - a) / (b - a))
        }
        for frame in 0..<count {
            let t = Double(frame) / rate - 0.05
            var sample = 0.0
            // 1) Hava
            if t >= 0, t < 0.9 {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let noise = Double(seed) / Double(UInt32.max) * 2 - 1
                let frequency = ramp(t, 0, 0.72, from: 250, to: 3200)
                let f = 2 * sin(.pi * frequency / rate)
                let high = noise - noiseState.low - noiseState.band / 1.2
                noiseState.band += f * high
                noiseState.low += f * noiseState.band
                let gain = t < 0.6 ? ramp(t, 0, 0.6, from: 0.0001, to: 0.35) : ramp(t, 0.6, 0.85, from: 0.35, to: 0.0001)
                sample += noiseState.band * gain
            }
            // 2) Vuruş
            if t >= 0.78, t < 1.6 {
                let frequency = ramp(t, 0.78, 1.1, from: 140, to: 42)
                kickPhase += 2 * .pi * frequency / rate
                let gain = t < 0.79 ? ramp(t, 0.78, 0.79, from: 0.0001, to: 0.9) : ramp(t, 0.79, 1.5, from: 0.9, to: 0.0001)
                sample += sin(kickPhase) * gain
            }
            // 3) Tıklar (üçgen dalga)
            for (start, frequency) in [(0.80, 1318.5), (0.94, 1760.0)] where t >= start && t < start + 0.4 {
                let local = t - start
                let phase = (local * frequency).truncatingRemainder(dividingBy: 1)
                let triangle = 4 * abs(phase - 0.5) - 1
                let gain = local < 0.01 ? ramp(local, 0, 0.01, from: 0.0001, to: 0.22) : ramp(local, 0.01, 0.35, from: 0.22, to: 0.0001)
                sample += triangle * gain
            }
            // 4) Akor (ilk ikisi testere dişi, alçak geçiren 400 → 1800 Hz)
            if t >= 1.15, t < 3.3 {
                let cutoff = 400 + 1400 * min(1, max(0, (t - 1.15) / 0.45))
                let alpha = 1 - exp(-2 * .pi * cutoff / rate)
                for (index, base) in chord.enumerated() {
                    let frequency = base * pow(2, (index % 2 == 0 ? -6.0 : 6.0) / 1200)
                    let local = t - 1.15
                    let phase = (local * frequency).truncatingRemainder(dividingBy: 1)
                    let wave = index < 2 ? 2 * phase - 1 : sin(2 * .pi * phase)
                    chordLow[index] += alpha * (wave - chordLow[index])
                    let peak = index < 2 ? 0.08 : 0.12
                    let gain = t < 1.3 ? ramp(t, 1.15, 1.3, from: 0.0001, to: peak) : ramp(t, 1.3, 3.2, from: peak, to: 0.0001)
                    sample += chordLow[index] * gain
                }
            }
            // Sıkıştırıcının yerine yumuşak sınırlama.
            data[frame] = Float(tanh(sample * 0.9))
        }
    }
}
