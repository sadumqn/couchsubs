// SPDX-License-Identifier: AGPL-3.0-only
// Geliştirici imzası: ana ekranın, Profil'in ve Ayarlar'ın en altında, içerik bittikten sonra (Android'de
// DeveloperSignature ile aynı). Soluk "Geliştirici" yazısı, altında ondan biraz büyük Enmera logosu; logoya dokununca
// enmera.com.tr sistem tarayıcısında açılır.

import SwiftUI

struct DeveloperSignature: View {
    static let url = URL(string: "https://enmera.com.tr")!
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Mobile.Space.hair) {
            Text("Developer")
                .font(Mobile.TypeScale.caption)
                .foregroundStyle(Mobile.Palette.tertiary)
            Button { openURL(Self.url) } label: {
                // Logo görünüm temasına göre (asset katalogunda açık: siyah, koyu: beyaz).
                Image("EnmeraLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 20)
                    .opacity(0.85)
                    .padding(.vertical, Mobile.Space.gap)
                    .padding(.horizontal, Mobile.Space.tile)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Mobile.Space.screen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Developer: Enmera"))
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { openURL(Self.url) }
    }
}
