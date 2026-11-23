// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

final class LGSessionRenewalTests: XCTestCase {
    func testRenewalThrottleIsPerHostAndStillSkipsRepeatedChecks() {
        var renewedAt: [String: Date] = [:]
        var renewedHosts: [String] = []
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        func renew(_ host: String, at now: Date) -> Int? {
            let key = LGSessionRenewalPolicy.storageKey(host)
            return LGSessionRenewalPolicy.renewIfDue(
                now: now,
                lastRenewedAt: renewedAt[key],
                saveRenewedAt: { renewedAt[key] = $0 },
                renew: { renewedHosts.append(host); return 1000 }
            )
        }

        XCTAssertEqual(renew("192.168.1.10", at: t0), 1000)
        XCTAssertEqual(renew("192.168.1.20", at: t0.addingTimeInterval(3600)), 1000)
        XCTAssertNil(renew("192.168.1.20", at: t0.addingTimeInterval(7200)))

        XCTAssertEqual(renewedHosts, ["192.168.1.10", "192.168.1.20"])
        XCTAssertEqual(renewedAt[LGSessionRenewalPolicy.storageKey("192.168.1.10")], t0)
        XCTAssertEqual(renewedAt[LGSessionRenewalPolicy.storageKey("192.168.1.20")], t0.addingTimeInterval(3600))
    }

    func testStorageKeyNormalizesHostWhitespaceAndCase() {
        XCTAssertEqual(LGSessionRenewalPolicy.storageKey("tv.example"), LGSessionRenewalPolicy.storageKey(" TV.Example "))
    }
}
