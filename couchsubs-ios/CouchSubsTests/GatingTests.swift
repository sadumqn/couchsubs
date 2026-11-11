// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import CouchSubs

@MainActor
private final class FakeSubscriptions: SubscriptionService {
    var isAvailable = true
    var onEntitlementChange: ((Bool) -> Void)?
    var entitled = false
    var identified: [String?] = []
    var purchaseResult = true

    func identify(_ uid: String?) async { identified.append(uid) }
    func isEntitled() async -> Bool { entitled }
    func offers() async throws -> [PlanOffer] {
        [PlanOffer(id: "couchsubs_packs_monthly", period: .monthly, price: "₺399,00", pricePerMonth: nil),
         PlanOffer(id: "couchsubs_packs_annual", period: .annual, price: "₺3.588,00", pricePerMonth: "₺299,00")]
    }
    func purchase(_ offer: PlanOffer) async throws -> Bool {
        entitled = purchaseResult
        return purchaseResult
    }
    func restore() async throws -> Bool { entitled }
    func showManageSubscriptions() async {}
    func status() async -> SubscriptionStatus? { nil }
}

@MainActor
private final class FakeAccounts: AccountService {
    var isAvailable = true
    var canUseGoogle = false
    var user: AccountUser?
    var onChange: ((AccountUser?) -> Void)?
    var deleted = false

    func signIn(as uid: String) {
        user = AccountUser(uid: uid, name: nil, email: "a@b.c", providers: ["password"])
        onChange?(user)
    }
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> Bool { true }
    func signInWithGoogle() async throws -> Bool { true }
    func signIn(email: String, password: String) async throws { signIn(as: "u1") }
    func signUp(name: String, email: String, password: String) async throws { signIn(as: "u1") }
    func sendPasswordReset(email: String) async throws {}
    func updateName(_ name: String) async throws {}
    func updateEmail(_ email: String) async throws {}
    func updatePassword(_ password: String) async throws {}
    func signOut() throws {
        user = nil
        onChange?(nil)
    }
    func deleteAccount() async throws {
        deleted = true
        try signOut()
    }
    func idToken() async throws -> String? { user.map { "token-\($0.uid)" } }
}

@MainActor
private final class RecordingAnalytics: AnalyticsLogging {
    var events: [AnalyticsEvent] = []
    func log(_ event: AnalyticsEvent) { events.append(event) }
    func screen(_ name: String) {}
    func setCollection(_ enabled: Bool) {}
}

@MainActor
final class GatingTests: XCTestCase {
    private let library = GamePackLibrary(bundled: nil, user: nil)

    private func makeAccount(_ subscriptions: FakeSubscriptions, _ accounts: FakeAccounts? = nil,
                             analytics: RecordingAnalytics? = nil, bundled: Bool = false) -> AccountModel {
        AccountModel(accounts: accounts ?? FakeAccounts(), subscriptions: subscriptions, analytics: analytics ?? RecordingAnalytics(),
                     packStore: nil, library: library, bundledPacks: bundled, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testPacksStayLockedWithoutEntitlement() async {
        let subscriptions = FakeSubscriptions()
        let account = makeAccount(subscriptions)
        await account.start()
        XCTAssertFalse(account.packsUnlocked)
    }

    func testEntitlementUnlocksAndExpiryLocksPacks() async {
        let subscriptions = FakeSubscriptions()
        subscriptions.entitled = true
        let account = makeAccount(subscriptions)
        var changes: [Bool] = []
        account.onPacksChanged = { changes.append($0) }
        await account.start()
        XCTAssertTrue(account.packsUnlocked)
        // RevenueCat'ten gelen güncelleme (abonelik bitti).
        subscriptions.onEntitlementChange?(false)
        XCTAssertFalse(account.packsUnlocked)
        XCTAssertEqual(changes, [true, false])
    }

    func testPurchaseUnlocksAndIsMeasured() async throws {
        let subscriptions = FakeSubscriptions()
        let analytics = RecordingAnalytics()
        let account = makeAccount(subscriptions, analytics: analytics)
        await account.loadOffers()
        XCTAssertEqual(account.offers.map(\.period), [.monthly, .annual])
        try await account.purchase(account.offers[1])
        XCTAssertTrue(account.packsUnlocked)
        XCTAssertEqual(analytics.events, [.purchase(productId: "couchsubs_packs_annual", price: nil, currency: nil)])
    }

    func testCancelledPurchaseKeepsPacksLocked() async throws {
        let subscriptions = FakeSubscriptions()
        subscriptions.purchaseResult = false
        let account = makeAccount(subscriptions)
        await account.loadOffers()
        try await account.purchase(account.offers[0])
        XCTAssertFalse(account.packsUnlocked)
    }

    func testSubscriptionFollowsTheFirebaseUser() async throws {
        let subscriptions = FakeSubscriptions()
        let accounts = FakeAccounts()
        let account = makeAccount(subscriptions, accounts)
        await account.start()
        try await accounts.signIn(email: "a@b.c", password: "secret")
        // RevenueCat'e Firebase UID'siyle girilir (eşzamansız).
        for _ in 0..<50 where subscriptions.identified.last != "u1" { await Task.yield() }
        XCTAssertEqual(subscriptions.identified, [nil, "u1"])
        XCTAssertEqual(account.user?.uid, "u1")
    }

    func testDebugFixturesUnlockWithoutSubscription() async {
        let account = makeAccount(FakeSubscriptions(), bundled: true)
        await account.start()
        XCTAssertTrue(account.packsUnlocked)
    }

    func testDeleteAccountWipesLocalData() async throws {
        let accounts = FakeAccounts()
        accounts.signIn(as: "u1")
        let account = makeAccount(FakeSubscriptions(), accounts)
        var wiped = false
        try await account.deleteAccount { wiped = true }
        XCTAssertTrue(accounts.deleted)
        XCTAssertTrue(wiped)
        XCTAssertNil(account.user)
    }

    func testUnavailableStoreShowsComingSoon() async {
        let subscriptions = FakeSubscriptions()
        subscriptions.isAvailable = false
        let account = makeAccount(subscriptions)
        await account.loadOffers()
        XCTAssertTrue(account.offers.isEmpty)
    }

    /// Okuma hattı paketlere yalnız abonelikte bakar.
    func testPhoneModelUsesPacksOnlyWhenUnlocked() {
        let model = PhoneModel(services: LivePhoneServices(), store: EphemeralStore(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertFalse(model.packsUnlocked)
        XCTAssertFalse(model.packsActive)
        model.packsUnlocked = true
        XCTAssertTrue(model.packsActive)
        model.settings.gamePacks = false
        XCTAssertFalse(model.packsActive)
    }
}
