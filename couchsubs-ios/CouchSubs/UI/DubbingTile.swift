// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Ayarlardaki Türkçe dublaj kutusu: Mac/Windows'taki Türkçe dublaj kartıyla aynı adlar ve seçenekler (açma, sesin
/// çalacağı yer, anlatıcı/ikinci konuşan/karakter sesleri, Dinle). Ses telefonun kendi Türkçe sesidir (Windows'taki
/// "Hızlı"); indirme gerekmez. Android'de aynı kutu (DubbingTile.kt).
struct DubbingTile: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        Tile {
            Toggle(isOn: $model.settings.dubbing.enabled) {
                VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                    Text("Turkish dubbing").font(Mobile.TypeScale.headline)
                    Text("Voice the translation in Turkish").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
            }
            .tint(Mobile.Palette.accent)
            caption("In the game's audio settings, turn the dialogue (voice) volume down; keep music and effects. If the game can show speaker names in subtitles, turn them on: every character then speaks with its own voice.")
            if model.settings.dubbing.enabled {
                caption("This phone's own Turkish voice: speaks at once, nothing to download. Sounds more mechanical.")
                if !PhoneDubber.hasTurkishVoice {
                    caption("No Turkish voice is installed on this phone. Add one in Settings › Accessibility › Spoken Content › Voices › Turkish.")
                }
                Text("Play the voice on").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                SegmentedTabs(options: [DubbingOutput.tv: "TV", .computer: "This phone"], selection: $model.settings.dubbing.output)
                voiceRow(Text("Narrator and unnamed lines"), voice: $model.settings.dubbing.cast.narrator)
                voiceRow(Text("Second speaker in dialogue"), voice: $model.settings.dubbing.cast.partner)
                let names = model.settings.dubbing.cast.assignments.keys.sorted()
                if !names.isEmpty {
                    Text("Characters").font(Mobile.TypeScale.headline)
                    ForEach(names, id: \.self) { name in
                        voiceRow(Text(verbatim: Self.displayName(name)),
                                 voice: Binding(get: { model.settings.dubbing.cast.assignments[name] ?? .male1 },
                                                set: { model.assignVoice($0, to: name) }))
                    }
                }
            }
        }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text).dsMuted()
    }

    private func voiceRow(_ title: Text, voice: Binding<DubbingVoice>) -> some View {
        // Başlık üstte, altında açılır seçim ve yanında Dinle (tasarım kuralı: başlık üstte, denetim altta).
        VStack(alignment: .leading, spacing: Mobile.Space.inline) {
            title.font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.text)
            HStack(spacing: Mobile.Space.gap) {
                DSSelect(selection: voice, options: DubbingVoice.allCases.map { ($0, $0.text) })
                Button("Listen") { model.previewVoice(voice.wrappedValue) }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false))
            }
        }
    }

    /// "OLD MAN" → "Old Man" (Mac DubbingCard ile aynı).
    static func displayName(_ name: String) -> String {
        name.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
