// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Elle yazılan adresteki TV'nin türü TV'ye sorulur (Windows'taki `ManualTv` ile aynı kural). Önceden Samsung değilse
/// LG sayılıyordu: adresini yazan Android TV kullanıcısında LG eşleştirmesi deneniyor, "TV yanıt vermedi" çıkıyordu.
public enum ManualTV {
    /// Android TV / Google TV'nin açık tuttuğu portlar: ADB (5555, hata ayıklama açıksa), Google Cast (8008, 8009) ve
    /// Android TV uzaktan kumanda hizmeti (6466). Yeni LG'lerde de Google Cast olabildiği için LG'ye önce bakılır.
    public static let androidPorts: [UInt16] = [5555, 6466, 8009, 8008]

    public struct Result: Equatable, Sendable {
        public let tv: LGTV
        /// TV türünü kendisi söyledi mi? Hiçbir yoklamaya yanıt gelmediyse TV eskisi gibi LG sayılır ve kullanıcıya
        /// söylenir (webOS 3 cihaz tanımını her zaman vermiyor).
        public let recognised: Bool
    }

    /// Yoklama sonuçlarından TV: Samsung 8001'de kendini tanıtırsa Samsung; LG cihaz tanımı ya da ikinci ekran sunucusu
    /// yanıt verirse LG; Android TV portlarından biri açıksa Android TV; hiçbiri değilse (tanınmadan) LG.
    public static func classify(host: String, samsung: LGTV?, lg: LGTV?, androidPortOpen: Bool) -> Result {
        if let samsung { return Result(tv: samsung, recognised: true) }
        if let lg { return Result(tv: lg, recognised: true) }
        if androidPortOpen { return Result(tv: LGTV(name: "Android TV", host: host, brand: .androidTV), recognised: true) }
        return Result(tv: LGTV(name: "LG TV", host: host), recognised: false)
    }

    /// Adresi üç tür için aynı anda yoklar.
    public static func tv(at host: String) async -> Result {
        async let samsung = SamsungDiscovery.tv(at: host)
        async let lg = LGDiscovery.tv(at: host)
        async let android = isAndroidTV(host: host)
        return classify(host: host, samsung: await samsung, lg: await lg, androidPortOpen: await android)
    }

    static func isAndroidTV(host: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for port in androidPorts {
                group.addTask { await DevModeInstaller.isPortOpen(host: host, port: port, timeout: .milliseconds(1500)) }
            }
            for await open in group where open {
                group.cancelAll()
                return true
            }
            return false
        }
    }
}
