// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import RevenueCat

/// RevenueCat ile abonelik: appUserID = Firebase UID, yetki `packs`, teklif `default` ($rc_monthly, $rc_annual).
@MainActor
final class RevenueCatSubscriptions: SubscriptionService {
    static let entitlement = "packs"
    static let offering = "default"

    var onEntitlementChange: ((Bool) -> Void)?
    private var packages: [String: Package] = [:]
    private var updates: Task<Void, Never>?

    init(apiKey: String, appUserID: String?) {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        updates = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.onEntitlementChange?(Self.isActive(info))
            }
        }
    }

    var isAvailable: Bool { true }

    static func isActive(_ info: CustomerInfo) -> Bool { info.entitlements[entitlement]?.isActive == true }

    func identify(_ uid: String?) async {
        if let uid {
            guard Purchases.shared.appUserID != uid else { return }
            _ = try? await Purchases.shared.logIn(uid)
        } else if !Purchases.shared.isAnonymous {
            _ = try? await Purchases.shared.logOut()
        }
    }

    func isEntitled() async -> Bool {
        guard let info = try? await Purchases.shared.customerInfo() else { return false }
        return Self.isActive(info)
    }

    func offers() async throws -> [PlanOffer] {
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.offering(identifier: Self.offering) ?? offerings.current else { return [] }
        var result: [PlanOffer] = []
        packages = [:]
        for (package, period) in [(offering.monthly, PlanOffer.Period.monthly), (offering.annual, .annual)] {
            guard let package else { continue }
            let product = package.storeProduct
            packages[product.productIdentifier] = package
            let perMonth = period == .annual ? product.pricePerMonth?.decimalValue : product.price
            result.append(PlanOffer(id: product.productIdentifier, period: period, price: product.localizedPriceString,
                                    pricePerMonth: period == .annual ? product.localizedPricePerMonth : nil, monthlyValue: perMonth))
        }
        return result
    }

    func purchase(_ offer: PlanOffer) async throws -> Bool {
        guard let package = packages[offer.id] else { return false }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return false }
        return Self.isActive(result.customerInfo)
    }

    func restore() async throws -> Bool {
        Self.isActive(try await Purchases.shared.restorePurchases())
    }

    func showManageSubscriptions() async {
        try? await Purchases.shared.showManageSubscriptions()
    }

    func status() async -> SubscriptionStatus? {
        guard let info = try? await Purchases.shared.customerInfo(),
              let entitlement = info.entitlements[Self.entitlement], entitlement.isActive else { return nil }
        let period: PlanOffer.Period = entitlement.productIdentifier.contains("annual") ? .annual : .monthly
        let store = entitlement.store == .appStore ? "App Store" : String(describing: entitlement.store)
        return SubscriptionStatus(productId: entitlement.productIdentifier, period: period, renewsAt: entitlement.expirationDate,
                                  willRenew: entitlement.willRenew, store: store)
    }
}
