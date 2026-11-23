// SPDX-License-Identifier: AGPL-3.0-only
// "Hangi oyunu oynuyorsunuz?" kartı ve "Oynanan oyun: X · Değiştir" satırı (Android'deki GameAskCard ile aynı metin ve
// davranış; bkz. CouchSubsCore GameChoice).

import CouchSubsCore
import SwiftUI

/// Oyun paketle tanınmadıysa çeviri başladıktan iki dakika sonra çıkan küçük kart: arama, öneriler, "Listede yok" ve
/// "Sorma". Seçim bu oturumda ve aynı PS5'te bir sonraki oturumda (ilk öneri) hatırlanır.
struct GameAskTile: View {
    @ObservedObject var choice: GameChoice
    @State private var query = ""

    var body: some View {
        Tile {
            HStack(alignment: .firstTextBaseline) {
                Text("Which game are you playing?").font(Mobile.TypeScale.headline)
                Spacer(minLength: Mobile.Space.inline)
                Button("Don't Ask") { choice.dismiss() }
                    .font(Mobile.TypeScale.caption)
                    .foregroundStyle(Mobile.Palette.secondary)
            }
            Text("Lines that are not in a pack go to the shared pool with the game's name, so its ready translation comes sooner.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search games", text: $query)
                .textFieldStyle(MobileFieldStyle())
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { if !typed.isEmpty { choice.choose(typed) } }
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, name in
                    if index > 0 { RowDivider() }
                    Button { choice.choose(name) } label: {
                        HStack {
                            Text(verbatim: name).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.text)
                            Spacer(minLength: Mobile.Space.inline)
                            if name == choice.lastPlayed {
                                Text("Last played").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                            }
                        }
                        .padding(.vertical, Mobile.Space.gap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !typed.isEmpty, !suggestions.contains(where: { GameName.key($0) == GameName.key(typed) }) {
                Button(String(format: String(localized: "Not listed: use “%@”"), typed)) { choice.choose(typed) }
                    .buttonStyle(.mobileSecondary)
            }
        }
    }

    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suggestions: [String] { choice.suggestions(query).prefix(5).map { $0 } }
}

/// Çeviri ekranında: kart açıksa kart, değilse "Oynanan oyun" satırı.
struct GameSection: View {
    @ObservedObject var choice: GameChoice
    @ObservedObject var areas: GameAreas

    var body: some View {
        if choice.asking {
            GameAskTile(choice: choice)
        } else {
            PlayedGameRow(choice: choice)
            GameAreasRow(areas: areas)
        }
    }
}

/// Oyunun kayıtlı alanları: uygulandıysa "X için kayıtlı alanlar kullanılıyor · Geri al"; oyun yalnız paketten
/// tanındıysa "X için kayıtlı alanlar var. Kullanılsın mı? · Kullan / Hayır" (Mac, Windows ve Android ile aynı).
struct GameAreasRow: View {
    @ObservedObject var areas: GameAreas
    /// Ayarlar değişince (profil uygulandı ya da bırakıldı) satır yenilenir.
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        if let offered = areas.offeredGame {
            Tile {
                text(String(format: String(localized: "Saved areas for %@ are available. Use them?"), offered))
                HStack(spacing: Mobile.Space.gap) {
                    Button("Use") { areas.useOffered() }.buttonStyle(.mobileSecondary)
                    Button("No") { areas.declineOffered() }.buttonStyle(.mobileSecondary)
                }
            }
        } else if model.settings.activeAreaProfile != nil, let active = areas.activeGame {
            Tile {
                HStack(spacing: Mobile.Space.gap) {
                    text(String(format: String(localized: "Using the saved areas for %@."), active))
                    Spacer(minLength: Mobile.Space.inline)
                    Button("Undo") { areas.undo() }
                        .font(Mobile.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(Mobile.Palette.accentText)
                }
            }
        }
    }

    private func text(_ value: String) -> some View {
        Text(verbatim: value).font(Mobile.TypeScale.body).fixedSize(horizontal: false, vertical: true)
    }
}

/// Çeviri ekranındaki "Oynanan oyun" satırı; "Değiştir" kartı açar.
struct PlayedGameRow: View {
    @ObservedObject var choice: GameChoice

    var body: some View {
        Tile {
            HStack(spacing: Mobile.Space.gap) {
                MobileTileIcon(symbol: "gamecontroller")
                VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                    Text("Played game").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Text(verbatim: choice.game?.name ?? String(localized: "Not known"))
                        .font(Mobile.TypeScale.headline).lineLimit(1)
                }
                Spacer(minLength: Mobile.Space.inline)
                if !choice.asking {
                    Button(choice.game == nil ? LocalizedStringKey("Choose") : LocalizedStringKey("Change")) { choice.ask() }
                        .font(Mobile.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(Mobile.Palette.accentText)
                }
            }
        }
    }
}
