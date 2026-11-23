// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// GitHub #478: TV'de 5555 kapalıyken Android TV kurulumu kablosuz hata ayıklamaya yönlendirmeli (Android'deki AdbModeTest).
final class AdbModeTests: XCTestCase {
    func testClosedLegacyPortSelectsWireless() {
        XCTAssertTrue(AdbMode.prefersWireless(legacyAdbReachable: false))
        XCTAssertFalse(AdbMode.prefersWireless(legacyAdbReachable: true))
    }

    func testUnreachableOnNetworkModeOffersWireless() {
        XCTAssertTrue(AdbMode.offersWireless(wireless: false, error: .unreachable))
        XCTAssertFalse(AdbMode.offersWireless(wireless: true, error: .unreachable))
        XCTAssertFalse(AdbMode.offersWireless(wireless: false, error: .notApproved))
        XCTAssertFalse(AdbMode.offersWireless(wireless: false, error: nil))
    }

    func testSwitchingKeepsOnlyTheHost() {
        XCTAssertEqual(AdbMode.hostOnly("192.168.1.40:5555"), "192.168.1.40")
        XCTAssertEqual(AdbMode.hostOnly(" 192.168.1.40 "), "192.168.1.40")
        XCTAssertEqual(AdbMode.hostOnly("tv.local:37000"), "tv.local")
    }
}
