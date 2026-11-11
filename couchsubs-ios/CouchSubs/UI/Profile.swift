// SPDX-License-Identifier: AGPL-3.0-only
// Profil, hesap bilgileri, abonelik ve ayarlar (tuvaldeki Telefon · Profil, Hesap, Abonelik, Ayarlar).

import CouchSubsCore
import SwiftUI

// MARK: - Profil

struct ProfileScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Binding var path: [Route]
    @State private var showSignIn = false
    @State private var error: String?

    var body: some View {
        MobileScreen {
            BackHeader(title: "Profile")
        } content: {
            Tile(emphasis: account.isSubscribed ? .pro : .none) {
                HStack(spacing: Mobile.Space.gap) {
                    AvatarButton(initials: account.initials, pro: account.isSubscribed) {}
                        .scaleEffect(56 / Mobile.Control.icon)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        if let user = account.user {
                            Text(verbatim: user.name?.isEmpty == false ? user.name! : user.email ?? "CouchSubs").font(Mobile.TypeScale.title).lineLimit(1)
                            if let email = user.email { Text(verbatim: email).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary) }
                        } else {
                            Text("Not signed in").font(Mobile.TypeScale.title)
                            Text("The free translation works without an account.").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if account.isSubscribed {
                    Pill(text: account.status?.period == .monthly ? String(localized: "Pro · Monthly") : String(localized: "Pro · Yearly"), kind: .pro)
                } else if account.user == nil {
                    Button("Sign in") { showSignIn = true }.buttonStyle(.mobilePrimary)
                }
            }
            LazyVGrid(columns: WelcomeFlow.columns, spacing: Mobile.Space.gap) {
                Button { path.append(.target) } label: {
                    StatTile(symbol: "tv", tint: .ok, label: "Devices", value: devicesText)
                }
                .buttonStyle(.plain)
                Button { path.append(.psn) } label: {
                    StatTile(symbol: "person.2.fill", label: "PSN account",
                             value: model.accountId == nil ? String(localized: "Not set up") : String(localized: "Signed in"))
                }
                .buttonStyle(.plain)
            }
            Tile(spacing: 0) {
                if account.user != nil {
                    NavigationLink(value: Route.account) { ListRow(symbol: "person.text.rectangle", title: "Account details") }
                    RowDivider()
                }
                NavigationLink(value: Route.subscription) {
                    ListRow(symbol: "bolt.fill", tint: .pro, title: "Subscription", detail: renewalText)
                }
                RowDivider()
                if account.user != nil {
                    NavigationLink(value: Route.account) { ListRow(symbol: "bell", title: "Notifications") }
                    RowDivider()
                }
                Link(destination: AppConfig.privacyURL) { ListRow(symbol: "hand.raised", title: "Data and privacy") }
                RowDivider()
                Link(destination: URL(string: "https://github.com/yorulmazsinan/couchsubs/issues")!) { ListRow(symbol: "questionmark.circle", title: "Help") }
            }
            .buttonStyle(.plain)
            if let error { MobileNote(text: error) }
            Text(verbatim: "CouchSubs \(AppIdentity.version) · Copyright © 2026 Sinan Yorulmaz · AGPL-3.0")
                .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary).frame(maxWidth: .infinity)
        } bottom: {
            if account.user != nil {
                Button("Sign out") {
                    Task {
                        do { try await account.signOut() } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.mobileDestructive)
            }
        }
        .sheet(isPresented: $showSignIn) { SignUpScreen(startInSignIn: true, onSkip: nil) }
        .onChange(of: account.user) { _, user in if user != nil { showSignIn = false } }
        .task {
            account.analytics.screen("profile")
            await account.refreshStatus()
        }
    }

    private var devicesText: String {
        let ps5 = model.console == nil ? 0 : 1
        let tv = model.hasTV ? 1 : 0
        return String(format: String(localized: "%lld PS5 · %lld TV"), ps5, tv)
    }

    private var renewalText: String? {
        account.status?.renewsAt.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }
    }
}

// MARK: - Hesap bilgileri

struct AccountDetailsScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var newPassword = ""
    @State private var changingPassword = false
    @State private var message: String?
    @State private var working = false
    @State private var confirmDelete = false
    @AppStorage("notifyPackUpdates") private var notifyPackUpdates = true
    @AppStorage("usageData") private var usageData = true

    var body: some View {
        @Bindable var model = model
        MobileScreen {
            BackHeader(title: "Account details")
        } content: {
            Tile {
                Text("Name").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                TextField("Name", text: $name).textFieldStyle(MobileFieldStyle()).textContentType(.name)
                Text("E-mail").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary).padding(.top, Mobile.Space.hair)
                HStack(spacing: Mobile.Space.inline) {
                    TextField("E-mail", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .disabled(account.user?.usesPassword != true)
                    if account.user?.emailVerified == true { Pill(text: String(localized: "verified"), kind: .ok, compact: true) }
                }
                .font(Mobile.TypeScale.headline.weight(.regular))
                .padding(.horizontal, Mobile.Space.tile)
                .frame(minHeight: Mobile.Control.field)
                .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.borderStrong))
                if account.user?.usesPassword == true {
                    HStack {
                        Text("Password").font(Mobile.TypeScale.headline)
                        Spacer()
                        Button("Change") { changingPassword.toggle() }.font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.accent)
                    }
                    .frame(minHeight: Mobile.Control.row)
                    if changingPassword {
                        SecureField("New password", text: $newPassword).textFieldStyle(MobileFieldStyle()).textContentType(.newPassword)
                    }
                }
            }
            Tile(spacing: 0) {
                toggleRow("Notifications", "New packs and updates", isOn: $notifyPackUpdates)
                RowDivider()
                toggleRow("Contribute to the shared pool", "English lines that are read, anonymous", isOn: $model.settings.sharePool)
                RowDivider()
                toggleRow("Usage data", "Error and usage statistics", isOn: $usageData)
            }
            Button { confirmDelete = true } label: {
                Tile {
                    HStack(spacing: Mobile.Space.gap) {
                        TileIcon(symbol: "trash", tint: .danger)
                        VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                            Text("Delete account").font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.danger)
                            Text("The subscription is cancelled separately in the store").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            if let message { Text(verbatim: message).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary) }
        } bottom: {
            Button { Task { await save() } } label: {
                if working { ProgressView().tint(Mobile.Palette.onAccent) } else { Text("Save") }
            }
            .buttonStyle(.mobilePrimary)
            .disabled(working)
        }
        .onAppear {
            name = account.user?.name ?? ""
            email = account.user?.email ?? ""
        }
        .onChange(of: usageData) { _, value in account.analytics.setCollection(value) }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    do {
                        try await account.deleteAccount { model.wipeLocalData() }
                        dismiss()
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Your account and everything CouchSubs keeps on this phone are deleted. An App Store subscription is cancelled separately in your Apple ID settings.")
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, _ caption: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                Text(title).font(Mobile.TypeScale.headline)
                Text(caption).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
        }
        .tint(Mobile.Palette.accent)
        .padding(.vertical, Mobile.Space.gap)
    }

    private func save() async {
        working = true
        message = nil
        do {
            if name != (account.user?.name ?? "") { try await account.accounts.updateName(name) }
            if email != (account.user?.email ?? ""), !email.isEmpty {
                try await account.accounts.updateEmail(email)
                message = String(localized: "We sent a confirmation link to the new e-mail.")
            }
            if changingPassword, !newPassword.isEmpty {
                try await account.accounts.updatePassword(newPassword)
                newPassword = ""
                changingPassword = false
            }
            if message == nil { dismiss() }
        } catch {
            message = error.localizedDescription
        }
        working = false
    }
}

// MARK: - Abonelik

struct SubscriptionScreen: View {
    @Environment(AccountModel.self) private var account
    @State private var showPaywall = false
    @State private var message: String?

    var body: some View {
        MobileScreen {
            BackHeader(title: "Subscription")
        } content: {
            if account.isSubscribed {
                Tile(emphasis: .pro) {
                    HStack {
                        Pill(text: String(localized: "Pro active"), kind: .pro)
                        Spacer()
                        Text(verbatim: account.status?.store ?? "App Store").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    }
                    Text(account.status?.period == .monthly ? "Monthly plan" : "Yearly plan").font(Mobile.TypeScale.title)
                    if let price = planPrice { Text(verbatim: price).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary) }
                    if let date = account.status?.renewsAt {
                        HStack {
                            Text(account.status?.willRenew == false ? "Ends" : "Renewal").font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                            Spacer()
                            Text(verbatim: date.formatted(.dateTime.day().month(.wide).year())).font(Mobile.TypeScale.headline)
                        }
                    }
                }
            } else {
                Tile(emphasis: .pro) {
                    Pill(text: String(localized: "Free"), kind: .neutral)
                    Text("Ready translation is in Pro").font(Mobile.TypeScale.title)
                    Text("The free translation, DeepL and translation with your own key are always free.")
                        .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                }
            }
            Tile(spacing: 0) {
                check("Ready translation in 6 games")
                RowDivider()
                check("New packs at no extra cost")
                RowDivider()
                check("The same account on all your devices")
            }
            if account.isSubscribed, let other = otherPlan {
                Button { Task { await switchPlan(other) } } label: {
                    Tile {
                        HStack(spacing: Mobile.Space.gap) {
                            TileIcon(symbol: "arrow.left.arrow.right")
                            VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                                Text(other.period == .monthly ? "Switch to the monthly plan" : "Switch to the yearly plan").font(Mobile.TypeScale.headline)
                                Text(verbatim: other.period == .monthly
                                     ? String(format: String(localized: "%@ per month"), other.price) + " · " + String(localized: "starts at the end of the year")
                                     : String(format: String(localized: "%@ per year"), other.price))
                                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let message { MobileNote(text: message) }
        } bottom: {
            Button("Restore purchases") {
                Task {
                    do {
                        if try await !account.restore() { message = String(localized: "No active subscription was found for this Apple ID.") }
                        await account.refreshStatus()
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.mobileGhost)
            if account.isSubscribed {
                Button("Manage in the App Store") { Task { await account.subscriptions.showManageSubscriptions() } }
                    .buttonStyle(.mobileSecondary)
                Text("Cancellation and refunds are done in App Store › Subscriptions.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary).frame(maxWidth: .infinity)
            } else {
                Button("Go Pro") { showPaywall = true }.buttonStyle(.mobilePro)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallScreen(source: "subscription") }
        .task {
            account.analytics.screen("subscription")
            await account.refreshStatus()
            await account.loadOffers()
        }
    }

    private var planPrice: String? {
        guard let status = account.status, let plan = account.offers.first(where: { $0.id == status.productId }) else { return nil }
        return plan.period == .annual
            ? String(format: String(localized: "%@ per year"), plan.price) + (plan.pricePerMonth.map { " · " + String(format: String(localized: "%@ per month"), $0) } ?? "")
            : String(format: String(localized: "%@ per month"), plan.price)
    }

    private var otherPlan: PlanOffer? {
        guard let status = account.status else { return nil }
        return account.offers.first { $0.period != status.period }
    }

    private func check(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Mobile.Space.gap) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Mobile.Palette.pro)
            Text(text).font(Mobile.TypeScale.body)
            Spacer()
        }
        .frame(minHeight: Mobile.Control.row)
    }

    private func switchPlan(_ plan: PlanOffer) async {
        do {
            try await account.purchase(plan)
            await account.refreshStatus()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Ayarlar

struct SettingsScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Binding var path: [Route]
    @State private var key = ""
    @State private var checking = false
    @State private var keyResult: String?
    @State private var showPaywall = false

    /// Segmentteki seçim: Ücretsiz, DeepL, Gemini, Diğer (OpenAI, Claude).
    private enum Choice: Hashable { case free, deepL, gemini, other }
    private static let choices: KeyValuePairs<Choice, LocalizedStringKey> = [.free: "Free", .deepL: "DeepL", .gemini: "Gemini", .other: "Other"]

    var body: some View {
        @Bindable var model = model
        MobileScreen {
            BackHeader(title: "Settings")
        } content: {
            Tile {
                Text("Translation engine").font(Mobile.TypeScale.headline)
                SegmentedTabs(options: Self.choices,
                              selection: Binding(get: { choice }, set: { setChoice($0) }))
                if choice == .other {
                    SegmentedTabs(options: [TranslationEngine.openAI: "OpenAI", .claude: "Claude"],
                                  selection: Binding(get: { model.settings.translationEngine == .claude ? .claude : .openAI },
                                                     set: { model.settings.translationEngine = $0 }))
                }
                let engine = model.settings.translationEngine
                if engine != .free {
                    HStack(spacing: Mobile.Space.inline) {
                        if model.hasKey(engine) {
                            Text(String(format: String(localized: "%@ key"), engine.displayName)).font(Mobile.TypeScale.headline.weight(.regular))
                            Spacer()
                            Pill(text: String(localized: "saved"), kind: .ok, compact: true)
                            Button { model.removeKey(engine) } label: { Image(systemName: "xmark.circle.fill") }
                                .foregroundStyle(Mobile.Palette.secondary)
                                .accessibilityLabel(Text("Remove key"))
                        } else {
                            SecureField(String(format: String(localized: "%@ key"), engine.displayName), text: $key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Save") { Task { await save(engine) } }
                                .foregroundStyle(Mobile.Palette.accent)
                                .disabled(checking || key.isEmpty)
                        }
                    }
                    .font(Mobile.TypeScale.headline.weight(.regular))
                    .padding(.horizontal, Mobile.Space.tile)
                    .frame(minHeight: Mobile.Control.field)
                    .background(Mobile.Palette.surface2, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Mobile.Radius.control).strokeBorder(Mobile.Palette.borderStrong))
                    if checking { ProgressView().tint(Mobile.Palette.accent) }
                    if let keyResult { MobileNote(text: keyResult) }
                }
                Text("In games with a ready pack this engine only translates the missing lines.")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
            Tile {
                HStack {
                    Text("Subtitle appearance").font(Mobile.TypeScale.headline)
                    Spacer()
                    Text(verbatim: "%\(percent)").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                }
                Slider(value: Binding(get: { Double(percent) }, set: { setPercent(Int($0)) }), in: 80...160, step: 10)
                    .tint(Mobile.Palette.accent)
                Text(verbatim: "Dinliyor musun beni?")
                    .font(Mobile.TypeScale.subtitle(landscape: false, scale: Double(percent) / 100))
                    .foregroundStyle(model.settings.style.textColor == .yellow ? Mobile.Palette.accent : Mobile.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack {
                    Text("Text colour").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                    Spacer()
                    ForEach([SubtitleTextColor.white, .yellow], id: \.self) { color in
                        Button { model.settings.style.textColor = color } label: {
                            Circle()
                                .fill(color == .yellow ? Mobile.Palette.accent : Mobile.Palette.text)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Mobile.Palette.accent, lineWidth: model.settings.style.textColor == color ? 2 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(color == .yellow ? "Yellow" : "White"))
                    }
                }
            }
            Tile(spacing: 0) {
                Button {
                    if account.packsUnlocked { path.append(.packs) } else { showPaywall = true }
                } label: {
                    ListRow(symbol: "bolt.fill", tint: .pro, title: "Game packs") {
                        Pill(text: "Pro", kind: .pro, compact: true)
                    }
                }
                if account.packsUnlocked {
                    Toggle(isOn: $model.settings.gamePacks) {
                        Text("Use the ready Turkish translations of game packs").font(Mobile.TypeScale.body)
                    }
                    .tint(Mobile.Palette.accent)
                    .padding(.vertical, Mobile.Space.inline)
                }
                RowDivider()
                NavigationLink(value: Route.target) { ListRow(symbol: "tv", title: "Subtitle target", detail: targetName) }
                RowDivider()
                NavigationLink(value: Route.ps5) {
                    ListRow(symbol: "gamecontroller", title: "PS5 and connection", detail: model.console?.name)
                }
                RowDivider()
                NavigationLink(value: Route.about) { ListRow(symbol: "info.circle", title: "About", detail: AppIdentity.version) }
            }
            .buttonStyle(.plain)
        } bottom: {
            Button("Send test subtitle") { model.sendTestSubtitle() }.buttonStyle(.mobileSecondary)
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallScreen(source: "settings") }
        .onAppear { account.analytics.screen("settings") }
    }

    private var choice: Choice {
        switch model.settings.translationEngine {
        case .free: .free
        case .deepL: .deepL
        case .gemini: .gemini
        case .openAI, .claude: .other
        }
    }

    private func setChoice(_ choice: Choice) {
        keyResult = nil
        key = ""
        switch choice {
        case .free: model.settings.translationEngine = .free
        case .deepL: model.settings.translationEngine = .deepL
        case .gemini: model.settings.translationEngine = .gemini
        case .other: model.settings.translationEngine = model.settings.translationEngine == .claude ? .claude : .openAI
        }
    }

    /// Yazı boyu TV'deki varsayılana (46) göre yüzde; telefon ekranı da aynı oranı kullanır.
    private var percent: Int { Int((Double(model.settings.style.fontSize) / Double(SubtitleStyle().fontSize) * 100 / 10).rounded()) * 10 }

    private func setPercent(_ value: Int) {
        model.settings.style.fontSize = Int((Double(SubtitleStyle().fontSize) * Double(value) / 100).rounded())
    }

    private var targetName: String {
        if model.settings.output == .computer { return String(localized: "This phone") }
        return model.hasTV ? model.tv?.name ?? "TV" : String(localized: "Not set up")
    }

    private func save(_ engine: TranslationEngine) async {
        checking = true
        keyResult = nil
        let accepted = await model.saveKey(key, for: engine)
        keyResult = accepted ? nil : String(localized: "The key did not work. Check it and try again.")
        if accepted { key = "" }
        checking = false
    }
}

/// Hakkında: sürüm, telif, kaynak kodu.
struct AboutScreen: View {
    var body: some View {
        MobileScreen {
            BackHeader(title: "About")
        } content: {
            Tile {
                LogoView(size: 56)
                Text(verbatim: "CouchSubs \(AppIdentity.version)").font(Mobile.TypeScale.title)
                Text(verbatim: "Copyright © 2026 Sinan Yorulmaz").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
                Text("CouchSubs is free and open source (AGPL-3.0). Remote Play uses chiaki-ng (AGPL-3.0).")
                    .font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
                Link("Source code", destination: AppIdentity.sourceURL).font(Mobile.TypeScale.headline).tint(Mobile.Palette.accent)
            }
        } bottom: {
            EmptyView()
        }
    }
}
