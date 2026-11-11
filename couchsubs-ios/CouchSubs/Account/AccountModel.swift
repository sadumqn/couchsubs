// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation
import Observation

/// Hesap (Firebase), abonelik (RevenueCat) ve paket indirme durumu. Ücretsiz motor, DeepL ve kendi yapay zekâ anahtarları
/// hesapsız da çalışır; oyun paketleri `packs` aboneliği ister ve sunucudan indirilir.
@MainActor
@Observable
final class AccountModel {
    private(set) var user: AccountUser?
    /// `packs` aboneliği açık (ya da hata ayıklamada uygulamayla gelen örnek paketler kullanılıyor).
    private(set) var isSubscribed = false
    private(set) var offers: [PlanOffer] = []
    private(set) var loadingOffers = false
    private(set) var packStatus: PackStatus = .idle
    private(set) var status: SubscriptionStatus?
    /// Aboneliğin değişmesi okuma hattına iletilir (paketler açılır/kapanır).
    @ObservationIgnored var onPacksChanged: ((Bool) -> Void)?

    enum PackStatus: Equatable {
        case idle, downloading, ready(Int), failed(String)
    }

    let accounts: AccountService
    let subscriptions: SubscriptionService
    let analytics: AnalyticsLogging
    private let packStore: PackStore?
    private let library: GamePackLibrary
    private let bundledPacks: Bool
    private let defaults: UserDefaults

    init(accounts: AccountService, subscriptions: SubscriptionService, analytics: AnalyticsLogging, packStore: PackStore?,
         library: GamePackLibrary, bundledPacks: Bool = AppConfig.useBundledPacks, defaults: UserDefaults = .standard) {
        self.accounts = accounts
        self.subscriptions = subscriptions
        self.analytics = analytics
        self.packStore = packStore
        self.library = library
        self.bundledPacks = bundledPacks
        self.defaults = defaults
        user = accounts.user
        isSubscribed = bundledPacks
        accounts.onChange = { [weak self] user in self?.userChanged(user) }
        subscriptions.onEntitlementChange = { [weak self] active in self?.entitlementChanged(active) }
    }

    /// Açılışta: abonelik durumu ve (haftada bir) paket yenilemesi.
    func start() async {
        await subscriptions.identify(user?.uid)
        entitlementChanged(await subscriptions.isEntitled())
    }

    /// Paketler okuma hattında kullanılabilir mi: abonelik açık.
    var packsUnlocked: Bool { isSubscribed }

    private func userChanged(_ user: AccountUser?) {
        let previous = self.user
        self.user = user
        guard previous?.uid != user?.uid else { return }
        Task {
            await subscriptions.identify(user?.uid)
            entitlementChanged(await subscriptions.isEntitled())
        }
    }

    func refreshStatus() async {
        status = await subscriptions.status()
    }

    /// Profil düğmesindeki baş harfler.
    var initials: String {
        let source = user?.name?.isEmpty == false ? user!.name! : user?.email ?? ""
        let words = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." }).prefix(2)
        return words.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    func entitlementChanged(_ active: Bool) {
        let unlocked = active || bundledPacks
        let changed = unlocked != isSubscribed
        isSubscribed = unlocked
        if changed { onPacksChanged?(unlocked) }
        if unlocked { Task { await refreshPacks(force: false) } }
    }

    /// Abonelikte paketleri indirir (haftalık; `force` ile hemen). Abonelik yoksa bir şey yapmaz.
    func refreshPacks(force: Bool) async {
        guard isSubscribed, !bundledPacks, let packStore else { return }
        packStatus = .downloading
        do {
            let downloaded = try await packStore.refresh(force: force)
            if downloaded > 0 { library.reload() }
            packStatus = .ready(library.packs.count)
            onPacksChanged?(true)
        } catch let failure as PackStore.Failure {
            packStatus = .failed(Self.describe(failure))
        } catch {
            packStatus = .failed(error.localizedDescription)
        }
    }

    static func describe(_ failure: PackStore.Failure) -> String {
        switch failure {
        case .notSignedIn: String(localized: "Sign in to download the game packs.")
        case .notSubscribed: String(localized: "Your subscription is not active.")
        case .network: String(localized: "No internet connection. Try again.")
        case .badChecksum, .badResponse, .server: String(localized: "The game packs could not be downloaded. Try again later.")
        }
    }

    // MARK: - Ödeme ekranı

    func loadOffers() async {
        guard subscriptions.isAvailable else { return }
        loadingOffers = true
        offers = (try? await subscriptions.offers()) ?? []
        loadingOffers = false
    }

    func purchase(_ offer: PlanOffer) async throws {
        if try await subscriptions.purchase(offer) {
            analytics.log(.purchase(productId: offer.id, price: nil, currency: nil))
            entitlementChanged(true)
        }
    }

    func restore() async throws -> Bool {
        let active = try await subscriptions.restore()
        entitlementChanged(active)
        return active
    }

    // MARK: - Hesap

    func signOut() async throws {
        try accounts.signOut()
        await packStore?.removeAll()
        library.reload()
    }

    /// Firebase kullanıcısını siler; ardından cihazdaki her şey (Anahtarlık, ayarlar, paketler, önbellekler) silinir.
    func deleteAccount(wipe: () -> Void) async throws {
        try await accounts.deleteAccount()
        await packStore?.removeAll()
        library.reload()
        wipe()
    }

    // MARK: - Tanıtım turu

    static let tourKey = "coachTourDone"
    var tourDone: Bool {
        get { access(keyPath: \.tourDone); return defaults.bool(forKey: Self.tourKey) }
        set { withMutation(keyPath: \.tourDone) { defaults.set(newValue, forKey: Self.tourKey) } }
    }
}
