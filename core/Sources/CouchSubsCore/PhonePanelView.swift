// SPDX-License-Identifier: AGPL-3.0-only

#if canImport(SwiftUI)
import SwiftUI

/// GTA 6 telefonunun yanındaki sohbet paneli (Mac yayın ve saydam penceresi, iPhone altyazı ekranı; Windows
/// PhonePanelView.cs, Android PhonePanel.kt, TV app.js `placePanel` aynı çizim): yuvarlak köşeli, yarı saydam koyu
/// kart; üstte kişinin adı, altında mesajlar sırayla (karşı taraf solda krem, oyuncu sağda amber balon, not ortada).
/// Mesajlar karta sığmazsa en eskiler üstten kırpılır, son mesajlar görünür kalır. Sağ altta sade kanepe simgesi.
public struct PhonePanelView: View {
    let panel: ScreenPhoneCard.Panel
    let fontSize: CGFloat
    let radius: CGFloat

    /// `fontSize`: mesaj yazısının boyu (nokta); `radius`: kartın köşesi.
    public init(_ panel: ScreenPhoneCard.Panel, fontSize: CGFloat, radius: CGFloat) {
        self.panel = panel
        self.fontSize = max(8, fontSize)
        self.radius = radius
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width * 0.16
            VStack(spacing: fontSize * 0.5) {
                if let title = panel.title {
                    Text(verbatim: title.translation)
                        .font(.system(size: fontSize * 1.05, weight: .bold))
                        .foregroundStyle(Self.color(title.style?.foreground, fallback: .white))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: fontSize * 0.45) {
                    // Anahtarlı liste: en eski mesaj düşünce ya da yenisi eklenince kalan balonlar yeniden yaratılmaz.
                    ForEach(Self.keys(panel.messages), id: \.self) { key in
                        message(panel.messages[key.index], side: side)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipped()
            }
            .padding(.horizontal, fontSize * 0.6)
            .padding(.top, fontSize * 0.55)
            .padding(.bottom, fontSize * 1.3)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Self.color(panel.card.style?.background, fallback: .black).opacity(ScreenPhoneCard.panelOpacity)))
            .overlay(alignment: .bottomTrailing) {
                CouchGlyph()
                    .fill(Self.color(panel.card.style?.foreground, fallback: .white).opacity(0.35))
                    .frame(width: fontSize * 0.9, height: fontSize * 0.6)
                    .padding(fontSize * 0.45)
            }
        }
        .allowsHitTesting(false)
    }

    /// Mesajın kimliği: parçası, yazısı ve aynı yazının kaçıncı tekrarı (dizin kimliğe girmez).
    struct Key: Hashable {
        let part: String, text: String, occurrence: Int
        let index: Int
        static func == (a: Key, b: Key) -> Bool { a.part == b.part && a.text == b.text && a.occurrence == b.occurrence }
        func hash(into hasher: inout Hasher) {
            hasher.combine(part)
            hasher.combine(text)
            hasher.combine(occurrence)
        }
    }

    static func keys(_ messages: [ScreenTranslation.Item]) -> [Key] {
        var seen: [String: Int] = [:]
        return messages.enumerated().map { index, item in
            let part = item.panel?.rawValue ?? ""
            let occurrence = seen[part + "\u{1F}" + item.translation, default: 0]
            seen[part + "\u{1F}" + item.translation] = occurrence + 1
            return Key(part: part, text: item.translation, occurrence: occurrence, index: index)
        }
    }

    @ViewBuilder private func message(_ item: ScreenTranslation.Item, side: CGFloat) -> some View {
        let mine = item.panel == .mine, note = item.panel == .note
        let text = Text(verbatim: item.translation)
            .font(.system(size: note ? fontSize * 0.8 : fontSize, weight: note ? .medium : .semibold))
            .foregroundStyle(Self.color(item.style?.foreground, fallback: .white))
            .multilineTextAlignment(note ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
        if note {
            text.frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 0) {
                if mine { Spacer(minLength: side) }
                text
                    .padding(.horizontal, fontSize * 0.6)
                    .padding(.vertical, fontSize * 0.32)
                    .background(RoundedRectangle(cornerRadius: fontSize * 0.75, style: .continuous)
                        .fill(Self.color(item.style?.background, fallback: .gray)))
                if !mine { Spacer(minLength: side) }
            }
        }
    }

    static func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return fallback }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Panelin sağ altındaki sade kanepe (`ScreenPhoneCard.couchGlyph`, 24×16 ızgara).
public struct CouchGlyph: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24, sy = rect.height / 16
        for part in ScreenPhoneCard.couchGlyph {
            let r = CGRect(x: rect.minX + part.x * sx, y: rect.minY + part.y * sy, width: part.width * sx, height: part.height * sy)
            path.addRoundedRect(in: r, cornerSize: CGSize(width: part.radius * sx, height: part.radius * sy))
        }
        return path
    }
}

/// Paneli karedeki yerinde çizer: `size` karenin (ya da onu gösteren alanın) boyu; yazı boyu panelin satır yüksekliğinden.
public struct PhonePanelInFrame: View {
    let panel: ScreenTranslation.Item
    let parts: ScreenPhoneCard.Panel
    let size: CGSize
    let minFont: CGFloat

    /// `minFont`: küçük ekranda (iPhone) yazı bundan küçülmez; sığmayan eski mesajlar panelde üstten kırpılır.
    public init(_ parts: ScreenPhoneCard.Panel, size: CGSize, minFont: CGFloat = 0) {
        self.parts = parts
        self.panel = parts.card
        self.size = size
        self.minFont = minFont
    }

    public var body: some View {
        let box = panel.box
        PhonePanelView(parts, fontSize: max(minFont, panel.lineHeight * size.height * 0.85),
                       radius: max(6, ScreenPhoneCard.panelRadius * size.height / 1080))
            .frame(width: max(0, box.right - box.left) * size.width, height: max(0, box.bottom - box.top) * size.height)
            .position(x: (box.left + box.right) * 0.5 * size.width, y: (box.top + box.bottom) * 0.5 * size.height)
    }
}
#endif
