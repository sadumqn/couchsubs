// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import UIKit
import UserNotifications

/// "Yeni paketler ve güncellemeler" (Profil › Bildirimler): arka plandaki paket yenilemesinde yeni ya da güncellenen oyun
/// paketi inince bildirim gösterilir (Android PackNotice ile aynı kural). Bu kurulumdaki ilk paket indirmesi bildirilmez;
/// uygulama ekrandayken ("Paketleri şimdi güncelle" sonucu zaten görünür) bildirim çıkmaz. Eskiden anahtar vardı ama
/// hiçbir şey okumuyordu.
enum PackNotice {
    static let settingKey = "notifyPackUpdates"
    /// Bildirimde en çok bu kadar paket adı yazılır; fazlası "+N".
    static let maxTitles = 3
    private static let identifier = "new-packs"

    static func shouldNotify(enabled: Bool, firstCheck: Bool, downloaded: Int, appActive: Bool) -> Bool {
        enabled && !firstCheck && downloaded > 0 && !appActive
    }

    /// "GTA 6, Mafia, RDR 2 +2"
    static func titles(_ titles: [String]) -> String {
        let shown = titles.prefix(maxTitles).joined(separator: ", ")
        return titles.count > maxTitles ? "\(shown) +\(titles.count - maxTitles)" : shown
    }

    @MainActor
    static func postIfWanted(titles: [String], firstCheck: Bool, defaults: UserDefaults = .standard) {
        let enabled = defaults.object(forKey: settingKey) as? Bool ?? true
        guard shouldNotify(enabled: enabled, firstCheck: firstCheck, downloaded: titles.count,
                           appActive: UIApplication.shared.applicationState == .active) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New game packs")
        content.body = String(format: String(localized: "New or updated: %@"), Self.titles(titles))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
