// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// "Yeni paketler ve güncellemeler": ilk indirme ve ekrandayken bildirim yok (Android PackNotice ile aynı kural).
final class PackNoticeTests: XCTestCase {
    func testOnlyLaterBackgroundDownloadsAreAnnounced() {
        XCTAssertTrue(PackNotice.shouldNotify(enabled: true, firstCheck: false, downloaded: 1, appActive: false))
        XCTAssertFalse(PackNotice.shouldNotify(enabled: true, firstCheck: true, downloaded: 4, appActive: false))
        XCTAssertFalse(PackNotice.shouldNotify(enabled: false, firstCheck: false, downloaded: 1, appActive: false))
        XCTAssertFalse(PackNotice.shouldNotify(enabled: true, firstCheck: false, downloaded: 1, appActive: true))
        XCTAssertFalse(PackNotice.shouldNotify(enabled: true, firstCheck: false, downloaded: 0, appActive: false))
        XCTAssertEqual(PackNotice.titles(["A", "B", "C", "D", "E"]), "A, B, C +2")
        XCTAssertEqual(PackNotice.titles(["GTA 6"]), "GTA 6")
    }
}
