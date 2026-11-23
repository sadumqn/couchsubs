// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// iPhone'da bağlantı kopunca kullanıcı uygulamayı kapatıp açıyordu (TestFlight): "Yeniden bağlan" düğmesi bırakılan
/// oturumda hemen, süren denemelerde 45 sn sonra görünür (Android ReconnectOfferTest ile aynı).
final class ReconnectOfferTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testHiddenWhileStreaming() {
        var offer = ReconnectOffer()
        offer.update(live: true, now: start)
        XCTAssertFalse(offer.shows(gaveUp: false, now: start.addingTimeInterval(600)))
    }

    func testShowsAfterLongReconnecting() {
        var offer = ReconnectOffer()
        offer.update(live: false, now: start)
        // Ara durumlar (bağlanıyor ↔ koptu) süreyi baştan başlatmaz.
        offer.update(live: false, now: start.addingTimeInterval(20))
        XCTAssertFalse(offer.shows(gaveUp: false, now: start.addingTimeInterval(44)))
        XCTAssertTrue(offer.shows(gaveUp: false, now: start.addingTimeInterval(ReconnectOffer.after)))
        offer.update(live: true, now: start.addingTimeInterval(50))
        XCTAssertFalse(offer.shows(gaveUp: false, now: start.addingTimeInterval(60)))
    }

    func testShowsAtOnceWhenTheSessionGaveUp() {
        var offer = ReconnectOffer()
        offer.update(live: false, now: start)
        XCTAssertTrue(offer.shows(gaveUp: true, now: start))
    }

    func testResetRestartsTheClock() {
        var offer = ReconnectOffer()
        offer.update(live: false, now: start)
        offer.reset(now: start.addingTimeInterval(100))
        XCTAssertFalse(offer.shows(gaveUp: false, now: start.addingTimeInterval(120)))
        XCTAssertTrue(offer.shows(gaveUp: false, now: start.addingTimeInterval(145)))
        offer.reset()
        XCTAssertFalse(offer.shows(gaveUp: false, now: start.addingTimeInterval(1000)))
    }
}
