// SPDX-License-Identifier: AGPL-3.0-only
// Deneme modu: konsol, hesap ve TV olmadan uygulamadaki örnek görüntülerle çeviri (App Store incelemesi de bunu kullanır).

import CouchSubsCore
import SwiftUI

/// Kurulumun ilk ekranlarında, ana ekranda ve Ayarlar'da görünen "Deneme modu" düğmesi.
struct DemoModeButton: View {
    @EnvironmentObject private var model: PhoneModel
    var kind: MobileButtonStyle.Kind = .secondary

    var body: some View {
        Button {
            Task { await model.startDemo() }
        } label: {
            Label("Try demo mode (no console needed)", systemImage: "play.rectangle")
        }
        .buttonStyle(MobileButtonStyle(kind: kind))
        .disabled(model.isStarting)
        .accessibilityIdentifier("demoModeButton")
    }
}

/// Deneme modunda çeviri ekranının üstü: "Deneme modu" rozeti, "Çık" düğmesi ve okunan örnek oyun görüntüsü.
struct DemoModeHeader: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            MobilePill(text: String(localized: "Demo mode"), kind: .accent)
            Spacer()
            Button("Exit") { model.exitDemo() }
                .buttonStyle(.mobileGhost)
                .fixedSize()
                .accessibilityIdentifier("demoModeExit")
        }
        DemoFrameTile(preview: model.framePreview)
    }
}

/// Hattın şu an okuduğu örnek kare (altyazı bölgesi kareden okunur, çeviri aşağıda görünür).
private struct DemoFrameTile: View {
    @ObservedObject var preview: PhoneFramePreview

    var body: some View {
        Tile {
            Group {
                if let image = preview.image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Mobile.Palette.surface2).aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Mobile.Radius.control))
            Text("Sample game picture: the app reads the English subtitle in it, translates it and shows it below and on the subtitle screen.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
