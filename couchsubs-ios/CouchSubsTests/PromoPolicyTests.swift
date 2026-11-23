// SPDX-License-Identifier: AGPL-3.0-only
// Android'deki PromoPolicyTest ile aynı durumlar.

import XCTest
@testable import CouchSubs

final class PromoPolicyTests: XCTestCase {
    private let hour: TimeInterval = 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let idle = PromoMoment(onHome: true, sessionActive: false, demo: false, onboarding: false, tour: false, inApp: 10)
    private let never = PromoRecord(id: nil, shownAt: nil)

    private let json = """
        {"version":1,"popup":{"id":"enmera-commerce-1","active":true,
          "image":"https://couchsubs.enmeraapps.com/promo/popup.webp",
          "imageWide":"https://couchsubs.enmeraapps.com/promo/popup-wide.webp",
          "link":"https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs&utm_medium=app&utm_campaign=popup","alt":"Enmera Commerce","everyHours":24,
          "targets":["site","ios","android"]},
         "sitePopup":{"id":"site-1","active":true,"image":"https://x/site.webp","link":"https://x","targets":["site"]},
         "sponsors":[{"name":"Enmera","logo":"https://x/logo.png","url":"https://enmera.com.tr"}]}
        """

    private func popup(_ change: (inout PromoPopup) -> Void = { _ in }) -> PromoPopup {
        var popup = PromoPolicy.parse(Data(json.utf8))!
        change(&popup)
        return popup
    }

    private func show(_ popup: PromoPopup?, _ record: PromoRecord? = nil, moment: PromoMoment? = nil, platform: String = PromoPolicy.platform) -> Bool {
        PromoPolicy.shouldShow(popup, record: record ?? never, now: now, moment: moment ?? idle, platform: platform)
    }

    func testParsesSiteFormat() {
        let popup = popup()
        XCTAssertEqual(popup.id, "enmera-commerce-1")
        XCTAssertTrue(popup.active)
        XCTAssertEqual(popup.image, "https://couchsubs.enmeraapps.com/promo/popup.webp")
        XCTAssertEqual(popup.link, "https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs&utm_medium=app&utm_campaign=popup")
        XCTAssertEqual(popup.everyHours, 24)
        XCTAssertEqual(popup.targets, ["site", "ios", "android"])
    }

    func testBrokenOrMissingPopupIsNil() {
        XCTAssertNil(PromoPolicy.parse(Data("not json".utf8)))
        XCTAssertNil(PromoPolicy.parse(Data(#"{"version":1,"sponsors":[]}"#.utf8)))
        // everyHours yoksa 24.
        XCTAssertEqual(PromoPolicy.parse(Data(#"{"popup":{"id":"a","active":true}}"#.utf8))?.everyHours, 24)
    }

    func testShowsWhenActiveTargetedAndNeverShown() {
        XCTAssertTrue(show(popup()))
    }

    func testInactiveIsNeverShown() {
        XCTAssertFalse(show(popup { $0.active = false }))
        XCTAssertFalse(show(nil))
    }

    func testPlatformMustBeTargeted() {
        let siteOnly = popup { $0.targets = ["site", "android"] }
        XCTAssertFalse(show(siteOnly))
        XCTAssertTrue(show(siteOnly, platform: "android"))
        XCTAssertFalse(show(popup { $0.targets = [] }))
    }

    func testWaitsEveryHoursPerPopupId() {
        let popup = popup()
        let shown = PromoRecord(id: "enmera-commerce-1", shownAt: now.addingTimeInterval(-23 * hour))
        XCTAssertFalse(show(popup, shown))
        XCTAssertTrue(show(popup, PromoRecord(id: shown.id, shownAt: now.addingTimeInterval(-24 * hour))))
        // Yeni kampanya (başka kimlik) beklemeden gösterilir.
        XCTAssertTrue(show(self.popup { $0.id = "enmera-commerce-2" }, shown))
        // everyHours 72: bir gün sonra henüz değil.
        XCTAssertFalse(show(self.popup { $0.everyHours = 72 }, PromoRecord(id: shown.id, shownAt: now.addingTimeInterval(-30 * hour))))
        // Geçersiz everyHours 24 sayılır.
        XCTAssertFalse(show(self.popup { $0.everyHours = 0 }, shown))
        // Saat geri alındıysa susmaz.
        XCTAssertTrue(show(popup, PromoRecord(id: shown.id, shownAt: now.addingTimeInterval(hour))))
    }

    func testNeverDuringSessionDemoOnboardingTourOrOtherScreens() {
        let popup = popup()
        var moment = idle
        moment.sessionActive = true
        XCTAssertFalse(show(popup, moment: moment))
        moment = idle
        moment.demo = true
        XCTAssertFalse(show(popup, moment: moment))
        moment = idle
        moment.onboarding = true
        XCTAssertFalse(show(popup, moment: moment))
        moment = idle
        moment.tour = true
        XCTAssertFalse(show(popup, moment: moment))
        // Uygulamaya girdikten 10 saniye geçmeden açılmaz.
        moment = idle
        moment.inApp = 9.9
        XCTAssertFalse(show(popup, moment: moment))
        // Eşleme, TV kurulumu, Ayarlar gibi ekranlar ana ekranın üstündeyken.
        moment = idle
        moment.onHome = false
        XCTAssertFalse(show(popup, moment: moment))
    }

    func testOnlyWebLinksAndHttpsImages() {
        XCTAssertFalse(show(popup { $0.image = "http://couchsubs.enmeraapps.com/p.webp" }))
        XCTAssertFalse(show(popup { $0.link = "javascript:alert(1)" }))
        XCTAssertFalse(show(popup { $0.link = "" }))
        XCTAssertFalse(show(popup { $0.id = "" }))
    }

    /// promo.json'a ulaşılamazsa Mac ve Windows'taki açılır reklam (reklamlar.json › popups) aynı kurallarla gösterilir.
    func testBundledPopupFollowsTheSameRules() throws {
        let url = try XCTUnwrap(Bundle(for: PromoController.self).url(forResource: "reklamlar", withExtension: "json"))
        let bundled = try XCTUnwrap(PromoPolicy.bundled(Data(contentsOf: url)))
        XCTAssertTrue(bundled.bundled)
        XCTAssertEqual(bundled.image, "popup-enmera.jpg")
        XCTAssertTrue(bundled.link.hasPrefix("https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs"))
        XCTAssertNotNil(Bundle(for: PromoController.self).url(forResource: bundled.image, withExtension: nil, subdirectory: "reklam"))
        XCTAssertTrue(show(bundled))
        XCTAssertFalse(show(bundled, PromoRecord(id: bundled.id, shownAt: now.addingTimeInterval(-23 * hour))))
        var moment = idle
        moment.sessionActive = true
        XCTAssertFalse(show(bundled, moment: moment))
        moment = idle
        moment.onboarding = true
        XCTAssertFalse(show(bundled, moment: moment))
        // Görsel adı ya da https bağlantısı yoksa açılır reklam yok.
        XCTAssertNil(PromoPolicy.bundled(Data(#"{"popups":[{"id":"a","image":"","link":"https://x.com"}]}"#.utf8)))
        XCTAssertNil(PromoPolicy.bundled(Data(#"{"popups":[{"id":"a","image":"a.jpg","link":"http://x.com"}]}"#.utf8)))
        XCTAssertNil(PromoPolicy.bundled(Data(#"{"popups":[]}"#.utf8)))
    }
}
