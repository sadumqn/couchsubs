// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Birden çok Android TV varken kurulum ilk bulunana gitmez; kayıtlı/seçilen TV, yoksa kullanıcıya sorulur (GitHub #425).
final class AndroidTVPickTests: XCTestCase {
    func testSingleTVIsPicked() {
        XCTAssertEqual(AndroidTVPick.pick(found: ["192.168.1.105"], preferred: []), .host("192.168.1.105"))
        XCTAssertEqual(AndroidTVPick.pick(found: [], preferred: ["192.168.1.105"]), AndroidTVPick.none)
    }

    func testSeveralTVsAreAskedUnlessOneIsKnown() {
        let found = ["192.168.1.105", "192.168.1.106"]
        XCTAssertEqual(AndroidTVPick.pick(found: found, preferred: []), .ask(found))
        XCTAssertEqual(AndroidTVPick.pick(found: found, preferred: ["", "192.168.1.106"]), .host("192.168.1.106"))
        XCTAssertEqual(AndroidTVPick.pick(found: found, preferred: ["192.168.1.7"]), .ask(found))
        XCTAssertEqual(AndroidTVPick.pick(found: found + ["192.168.1.105"], preferred: []), .ask(found))
    }
}
