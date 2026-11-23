// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Eski ortak düğme türlerinin yeni arayüzdeki karşılığı: birincil → ana (amber), ikincil → ikincil, tehlikeli → durdur
/// (kırmızı tonlu), hayalet → amber yazılı düz düğme. Ölçüler yeni dilde (48, tam yuvarlak).
struct NewLookButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: CSButtonStyle.Kind
    let fullWidth: Bool

    var body: some View {
        switch kind {
        case .primary: DSButtonStyle(kind: .primary, fullWidth: fullWidth).makeBody(configuration: configuration)
        case .secondary: DSButtonStyle(kind: .secondary, fullWidth: fullWidth).makeBody(configuration: configuration)
        case .danger: DSButtonStyle(kind: .danger, fullWidth: fullWidth).makeBody(configuration: configuration)
        case .ghost: GhostBody(configuration: configuration)
        }
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.dsButtonSecondary)
                .foregroundStyle(Color.dsAmberText)
                .frame(minHeight: DS.size("tab"))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
                .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Yeni arayüzün ortamı: gömülen eski kartlar yeni dilde çizilir, seçiciler ve kaydırıcılar amber.
    func newLook() -> some View {
        // Hareket kapısı (kökte daha önce kurulduysa o geçerli): çeviri sürerken, hareketi azaltta ya da pencere önde
        // değilken sürekli animasyonlar durur.
        dsMotionGate()
            .environment(\.csNewLook, true)
            .tint(Color.dsAmber)
            .foregroundStyle(Color.dsText)
            .font(.dsBody)
    }
}
