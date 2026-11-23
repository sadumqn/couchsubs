// SPDX-License-Identifier: AGPL-3.0-only
// "Hangi oyunu oynuyorsunuz?" kartı ve "Oynanan oyun: X · Değiştir" satırı (iPhone'daki GameAsk.swift ve Android'deki
// GameAskCard ile aynı metin ve davranış; bkz. CouchSubsCore GameChoice).

import CouchSubsCore
import SwiftUI

/// Çeviri sürerken: kart açıksa kart, değilse "Oynanan oyun" satırı.
struct GameSection: View {
    @ObservedObject var choice: GameChoice
    @ObservedObject var areas: GameAreas

    var body: some View {
        if choice.asking {
            GameAskCard(choice: choice)
        } else {
            PlayedGameRow(choice: choice)
            GameAreasRow(areas: areas)
        }
    }
}

/// Oyunun kayıtlı alanları: uygulandıysa "X için kayıtlı alanlar kullanılıyor · Geri al"; oyun yalnız paketten
/// tanındıysa "X için kayıtlı alanlar var. Kullanılsın mı? · Kullan / Hayır" (Windows, iPhone ve Android ile aynı).
struct GameAreasRow: View {
    @ObservedObject var areas: GameAreas
    /// Ayarlar değişince (profil uygulandı ya da bırakıldı) satır yenilenir.
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let offered = areas.offeredGame {
            row(String(format: String(localized: "Saved areas for %@ are available. Use them?"), offered)) {
                Button("Use") { areas.useOffered() }.buttonStyle(.secondary)
                Button("No") { areas.declineOffered() }
                    .buttonStyle(.plain)
                    .font(.csCaption.weight(.semibold))
                    .foregroundStyle(Color.csSecondary)
            }
        } else if model.settings.activeAreaProfile != nil, let active = areas.activeGame {
            row(String(format: String(localized: "Using the saved areas for %@."), active)) {
                Button("Undo") { areas.undo() }
                    .buttonStyle(.plain)
                    .font(.csCaption.weight(.semibold))
                    .foregroundStyle(Color.csAccentText)
            }
        }
    }

    private func row<Buttons: View>(_ text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: Theme.space("m")) {
            TileIcon(symbol: "rectangle.dashed")
            Text(verbatim: text).font(.csBody).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.space("m"))
            buttons()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

/// Oyun paketle tanınmadıysa çeviri başladıktan iki dakika sonra çıkan küçük kart: arama, öneriler, "Listede yok" ve
/// "Sorma". Seçim bu oturumda ve aynı PS5'te bir sonraki oturumda (ilk öneri) hatırlanır.
private struct GameAskCard: View {
    @ObservedObject var choice: GameChoice
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            HStack(alignment: .firstTextBaseline) {
                Text("Which game are you playing?").font(.csHeadline)
                Spacer(minLength: Theme.space("m"))
                Button("Don't ask") { choice.dismiss() }
                    .buttonStyle(.plain)
                    .font(.csCaption)
                    .foregroundStyle(Color.csSecondary)
            }
            HintText(text: "Lines that are not in a pack go to the shared pool with the game's name, so its ready translation comes sooner.")
            TextField("Search games", text: $query)
                .textFieldStyle(CSTextFieldStyle())
                .onSubmit { if !typed.isEmpty { choice.choose(typed) } }
            // Öneri satırları üzerine gelince yüzey-2 zemin alır; zemin yazının iki yanına taşsın diye satır yatayda
            // içeriden, liste dışarıdan aynı boşlukla kaydırılır (yazı hizası değişmez).
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, name in
                    if index > 0 { Divider().overlay(Color.csBorder).padding(.horizontal, Theme.space("s")) }
                    Button { choice.choose(name) } label: {
                        HStack {
                            Text(verbatim: name).font(.csBody).foregroundStyle(Color.csText)
                            Spacer(minLength: Theme.space("m"))
                            if name == choice.lastPlayed {
                                Text("Last played").font(.csCaption).foregroundStyle(Color.csSecondary)
                            }
                        }
                        .padding(.horizontal, Theme.space("s"))
                        .frame(minHeight: Theme.size("rowHeight"))
                    }
                    .buttonStyle(RowButtonStyle(radius: "inner"))
                }
            }
            .padding(.horizontal, -Theme.space("s"))
            if !typed.isEmpty, !suggestions.contains(where: { GameName.key($0) == GameName.key(typed) }) {
                Button(String(format: String(localized: "Not listed: use “%@”"), typed)) { choice.choose(typed) }
                    .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }

    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suggestions: [String] { choice.suggestions(query).prefix(5).map { $0 } }
}

/// "Oynanan oyun" satırı; "Değiştir" kartı açar.
private struct PlayedGameRow: View {
    @ObservedObject var choice: GameChoice

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            TileIcon(symbol: "gamecontroller.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Played game").font(.csCaption).foregroundStyle(Color.csSecondary)
                Text(verbatim: choice.game?.name ?? String(localized: "Not known")).font(.csBody).lineLimit(1)
            }
            Spacer(minLength: Theme.space("m"))
            Button(choice.game == nil ? LocalizedStringKey("Choose") : LocalizedStringKey("Change")) { choice.ask() }
                .buttonStyle(.plain)
                .font(.csCaption.weight(.semibold))
                .foregroundStyle(Color.csAccentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}
