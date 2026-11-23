// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Foundation

/// Paket sunucusuna (server/packs) giden isteklerin imzası: paketler yalnız uygulama içinden alınsın.
/// `x-couchsubs-time` (unix saniye) ve `x-couchsubs-signature` = hex(HMAC-SHA256(sır, "GET\n<yol>\n<zaman>")).
/// Sır depoda değildir; yayın derlemesinde CI sırrı `PACKS_APP_SECRET`'tan gömülür (Info.plist `CSPacksAppSecret`).
/// Sır yoksa (yerel geliştirici derlemesi) uygulama paket indirmeyi hiç açmaz. Windows (PackSigning.cs) ve Android
/// (PackSigning.kt) aynı imzayı atar.
public enum PackSigning {
    public static let timeHeader = "x-couchsubs-time"
    public static let signatureHeader = "x-couchsubs-signature"

    public static func signature(secret: String, method: String, path: String, time: Int64) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(method)\n\(path)\n\(time)".utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// İsteğe zaman ve imza başlıklarını ekler (yol: adresin kendi yolu, ör. "/v1/packs/gta-6").
    public static func sign(_ request: inout URLRequest, secret: String, now: Date) {
        guard let url = request.url else { return }
        let time = Int64(now.timeIntervalSince1970)
        let path = url.path.isEmpty ? "/" : url.path
        request.setValue(String(time), forHTTPHeaderField: timeHeader)
        request.setValue(signature(secret: secret, method: request.httpMethod ?? "GET", path: path, time: time),
                         forHTTPHeaderField: signatureHeader)
    }

    /// Uygulama sırrı: `COUCHSUBS_PACKS_SECRET` ortam değişkeni ya da Info.plist `CSPacksAppSecret` (derleme ayarı
    /// `PACKS_APP_SECRET`). Boş ya da doldurulmamış (`$(...)`) değer yok sayılır.
    public static func configuredSecret(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        bundle: Bundle = .main) -> String? {
        let candidates = [environment["COUCHSUBS_PACKS_SECRET"], bundle.object(forInfoDictionaryKey: "CSPacksAppSecret") as? String]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, !value.hasPrefix("$(") {
                return value
            }
        }
        return nil
    }
}
