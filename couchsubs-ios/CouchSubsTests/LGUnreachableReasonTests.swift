// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// LG'de 9922 kapalıyken TV'nin diğer portlarına göre ne yapılacağı ayrılır (TestFlight 19–20 Kas: 14 denemede hep
/// "192.168.1.123:9922: Connection refused"; Android'deki LgUnreachableReason ile aynı kural).
final class LGUnreachableReasonTests: XCTestCase {
    func testOtherPortsTellWhyDeveloperSshIsClosed() {
        XCTAssertEqual(LGUnreachableReason.classify(keyServer: true, ssap: true), .restartNeeded)
        XCTAssertEqual(LGUnreachableReason.classify(keyServer: true, ssap: false), .restartNeeded)
        XCTAssertEqual(LGUnreachableReason.classify(keyServer: false, ssap: true), .devModeOff)
        XCTAssertEqual(LGUnreachableReason.classify(keyServer: false, ssap: false), .tvNotFound)
    }
}
