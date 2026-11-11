// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Gizli olmayan ama depoda durmayan ayarlar. Değerler `Config/Secrets.xcconfig`'ten (gitignore'da) Info.plist'e girer;
/// dosya yoksa boş kalır ve ilgili özellik kapanır (bkz. docs/ios-plan.md, "Sahibinin vermesi gerekenler").
enum AppConfig {
    private static func value(_ key: String) -> String? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    /// Firebase: GoogleService-Info.plist uygulamaya kopyalandıysa (derleme adımı, dosya varsa).
    static var hasFirebase: Bool { Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil }

    /// RevenueCat'in Apple için genel SDK anahtarı ("appl_...").
    static var revenueCatAPIKey: String? { value("CSRevenueCatAPIKey") }

    static var facebookAppID: String? { value("FacebookAppID") }
    static var facebookClientToken: String? { value("FacebookClientToken") }

    /// Paket sunucusu (Cloudflare Worker, server/packs).
    static var packsBaseURL: URL? { value("CSPacksBaseURL").flatMap(URL.init(string:)) }

    /// Hata ayıklama: paketler sunucu yerine uygulamayla gelen örneklerden (CouchSubsCore'un packs klasörü) okunur ve
    /// abonelik denetimi atlanır. Yalnız Debug derlemesinde, ortam değişkeniyle: COUCHSUBS_BUNDLED_PACKS=1.
    static var useBundledPacks: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["COUCHSUBS_BUNDLED_PACKS"] == "1"
        #else
        false
        #endif
    }

    static let termsURL = URL(string: "https://github.com/yorulmazsinan/couchsubs/blob/main/docs/kosullar.md")!
    static let privacyURL = URL(string: "https://github.com/yorulmazsinan/couchsubs/blob/main/PRIVACY.md")!
}
