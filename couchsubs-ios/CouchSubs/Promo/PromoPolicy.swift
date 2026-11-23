// SPDX-License-Identifier: AGPL-3.0-only
// Kendi ürünlerimizin tanıtımı (house ad): sitedeki promo.json'daki popup, günde en çok bir kez, yalnız boştaki ana
// ekranda. Reklam SDK'sı, reklam kimliği (IDFA) ya da izleme yok; yalnız görsel ve bağlantı. Android'deki Promo.kt ile birebir.

import Foundation

/// promo.json'daki popup (biçim: site/public/promo.json).
struct PromoPopup: Equatable {
    var id: String
    var active: Bool
    var image: String
    var link: String
    var alt: String
    var everyHours: Int
    var targets: Set<String>
    /// Uygulamayla gelen açılır reklam (design/yeni-arayuz/reklamlar.json › popups; Mac ve Windows'ta gösterilenin aynısı):
    /// promo.json'a ulaşılamazsa kullanılır, `image` uygulamadaki reklam/ klasöründeki dosyanın adıdır.
    var bundled = false
}

/// Şu anki ekran: popup yalnız ana ekranda ve kullanıcı boştayken açılır.
struct PromoMoment: Equatable {
    /// Ana ekran en üstte (Ayarlar, Profil, eşleme, TV kurulumu gibi bir ekran açık değil).
    var onHome: Bool
    /// Altyazı/çeviri oturumu çalışıyor ya da konsola bağlanılıyor.
    var sessionActive: Bool
    var demo: Bool
    /// Karşılama ya da kurulum adımları sürüyor.
    var onboarding: Bool
    /// Ana ekranın ilk açılış turu görünüyor.
    var tour: Bool
    /// Uygulama ön plana geleli geçen süre: popup girişten `PromoPolicy.showDelay` sonra açılır.
    var inApp: TimeInterval
}

/// Son gösterim (popup kimliği başına; yeni kimlik hiç gösterilmemiş sayılır).
struct PromoRecord: Equatable {
    var id: String?
    var shownAt: Date?
}

enum PromoPolicy {
    static let platform = "ios"
    static let defaultEveryHours = 24
    /// Uygulamaya girdikten bu kadar sonra (kullanıcı boştaysa) açılır.
    static let showDelay: TimeInterval = 10
    static let configURL = URL(string: "https://couchsubs.enmeraapps.com/promo.json")!
    /// promo.json ve görsel için üst sınırlar: yavaş ağda uygulamayı bekletmez, büyük dosya inmez.
    static let timeout: TimeInterval = 5
    static let maxConfigBytes = 64 * 1024
    static let maxImageBytes = 2 * 1024 * 1024
    /// Uygulama açık kaldıkça promo.json en çok bu kadar sıklıkla yeniden çekilir (soğuk açılışta her zaman).
    static let refetchInterval: TimeInterval = 24 * 60 * 60

    /// promo.json'dan mobil popup ("popup"; sitenin "sitePopup" alanı okunmaz); yoksa ya da bozuksa nil.
    static func parse(_ data: Data) -> PromoPopup? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let popup = root["popup"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String { ((popup[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let hours = (popup["everyHours"] as? NSNumber)?.intValue ?? defaultEveryHours
        let targets = (popup["targets"] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces).lowercased() }
        return PromoPopup(id: text("id"), active: (popup["active"] as? Bool) ?? false, image: text("image"),
                          link: text("link"), alt: text("alt"), everyHours: hours, targets: Set(targets))
    }

    /// Uygulamayla gelen reklamlar.json'daki ilk açılır reklam (Mac ve Windows'un okuduğu dosya; günde bir, her platformda).
    /// Görsel adı boşsa ya da bağlantı https değilse nil: yer tutucu açılmaz.
    static func bundled(_ data: Data) -> PromoPopup? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let popup = (root["popups"] as? [[String: Any]])?.first else { return nil }
        func text(_ key: String) -> String { ((popup[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let image = text("image"), link = text("link")
        guard !image.isEmpty, !image.contains("/"), httpsURL(link) != nil else { return nil }
        return PromoPopup(id: text("id"), active: true, image: image, link: link, alt: text("alt"),
                          everyHours: defaultEveryHours, targets: [platform], bundled: true)
    }

    /// Görsel yalnız https, bağlantı http/https; başka şema (tel:, javascript:, uygulama adresi) açılmaz.
    static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Popup açık, bu platform hedefte ve son gösterimden `everyHours` saat geçtiyse true (ekrandan bağımsız).
    static func due(_ popup: PromoPopup?, record: PromoRecord, now: Date, platform: String = platform) -> Bool {
        guard let popup, popup.active, !popup.id.isEmpty, popup.targets.contains(platform),
              popup.bundled || httpsURL(popup.image) != nil, webURL(popup.link) != nil else { return false }
        guard record.id == popup.id, let shownAt = record.shownAt else { return true }
        let hours = popup.everyHours > 0 ? popup.everyHours : defaultEveryHours
        // Saat geri alındıysa (gösterim gelecekte görünüyor) yeniden gösterilir; sonsuza dek susmaz.
        let elapsed = now.timeIntervalSince(shownAt)
        return elapsed < 0 || elapsed >= TimeInterval(hours) * 60 * 60
    }

    /// Popup'ın şu an açılabileceği an: girişten 10 sn sonra, yalnız ana ekranda, oturum, deneme, kurulum ve tur yokken.
    static func idle(_ moment: PromoMoment) -> Bool {
        moment.onHome && !moment.sessionActive && !moment.demo && !moment.onboarding && !moment.tour
            && moment.inApp >= showDelay
    }

    static func shouldShow(_ popup: PromoPopup?, record: PromoRecord, now: Date, moment: PromoMoment,
                           platform: String = platform) -> Bool {
        idle(moment) && due(popup, record: record, now: now, platform: platform)
    }
}
