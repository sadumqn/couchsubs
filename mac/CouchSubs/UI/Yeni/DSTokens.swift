// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

// design/yeni-arayuz/tasarim.json'un okunuşu; Mac ve iPhone aynı dosyayı derler (couchsubs-ios/project.yml). Dosya v2'de
// (Perde) renk, yükselti, efekt ve hareket belirteçleri ekledi; okuma hoşgörülüdür: bölümlerdeki sayı olmayan değerler
// (açıklama metinleri, eski/yeni sürüm farkları) atlanır, eksik yeni anahtar varsayılanına düşer. Windows aynı dosyayı
// kendi okuyucusuyla okur (Palette.cs; o da sayı olmayanları atlar).

struct DSTokens: Decodable {
    struct ColorPair: Decodable {
        let light: String
        let dark: String
    }

    struct FontToken: Decodable {
        let size: Double
        let weight: String
        let tracking: Double?
        let design: String?
    }

    /// Süreler milisaniye; eğriler cubic-bezier'in dört değeri.
    struct Motion {
        let short: Double
        let medium: Double
        let page: Double
        let reduced: Double
        let enter: [Double]
        let exit: [Double]
        let adRotate: Double
        /// Perde: kutlama (600), canlı nabız (1600), ortam (24000), liste girişi aralığı (60).
        let celebrate: Double
        let livePulse: Double
        let ambient: Double
        let listStagger: Double
        /// Yaylı aşma eğrisi (0.34, 1.56, 0.64, 1): başarı tiki.
        let spring: [Double]
    }

    let version: Int
    /// "dark" (Perde) ya da "light"; kullanıcının Görünüm ayarı yoksa uygulanan.
    let defaultTheme: String
    let color: [String: ColorPair]
    let font: [String: FontToken]
    let mutedTracking: Double
    let space: [String: Double]
    let radius: [String: Double]
    let size: [String: Double]
    let motion: Motion
    /// effect › ad › sayısal alanlar (ör. coverGlow.blur 26, sheen.period 1800, ambientBlobs.maxFps 15).
    let effect: [String: [String: Double]]

    private enum Key: String, CodingKey {
        case version, defaultTheme, color, font, mutedTracking, space, radius, size, motion, effect
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Key.self)
        version = (try? root.decode(Int.self, forKey: .version)) ?? 1
        defaultTheme = (try? root.decode(String.self, forKey: .defaultTheme)) ?? "dark"
        color = try root.decode([String: ColorPair].self, forKey: .color)
        let fonts = try root.decode([String: JSONValue].self, forKey: .font)
        font = fonts.compactMapValues { $0.font }
        mutedTracking = try root.decode(Double.self, forKey: .mutedTracking)
        space = try root.decode([String: JSONValue].self, forKey: .space).compactMapValues(\.number)
        radius = try root.decode([String: JSONValue].self, forKey: .radius).compactMapValues(\.number)
        size = try root.decode([String: JSONValue].self, forKey: .size).compactMapValues(\.number)
        let m = try root.decode([String: JSONValue].self, forKey: .motion)
        func ms(_ name: String, _ fallback: Double) -> Double { m[name]?.number ?? fallback }
        func curve(_ name: String, _ fallback: [Double]) -> [Double] {
            let values = m[name]?.array?.compactMap(\.number) ?? []
            return values.count == 4 ? values : fallback
        }
        motion = Motion(short: ms("short", 150), medium: ms("medium", 250), page: ms("page", 350), reduced: ms("reduced", 100),
                        enter: curve("enter", [0.05, 0.7, 0.1, 1]), exit: curve("exit", [0.3, 0, 0.8, 0.15]),
                        adRotate: ms("adRotate", 6000), celebrate: ms("celebrate", 600), livePulse: ms("livePulse", 1600),
                        ambient: ms("ambient", 24000), listStagger: ms("listStagger", 60), spring: curve("spring", [0.34, 1.56, 0.64, 1]))
        let effects = (try? root.decode([String: JSONValue].self, forKey: .effect)) ?? [:]
        effect = effects.compactMapValues { $0.object?.compactMapValues(\.number) }
    }

    /// "#RRGGBB" ya da "#RRGGBBAA" → 0–1 aralığında kırmızı, yeşil, mavi, saydamlık.
    static func rgba(_ hex: String) -> (Double, Double, Double, Double)? {
        guard hex.first == "#", hex.count == 7 || hex.count == 9, let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        if hex.count == 7 {
            return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255, 1)
        }
        return (Double(value >> 24 & 0xFF) / 255, Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// WCAG kontrast oranı. Saydam renkler önce altlarındaki zemine (`over`, yoksa `background`) karıştırılır: ör. kıl
    /// çizgi ya da yumuşak tonlu zemin üstündeki yazı gerçekte görüldüğü renkle ölçülür.
    static func contrast(_ foreground: String, _ background: String, over base: String? = nil) -> Double {
        func blend(_ top: (Double, Double, Double, Double), _ under: (Double, Double, Double)) -> (Double, Double, Double) {
            (top.0 * top.3 + under.0 * (1 - top.3), top.1 * top.3 + under.1 * (1 - top.3), top.2 * top.3 + under.2 * (1 - top.3))
        }
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func channel(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        let under = base.flatMap(rgba).map { ($0.0, $0.1, $0.2) } ?? (1, 1, 1)
        guard let back = rgba(background), let front = rgba(foreground) else { return 0 }
        let backColor = blend(back, under)
        let a = luminance(blend(front, backColor)), b = luminance(backColor)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// tasarim.json'daki herhangi bir değer (hoşgörülü okuma için).
private enum JSONValue: Decodable {
    case number(Double), string(String), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var array: [JSONValue]? { if case let .array(value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case let .object(value) = self { value } else { nil } }
    var string: String? { if case let .string(value) = self { value } else { nil } }

    var font: DSTokens.FontToken? {
        guard let fields = object, let size = fields["size"]?.number, let weight = fields["weight"]?.string else { return nil }
        return DSTokens.FontToken(size: size, weight: weight, tracking: fields["tracking"]?.number, design: fields["design"]?.string)
    }
}
