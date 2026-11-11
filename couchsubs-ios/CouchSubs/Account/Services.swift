// SPDX-License-Identifier: AGPL-3.0-only
// Hesap, abonelik, ölçüm ve izin hizmetlerinin arayüzleri. Gerçekleri Firebase, RevenueCat, Meta ve Google SDK'larıyla
// (bu klasördeki diğer dosyalar); testlerde ve anahtarlar yokken sahteleri/boşları kullanılır.

import Foundation

/// Giriş yapmış kullanıcı (Firebase Auth).
struct AccountUser: Equatable, Sendable {
    var uid: String
    var name: String?
    var email: String?
    /// Giriş yolları: "apple.com", "google.com", "password".
    var providers: [String]
    var emailVerified = false

    var usesPassword: Bool { providers.contains("password") }
}

enum AccountError: LocalizedError, Equatable {
    case unavailable, wrongPassword, userNotFound, emailInUse, weakPassword, invalidEmail, requiresRecentLogin,
         network, canceled, other(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Accounts are not available yet in this version.")
        case .wrongPassword: String(localized: "The e-mail or password is wrong.")
        case .userNotFound: String(localized: "No account found with this e-mail.")
        case .emailInUse: String(localized: "This e-mail already has an account. Sign in instead.")
        case .weakPassword: String(localized: "The password must be at least 6 characters.")
        case .invalidEmail: String(localized: "Check the e-mail address.")
        case .requiresRecentLogin: String(localized: "For your security, sign in again and repeat this step.")
        case .network: String(localized: "No internet connection. Try again.")
        case .canceled: nil
        case .other(let text): text
        }
    }
}

@MainActor
protocol AccountService: AnyObject {
    /// Firebase yapılandırıldı mı (GoogleService-Info.plist uygulamada var mı).
    var isAvailable: Bool { get }
    var canUseGoogle: Bool { get }
    var user: AccountUser? { get }
    /// Giriş, çıkış ve profil değişince çağrılır.
    var onChange: ((AccountUser?) -> Void)? { get set }
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> Bool
    /// Dönen değer: yeni hesap mı (analitikte sign_up / login ayrımı için).
    func signInWithGoogle() async throws -> Bool
    func signIn(email: String, password: String) async throws
    func signUp(name: String, email: String, password: String) async throws
    func sendPasswordReset(email: String) async throws
    func updateName(_ name: String) async throws
    /// Yeni adrese doğrulama bağlantısı gider; adres bağlantıya basılınca değişir.
    func updateEmail(_ email: String) async throws
    func updatePassword(_ password: String) async throws
    func signOut() throws
    /// Firebase kullanıcısını gerçekten siler (yakın zamanda giriş ister: `requiresRecentLogin`).
    func deleteAccount() async throws
    func idToken() async throws -> String?
}

/// Abonelik seçeneği (RevenueCat paketinin fiyatı mağazadan gelir).
struct PlanOffer: Identifiable, Equatable, Sendable {
    enum Period: String, Sendable { case monthly, annual }
    let id: String
    let period: Period
    /// Mağazanın yerel biçimiyle fiyat ("₺399,99").
    let price: String
    /// Yıllıkta aylık karşılığı ("₺299,00").
    let pricePerMonth: String?
    /// Aylık karşılığın sayısı (yıllık planın tasarruf oranı için).
    var monthlyValue: Decimal? = nil

    /// Yıllığın aylığa göre tasarrufu (yüzde, yuvarlanmış); iki fiyat da bilinmiyorsa nil.
    static func savingsPercent(monthly: PlanOffer?, annual: PlanOffer?) -> Int? {
        guard let monthly = monthly?.monthlyValue, let annual = annual?.monthlyValue, monthly > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: 1 - annual / monthly).doubleValue
        return ratio > 0 ? Int((ratio * 100).rounded()) : nil
    }
}

/// Etkin aboneliğin ayrıntısı (Abonelik ekranı).
struct SubscriptionStatus: Equatable, Sendable {
    let productId: String
    let period: PlanOffer.Period
    /// Yenileme ya da bitiş tarihi.
    let renewsAt: Date?
    let willRenew: Bool
    /// "App Store" (başka mağazadan alındıysa onun adı).
    let store: String
}

@MainActor
protocol SubscriptionService: AnyObject {
    /// RevenueCat anahtarı var mı; yoksa ödeme ekranı "yakında" der.
    var isAvailable: Bool { get }
    /// `packs` aboneliği değişince çağrılır.
    var onEntitlementChange: ((Bool) -> Void)? { get set }
    /// Firebase kullanıcısıyla eşleşir (RevenueCat appUserID = Firebase UID); nil anonim.
    func identify(_ uid: String?) async
    func isEntitled() async -> Bool
    func offers() async throws -> [PlanOffer]
    /// Dönen değer: satın alma sonrası `packs` açık mı (kullanıcı vazgeçerse false).
    func purchase(_ offer: PlanOffer) async throws -> Bool
    func restore() async throws -> Bool
    func showManageSubscriptions() async
    func status() async -> SubscriptionStatus?
}

/// Ölçülen olaylar (Firebase Analytics ve Meta App Events'e aynı anda gider).
enum AnalyticsEvent: Equatable, Sendable {
    case signUp(method: String)
    case login(method: String)
    case paywallView(source: String)
    case purchase(productId: String, price: Double?, currency: String?)
    case packHit(packId: String?)
    case sessionStart(output: String)
    case sessionStop(seconds: Int)
    case tvConnected(brand: String)

    var name: String {
        switch self {
        case .signUp: "sign_up"
        case .login: "login"
        case .paywallView: "paywall_view"
        case .purchase: "purchase"
        case .packHit: "pack_hit"
        case .sessionStart: "session_start"
        case .sessionStop: "session_stop"
        case .tvConnected: "tv_connected"
        }
    }

    var parameters: [String: Sendable] {
        switch self {
        case .signUp(let method), .login(let method): ["method": method]
        case .paywallView(let source): ["source": source]
        case .purchase(let id, let price, let currency):
            ["item_id": id].merging(price.map { ["value": $0] } ?? [:]) { a, _ in a }
                .merging(currency.map { ["currency": $0] } ?? [:]) { a, _ in a }
        case .packHit(let id): id.map { ["pack_id": $0] } ?? [:]
        case .sessionStart(let output): ["output": output]
        case .sessionStop(let seconds): ["seconds": seconds]
        case .tvConnected(let brand): ["brand": brand]
        }
    }
}

@MainActor
protocol AnalyticsLogging: AnyObject {
    func log(_ event: AnalyticsEvent)
    func screen(_ name: String)
    /// Hesap bilgileri › Kullanım verisi: Analytics ve Crashlytics toplamasını açar/kapatır.
    func setCollection(_ enabled: Bool)
}

/// Hiçbir şey göndermez (testler, Firebase yapılandırılmamışken).
final class NoAnalytics: AnalyticsLogging {
    func log(_ event: AnalyticsEvent) {}
    func screen(_ name: String) {}
    func setCollection(_ enabled: Bool) {}
}

/// Firebase yokken: hesap açılamaz.
final class UnavailableAccounts: AccountService {
    var isAvailable: Bool { false }
    var canUseGoogle: Bool { false }
    var user: AccountUser? { nil }
    var onChange: ((AccountUser?) -> Void)?
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> Bool { throw AccountError.unavailable }
    func signInWithGoogle() async throws -> Bool { throw AccountError.unavailable }
    func signIn(email: String, password: String) async throws { throw AccountError.unavailable }
    func signUp(name: String, email: String, password: String) async throws { throw AccountError.unavailable }
    func sendPasswordReset(email: String) async throws { throw AccountError.unavailable }
    func updateName(_ name: String) async throws { throw AccountError.unavailable }
    func updateEmail(_ email: String) async throws { throw AccountError.unavailable }
    func updatePassword(_ password: String) async throws { throw AccountError.unavailable }
    func signOut() throws {}
    func deleteAccount() async throws { throw AccountError.unavailable }
    func idToken() async throws -> String? { nil }
}

/// RevenueCat anahtarı yokken: abonelik yok, ödeme ekranı "yakında".
final class UnavailableSubscriptions: SubscriptionService {
    var isAvailable: Bool { false }
    var onEntitlementChange: ((Bool) -> Void)?
    func identify(_ uid: String?) async {}
    func isEntitled() async -> Bool { false }
    func offers() async throws -> [PlanOffer] { [] }
    func purchase(_ offer: PlanOffer) async throws -> Bool { false }
    func restore() async throws -> Bool { false }
    func showManageSubscriptions() async {}
    func status() async -> SubscriptionStatus? { nil }
}
