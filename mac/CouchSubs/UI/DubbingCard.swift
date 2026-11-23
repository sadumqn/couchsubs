// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Ayarlardaki Türkçe dublaj bölümü: açma, ses modelini indirme, çıkış, karakter sesleri.
struct DubbingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "Turkish dubbing") {
            DSSwitchRow(title: "Voice the Translation in Turkish",
                        subtitle: "In the game's audio settings, turn the dialogue (voice) volume down; keep music and effects. If the game can show speaker names in subtitles, turn them on: every character then speaks with its own voice.",
                        isOn: $model.settings.dubbing.enabled, divider: false)

            if model.settings.dubbing.enabled {
                // "Ses: Doğal / Hızlı" (Windows ile aynı): Hızlı, Mac'in kendi Türkçe sesidir; indirme gerekmez.
                DSUnit(title: "Voice", hint: model.settings.dubbing.engine == .fast
                    ? "This Mac's own Turkish voice: speaks at once, nothing to download. Sounds more mechanical."
                    : "Natural voices, downloaded once. Each line takes a moment to prepare, so the voice can come a little after the subtitle.") {
                    DSTabs(selection: $model.settings.dubbing.engine, items: [(DubbingEngine.natural, "Natural"), (.fast, "Fast")])
                }
                if model.settings.dubbing.engine == .fast, !SystemSpeech.hasTurkishVoice {
                    ErrorText(error: String(localized: "No Turkish voice is installed on this Mac. Add one in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices."))
                }
                if let progress = model.dubbingDownload, model.settings.dubbing.engine == .natural {
                    ProgressView(value: progress) {
                        Text("Downloading voices… \(Int(progress * 100))%")
                    }
                } else if !model.dubbingReady {
                    HStack(alignment: .center, spacing: DS.space("m")) {
                        Text("The voices are downloaded once (440 MB).").dsMuted(.dsBody)
                        Spacer(minLength: DS.space("s"))
                        Button("Download Voices") { Task { await model.downloadDubbingModel() } }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                            .fixedSize()
                    }
                } else {
                    DSUnit(title: "Play the Voice On") {
                        DSTabs(selection: $model.settings.dubbing.output, items: [(DubbingOutput.tv, "TV"), (.computer, "This Mac")])
                    }
                    VoiceRow(title: Text("Narrator and unnamed lines"), voice: $model.settings.dubbing.cast.narrator)
                    VoiceRow(title: Text("Second speaker in dialogue"), voice: $model.settings.dubbing.cast.partner)
                    let names = model.settings.dubbing.cast.assignments.keys.sorted()
                    if !names.isEmpty {
                        Divider().overlay(Color.csBorder)
                        Text("Characters").font(.dsCardTitle)
                        ForEach(names, id: \.self) { name in
                            VoiceRow(title: Text(verbatim: Self.displayName(name)),
                                     voice: Binding(get: { model.settings.dubbing.cast.assignments[name] ?? .male1 },
                                                    set: { model.assignVoice($0, to: name) }))
                        }
                    }
                    if model.settings.dubbing.engine == .natural {
                        HintText(text: "Voices: Pocket TTS Turkish (wite-tech, CC BY 4.0) with Kyutai's pocket-tts. The voices are synthetic, not real people.")
                    }
                }
                if let error = model.dubbingError {
                    Text(error).font(.csCallout).foregroundStyle(Color.csDanger)
                }
            }
        }
    }

    /// "OLD MAN" → "Old Man"
    static func displayName(_ name: String) -> String {
        name.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

private struct VoiceRow: View {
    @EnvironmentObject private var model: AppModel
    let title: Text
    @Binding var voice: DubbingVoice

    var body: some View {
        // Başlık üstte, seçim kutusu altta tam genişlik; Dinle kutunun yanında.
        VStack(alignment: .leading, spacing: DS.unitTitleGap) {
            title.font(.dsBodyStrong).foregroundStyle(Color.dsText)
            HStack(alignment: .center, spacing: DS.space("s")) {
                DSSelect(selection: $voice, options: DubbingVoice.allCases.map { ($0, $0.text) })
                Button("Listen") { Task { await model.previewVoice(voice) } }.buttonStyle(DSButtonStyle(kind: .secondary)).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
