// SPDX-License-Identifier: AGPL-3.0-only
// Oyun paketleri (kilitli ve Pro) ve ödeme ekranı (tuvaldeki Telefon · Paketler, Paywall).

import CouchSubsCore
import SwiftUI

struct PacksScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var showPaywall = false
    /// Kilitliyken gösterilen oyunlar: uygulamayla gelen paketlerin adları (yalnız liste; çeviri olarak kullanılmaz).
    private let catalog = GamePackLibrary(bundled: GamePackLibrary.bundledDirectory, user: nil)
    @State private var catalogPacks: [GamePackLibrary.Info] = []

    var body: some View {
        MobileScreen {
            BackHeader(title: "Game packs") {
                if account.packsUnlocked { Pill(text: "Pro", kind: .pro) }
            }
        } content: {
            if account.packsUnlocked {
                Text("The pack is chosen by itself when the game opens. Lines not in the pack are translated with the engine you chose.")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                switch account.packStatus {
                case .downloading:
                    HStack(spacing: Mobile.Space.inline) {
                        ProgressView().tint(Mobile.Palette.pro)
                        Text("Downloading the packs…").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                case .failed(let reason): MobileNote(text: reason)
                default: EmptyView()
                }
                grid(model.installedPacks, unlocked: true)
                Tile {
                    HStack(spacing: Mobile.Space.gap) {
                        TileIcon(symbol: "sparkles")
                        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                            Text("New games are coming").font(Mobile.TypeScale.headline)
                            Text("New games come with Pro at no extra cost").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        }
                    }
                }
            } else {
                Tile(emphasis: .pro) {
                    HStack(spacing: Mobile.Space.gap) {
                        TileIcon(symbol: "lock.fill", tint: .pro)
                        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                            Text("Ready translation is in Pro").font(Mobile.TypeScale.headline)
                            Text(Self.summary(catalogPacks) + " · " + String(localized: "offline"))
                                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        }
                    }
                }
                Text("The free translation, DeepL and translation with your own key are always free.")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                grid(catalogPacks, unlocked: false)
            }
        } bottom: {
            if !account.packsUnlocked {
                Text("399 TL per month, or 299 TL per month when you buy yearly")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary).frame(maxWidth: .infinity)
                Button("See Pro") { showPaywall = true }.buttonStyle(.mobilePro)
            } else {
                Button("Update the packs now") { Task { await account.refreshPacks(force: true) } }
                    .buttonStyle(.mobileSecondary)
                    .disabled(account.packStatus == .downloading)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallScreen(source: "packs") }
        .task {
            account.analytics.screen(account.packsUnlocked ? "packs" : "packs" + "_locked")
            let catalog = self.catalog
            catalogPacks = await Task.detached(priority: .utility) { catalog.packs }.value
        }
    }

    private func grid(_ packs: [GamePackLibrary.Info], unlocked: Bool) -> some View {
        LazyVGrid(columns: WelcomeFlow.columns, spacing: Mobile.Space.gap) {
            ForEach(packs) { pack in
                Tile {
                    HStack {
                        GameMonogram(code: Self.code(pack.title))
                        Spacer()
                        if !unlocked { Image(systemName: "lock.fill").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary) }
                    }
                    Spacer(minLength: Mobile.Space.inline)
                    Text(verbatim: pack.title).font(Mobile.TypeScale.headline).lineLimit(2)
                    Text(Self.linesText(pack.entries)).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
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

    /// "6 oyun · 517 bin satır"
    static func summary(_ packs: [GamePackLibrary.Info]) -> String {
        String(format: String(localized: "%lld games"), packs.count) + " · " + linesText(packs.reduce(0) { $0 + $1.entries })
    }
}

// MARK: - Paywall

struct PaywallScreen: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    let source: String
    @State private var selected: PlanOffer.Period = .annual
    @State private var working = false
    @State private var error: String?
    @State private var needsSignIn = false

    private var monthly: PlanOffer? { account.offers.first { $0.period == .monthly } }
    private var annual: PlanOffer? { account.offers.first { $0.period == .annual } }

    var body: some View {
        MobileScreen {
            HStack {
                Pill(text: "CouchSubs Pro", kind: .pro)
                Spacer()
                IconButton(symbol: "xmark", label: "Close") { dismiss() }
            }
        } content: {
            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                Text("Without waiting, \(Text("instantly").foregroundStyle(Mobile.Palette.accent)) in Turkish")
                    .font(Mobile.TypeScale.display).tracking(-0.4)
                Text("With ready translation packs the subtitles come at the same time as the game.")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
            }
            LazyVGrid(columns: WelcomeFlow.columns, spacing: Mobile.Space.gap) {
                feature("square.stack.3d.up.fill", "6 games, 517 thousand lines")
                feature("bolt.fill", "Subtitles without delay")
                feature("wifi.slash", "Translation without internet")
                feature("sparkles", "New games included")
            }
            if account.isSubscribed {
                Pill(text: String(localized: "Your subscription is active."), kind: .ok, dot: true)
            } else if !account.subscriptions.isAvailable {
                MobileNote(text: String(localized: "Subscriptions are coming soon."), tone: Mobile.Palette.pro)
            } else if account.loadingOffers {
                ProgressView().tint(Mobile.Palette.pro).frame(maxWidth: .infinity)
            } else if account.offers.isEmpty {
                MobileNote(text: String(localized: "The prices could not be loaded. Check the internet connection and try again."))
            }
            if let annual { planTile(annual) }
            if let monthly { planTile(monthly) }
            if let error { MobileNote(text: error) }
            Text("The subscription renews automatically until you cancel it in your App Store account settings, at least 24 hours before the end of the period. Translation with the free engine, DeepL or your own AI key stays free.")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        } bottom: {
            Button {
                Task { await buy() }
            } label: {
                if working { ProgressView().tint(Mobile.Palette.onAccent) } else { Text("Go Pro") }
            }
            .buttonStyle(.mobilePro)
            .disabled(working || account.isSubscribed || offer == nil)
            VStack(spacing: Mobile.Space.hair) {
                Text("You can cancel any time.").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                HStack(spacing: Mobile.Space.inline) {
                    Button("Restore purchases") { Task { await restore() } }.disabled(working || !account.subscriptions.isAvailable)
                    Text(verbatim: "·")
                    Link("Terms", destination: AppConfig.termsURL)
                    Text(verbatim: "·")
                    Link("Privacy", destination: AppConfig.privacyURL)
                }
                .font(Mobile.TypeScale.caption)
                .tint(Mobile.Palette.accent)
                .foregroundStyle(Mobile.Palette.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $needsSignIn) { SignUpScreen(startInSignIn: false, onSkip: nil) }
        .onChange(of: account.user) { _, user in if user != nil { needsSignIn = false } }
        .task {
            account.analytics.log(.paywallView(source: source))
            account.analytics.screen("paywall")
            await account.loadOffers()
        }
    }

    private var offer: PlanOffer? { selected == .annual ? annual ?? monthly : monthly ?? annual }

    private func feature(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Tile {
            TileIcon(symbol: symbol, tint: .pro)
            Text(title).font(Mobile.TypeScale.headline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planTile(_ plan: PlanOffer) -> some View {
        let isSelected = offer?.id == plan.id
        return Button {
            selected = plan.period
        } label: {
            Tile(emphasis: isSelected ? .active : .none) {
                HStack(spacing: Mobile.Space.gap) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Mobile.Palette.accent : Mobile.Palette.secondary)
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        HStack(spacing: Mobile.Space.inline) {
                            Text(plan.period == .annual ? "Yearly" : "Monthly").font(Mobile.TypeScale.headline)
                            if plan.period == .annual, let percent = PlanOffer.savingsPercent(monthly: monthly, annual: annual) {
                                Pill(text: String(format: String(localized: "%lld%% saving"), percent), kind: .accent, compact: true)
                            }
                        }
                        Text(verbatim: plan.period == .annual
                             ? String(format: String(localized: "%@ per year"), plan.price) + (plan.pricePerMonth.map { " · " + String(format: String(localized: "%@ per month"), $0) } ?? "")
                             : String(localized: "Renews every month"))
                            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                    Spacer()
                    Text(verbatim: plan.period == .annual ? plan.pricePerMonth ?? plan.price : plan.price).font(Mobile.TypeScale.title)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func buy() async {
        guard let offer else { return }
        // RevenueCat'te kullanıcı Firebase UID'siyle tanınır; abonelik hesaba bağlansın diye önce giriş.
        guard account.user != nil || !account.accounts.isAvailable else {
            needsSignIn = true
            return
        }
        working = true
        error = nil
        do {
            try await account.purchase(offer)
            if account.isSubscribed { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }

    private func restore() async {
        working = true
        error = nil
        do {
            if try await account.restore() { dismiss() } else { error = String(localized: "No active subscription was found for this Apple ID.") }
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}
