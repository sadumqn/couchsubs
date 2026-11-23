// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Çeviri sürerken ana ekranda "Yeniden bağlan" düğmesi ne zaman görünür (Android'deki ReconnectOffer ile aynı kural).
///
/// Konsol bağlantısı koparsa oturum kendiliğinden kademeli olarak yeniden bağlanır (2, 4, 8 … en çok 60 sn; bkz.
/// `ReconnectPolicy`). Ama oturum yeniden denemeyi bırakabilir (görüntü hiç gelmiyor, PS5'te Uzaktan Oynatma çöktü, Xbox
/// denemeleri bitti) ya da uzun süre bağlanamayabilir. Eskiden ekranda yalnız "Yeniden bağlanılıyor…" ya da "yeniden
/// başlatın" yazıyordu; kullanıcılar uygulamayı kapatıp açıyordu (TestFlight, iPhone: "çok kopuyor, sürekli uygulamayı
/// açıp kapatmak zorunda kalıyorum"). Düğme, bırakılan oturumda hemen, süren denemelerde `after` sonra görünür.
public struct ReconnectOffer: Equatable, Sendable {
    /// Bu kadar süredir bağlı değilse (bağlanıyor ya da kopmuş) düğme görünür.
    public static let after: TimeInterval = 45

    /// Bağlantının gittiği an; bağlıyken nil.
    public private(set) var notLiveSince: Date?

    public init() {}

    /// Oturum durumu değişti. `live`: görüntü akıyor.
    public mutating func update(live: Bool, now: Date = Date()) {
        if live {
            notLiveSince = nil
        } else if notLiveSince == nil {
            notLiveSince = now
        }
    }

    /// Çeviri durdu ya da yeni oturum açıldı: süre baştan sayılır.
    public mutating func reset(now: Date? = nil) { notLiveSince = now }

    /// `gaveUp`: oturum yeniden denemeyi bıraktı.
    public func shows(gaveUp: Bool, now: Date = Date()) -> Bool {
        if gaveUp { return true }
        guard let notLiveSince else { return false }
        return now.timeIntervalSince(notLiveSince) >= Self.after
    }
}
