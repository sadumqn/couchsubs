// SPDX-License-Identifier: AGPL-3.0-only
// Deneme modu: konsol, hesap ve TV olmadan uygulamadaki örnek görüntülerle çeviri (App Store incelemesi de bunu kullanır).

import CouchSubsCore
import SwiftUI

/// Kurulum sihirbazının alt çubuğunda ve Ayarlar'da görünen "Deneme modu" düğmesi.
struct DemoModeButton: View {
    @EnvironmentObject private var model: AppModel
    var kind: CSButtonStyle.Kind = .secondary
    var height = "buttonLarge"

    var body: some View {
        Button {
            Task { await model.startDemo() }
        } label: {
            Label("Try demo mode (no console needed)", systemImage: "play.rectangle")
        }
        .buttonStyle(CSButtonStyle(kind: kind, height: height))
        .disabled(model.isStarting)
        .accessibilityIdentifier("demoModeButton")
    }
}

/// Ayarlar › Görüntü kaynağı: deneme modunu açar ya da kapatır.
struct DemoModeCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "Demo mode") {
            HintText(text: "Demo mode shows the whole app with sample pictures built into the app. No console, account or TV is needed.")
            HStack {
                if model.demoMode {
                    Button("Exit demo mode") { model.exitDemo() }.buttonStyle(.secondary)
                } else {
                    DemoModeButton(height: "buttonHeight")
                }
                Spacer()
            }
        }
    }
}

/// Ana pencerede deneme modunda: "Deneme modu" rozeti, "Çık" düğmesi ve okunan örnek oyun görüntüsü.
struct DemoFrameTile: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var preview: FramePreview

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            HStack {
                Pill(text: String(localized: "Demo mode"), tone: .pro)
                Spacer()
                Button("Exit") { model.exitDemo() }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("demoModeExit")
            }
            Group {
                if let image = preview.image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color.csBackground).aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .frame(maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius("inner")))
            HintText(text: "Sample game picture: the app reads the English subtitle in it, translates it and shows it below and on the subtitle screen.")
        }
        .tile()
    }
}
