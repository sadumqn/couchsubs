// SPDX-License-Identifier: AGPL-3.0-only
// "Hangi Oyunu Oynuyorsunuz?" (tuval 11): ana ekranın üstünde 560 genişlikte kart. GameChoice'un davranışı aynıdır
// (iPhone GameAsk.swift, Android GameAskCard, Windows): arama, öneriler, "Listede Yok", "Sorma"; seçilen oyunun kayıtlı
// alanları varsa "Kullanılsın mı?".

import CouchSubsCore
import SwiftUI

struct GamePickerOverlay: View {
    @ObservedObject var choice: GameChoice
    @ObservedObject var areas: GameAreas
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if choice.asking {
                Color.dsBackground.opacity(0.6)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { choice.dismiss() }
                    .transition(.opacity)
                GamePickerCard(choice: choice)
                    .transition(.opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(DS.animation(.page, reduced: reduceMotion || !model.settings.transitionAnimations), value: choice.asking)
    }
}

private struct GamePickerCard: View {
    @ObservedObject var choice: GameChoice
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        DSCard(scrolls: false) {
            DSCardHeader("Game being played")
            Text("Which Game Are You Playing?").font(.dsH2)
            TextField("Search Games", text: $query)
                .textFieldStyle(DSTextFieldStyle())
                .focused($focused)
                .onSubmit { if !typed.isEmpty { choice.choose(typed) } }
            // Kapak rafı (Perde): öneriler 3:4 kapak; paketi olan ya da son oynanan cam hapla, seçili oyun amber halka +
            // kapak ışımasıyla.
            DSCoverShelf(title: "Suggestions") {
                ForEach(suggestions, id: \.self) { name in
                    Button { choice.choose(name) } label: {
                        DSGameCover(title: name, status: hasPack(name) ? "Pack Available" : name == choice.lastPlayed ? "Last Played" : nil,
                                    selected: GameName.key(name) == GameName.key(choice.game?.name ?? ""), width: 112)
                    }
                    .buttonStyle(DSFocusPlainStyle(cornerRadius: DS.radius("cover")))
                    .accessibilityLabel(Text(verbatim: name))
                }
            }
            Text("Lines not in a pack go to the shared pool with the game's name, so a ready translation for that game arrives sooner.").dsMuted()
            HStack(spacing: DS.space("xs")) {
                Button("Not in the List") { if !typed.isEmpty { choice.choose(typed) } else { focused = true } }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
                    .help(Text(typed.isEmpty ? "" : String(format: String(localized: "Not listed: use “%@”"), typed)))
                Button("Don't Ask") { choice.dismiss() }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
            }
        }
        .frame(width: 560)
        .dsElevation(.raised, in: RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
        .onAppear { focused = true }
        .onExitCommand { choice.dismiss() }
    }

    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suggestions: [String] { choice.suggestions(query).prefix(4).map { $0 } }

    private func hasPack(_ name: String) -> Bool {
        let key = GameName.key(name)
        return GameCatalog.packShelf(model.installedPacks).contains { item in item.titles.contains { GameName.key($0) == key } }
    }

    /// Kapak görseli yokken oyunun adından türeyen sabit, sakin bir renk.
    static func cover(_ name: String) -> Color {
        let palette: [Color] = [Color(red: 0.784, green: 0.42, blue: 0.29), Color(red: 0.541, green: 0.231, blue: 0.184),
                                Color(red: 0.239, green: 0.29, blue: 0.361), Color(red: 0.353, green: 0.42, blue: 0.29),
                                Color(red: 0.31, green: 0.353, blue: 0.275), Color(red: 0.42, green: 0.36, blue: 0.5)]
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}
