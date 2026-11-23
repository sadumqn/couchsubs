// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// "Altyazıyı göster: TV / Bilgisayar ekranı / İkisi de / Yalnız OBS (yayın)" ve bilgisayar ekranındaki pencerenin seçenekleri.
/// Ana ekranda ve ayarlarda aynı karo kullanılır (Windows'ta da aynı düzen).
struct SubtitleOutputCard: View {
    @EnvironmentObject private var model: AppModel
    /// Ayarlarda açıklamalar da gösterilir; ana ekranda karo kısa kalır.
    var detailed = false

    var body: some View {
        Card {
            Text("Show subtitles on").font(.csCaption).foregroundStyle(Color.csSecondary)
            // Segmentli seçici bölmeleri en uzun etiket kadar eşit çizer (~3 × 127 pt) ve daralmaz; ana ekranın 380 pt'lik
            // sütununa sığmayınca kart sütundan taşıyordu. Sığmazsa aynı seçenekler yan yana radyo düğmeleriyle gösterilir.
            ViewThatFits(in: .horizontal) {
                outputPicker
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                outputPicker
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
            }
            if model.settings.output.showsOnComputer {
                if detailed {
                    HintText(text: "Subtitles appear in a window on this computer, over the game or PS Remote Play.")
                }
                ComputerScreenOptions()
                if detailed || model.settings.overlayClickThrough {
                    HintText(text: LocalizedStringKey(HotkeyText.sentence(model.settings, .clickThrough,
                        String(localized: "When on, clicks go through to the window below. Press %@ to turn it off."))))
                }
            }
            // "Yalnız OBS (yayın)": TV aranmaz, bilgisayar ekranında pencere açılmaz; altyazı yalnız OBS katmanına gider.
            if model.settings.output == .obs {
                HintText(text: "Subtitles go only to the OBS overlay. The TV is not searched for or opened, and no subtitle window opens on this computer. In OBS add a Browser source with this address (width 1920, height 1080).")
                AddressRow(address: "http://localhost:\(model.serverPort)/obs?k=\(model.subtitleAccessKey)")
                if let network = AppModel.localAddress(near: nil) {
                    HintText(text: "If OBS runs on another computer, use this address:")
                    AddressRow(address: "http://\(network):\(model.serverPort)/obs?k=\(model.subtitleAccessKey)")
                }
            }
            // Ana ekranda: altyazıyı ayrıca bir telefon ya da tablet tarayıcısında göstermek (Ayarlar'da ayrı karo).
            if !detailed {
                Button("Show on another device") { showingSecondScreen = true }
                    .buttonStyle(.secondary)
                    .popover(isPresented: $showingSecondScreen, arrowEdge: .bottom) {
                        SecondScreenPanel()
                            .padding(Theme.space("l"))
                            .frame(width: 380)
                            .environmentObject(model)
                    }
            }
        }
    }

    @State private var showingSecondScreen = false

    private var outputPicker: some View {
        Picker("Show subtitles on", selection: $model.settings.output) {
            Text(verbatim: "TV").tag(SubtitleOutput.tv)
            Text("Computer screen").tag(SubtitleOutput.computer)
            Text("Both").tag(SubtitleOutput.both)
            Text("OBS only (stream)").tag(SubtitleOutput.obs)
        }
        .labelsHidden()
    }
}

/// Bilgisayar ekranındaki altyazı penceresi: tıklamalar geçsin, pencereyi ayarla.
private struct ComputerScreenOptions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.space("m")) {
                Toggle("Clicks pass through", isOn: $model.settings.overlayClickThrough)
                    .toggleStyle(.switch)
                    .tint(Color.csAccent)
                Spacer()
                adjust
            }
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                Toggle("Clicks pass through", isOn: $model.settings.overlayClickThrough)
                    .toggleStyle(.switch)
                    .tint(Color.csAccent)
                adjust
            }
        }
    }

    private var adjust: some View {
        Button("Position the subtitles") { model.overlayAdjusting = true }
            .buttonStyle(.secondary)
            .disabled(model.overlayAdjusting)
    }
}
