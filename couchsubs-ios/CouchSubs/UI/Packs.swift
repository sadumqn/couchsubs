// SPDX-License-Identifier: AGPL-3.0-only
// Oyun paketleri (tuvaldeki Telefon · Paketler). Paketler herkese ücretsiz: uygulamayla gelir, sunucudan güncellenir.

import CouchSubsCore
import SwiftUI

struct PacksScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @EnvironmentObject private var app: AppModel
    /// "Paketleri şimdi güncelle"ye basıldı, sonuç bekleniyor: sayfa bulanıklaşır, ortada gösterge döner.
    @State private var updating = false
    @State private var result: PackUpdateAlert?
    @State private var showResult = false

    var body: some View {
        MobileScreen {
            BackHeader(title: "Game packs") {
                MobilePill(text: String(localized: "Free"))
            }
        } content: {
            Text("The pack is chosen by itself when the game opens. Lines not in the pack are translated with the engine you chose.")
                .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
            // Ayarlar › Oyun Paketleri: Mac'teki anahtarlar kartı (aynı ad, sıra ve açıklama).
            PackSettingsTile()
            Text(Self.summary(model.installedPacks) + " · " + String(localized: "offline"))
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            switch app.packStatus {
            case .downloading:
                HStack(spacing: Mobile.Space.inline) {
                    DSBarsLoader()
                    Text("Updating the packs…").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
            case .failed(let reason): MobileNote(text: reason, tone: Mobile.Palette.secondary)
            default: EmptyView()
            }
            if !model.installedPacks.isEmpty {
                Text("Tap a game to turn its pack on or off.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
            // Perde kapak rafı: yatay kayan 3:4 kapaklar; oynanan paketin kapağı amber halka ve kendi renginden ışıma.
            if !model.installedPacks.isEmpty {
                DSCoverShelf(title: "Installed packs") {
                    ForEach(GameCatalog.packShelf(model.installedPacks)) { pack in
                        packTile(pack)
                    }
                }
            }
            ImportedPacksSection()
            Tile {
                HStack(spacing: Mobile.Space.gap) {
                    MobileTileIcon(symbol: "arrow.down.circle")
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        Text("New games are coming").font(Mobile.TypeScale.headline)
                        Text("New packs arrive by themselves, free").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                }
            }
        } bottom: {
            Button(action: updateNow) {
                if busy { Text("Updating…") } else { Text("Update the packs now") }
            }
            .buttonStyle(.mobileSecondary)
            .disabled(busy || AppConfig.packsBaseURL == nil || AppConfig.packsSecret == nil)
        }
        .overlay {
            if updating {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    VStack(spacing: Mobile.Space.gap) {
                        DSBarsLoader(scale: 2)
                        Text("Updating the packs…").font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.text)
                    }
                    .padding(Mobile.Space.tile * 1.5)
                    .dsGlass(in: RoundedRectangle(cornerRadius: Mobile.Radius.tile, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: updating)
        .alert(result?.title ?? "", isPresented: $showResult, presenting: result) { alert in
            if alert.retry {
                Button("Try Again", action: updateNow)
                Button("Close", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(verbatim: alert.message)
        }
        .onAppear { app.analytics.screen("packs") }
    }

    /// Elle ya da açılıştaki güncelleme sürüyor.
    private var busy: Bool { updating || app.packStatus == .downloading }

    private func updateNow() {
        guard !updating else { return }
        updating = true
        Task {
            let outcome = await app.updatePacksNow()
            updating = false
            guard let outcome else { return }
            result = PackUpdateAlert(outcome, stillUsed: String(localized: "The packs on this phone are still used."))
            showResult = true
        }
    }

    /// Paket karosu: dokununca paket açılır ya da kapanır (Android ile aynı). Kapalıysa soluk ve "Kapalı"; son satırı
    /// veren paketse çerçeveli ve "Oynanıyor". Oyunun "(ek satırlar)" paketi asıl paketin karosundadır, birlikte değişir.
    private func packTile(_ pack: PackShelfItem) -> some View {
        let on = pack.packIds.allSatisfy { !model.disabledPacks.contains($0) }
        let playing = model.isRunning && model.packInUse.map { pack.titles.contains($0) } == true
        return Button {
            Haptics.selection()
            model.setPacks(pack.packIds, on: !on)
        } label: {
            VStack(alignment: .leading, spacing: Mobile.Space.titleToBody) {
                DSGameCover(title: pack.title, status: playing ? "Now playing" : on ? "Installed" : "Off", selected: playing)
                Text(Self.linesText(pack.entries)).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: DS.size("coverWidthRail"), alignment: .leading)
            .opacity(on && model.settings.gamePacks ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSFocusPlainStyle(cornerRadius: DS.radius("cover")))
        .accessibilityValue(Text(on ? "On" : "Off"))
    }

    /// "Grand Theft Auto V" → "GTA", "Mafia: The Old Country" → "MTO".
    static func code(_ title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count == 1 { return String(words[0].prefix(3)).uppercased() }
        return String(words.prefix(3).compactMap(\.first)).uppercased()
    }

    /// "190 bin satır"
    static func linesText(_ entries: Int) -> String {
        entries >= 1000 ? String(format: String(localized: "%lld thousand lines"), entries / 1000)
            : String(format: String(localized: "%lld lines"), entries)
    }

    /// "6 oyun · 517 bin satır" (oyunun ek satırlar paketi ayrı oyun sayılmaz)
    static func summary(_ packs: [GamePackLibrary.Info]) -> String {
        String(format: String(localized: "%lld games"), GameCatalog.packShelf(packs).count) + " · "
            + linesText(packs.reduce(0) { $0 + $1.entries })
    }
}
