// SPDX-License-Identifier: AGPL-3.0-only

import Network
import XCTest
@testable import CouchSubsCore

final class TVReachTests: XCTestCase {
    private let saved = LGTV(name: "LG TV", host: "192.168.1.238")

    /// beta.89: TV 192.168.1.238'den .156'ya geçmişti; eski adres sessiz, TV ağda yeni adreste bulunur.
    func testSilentAddressFindsSameTVAtNewAddress() async {
        let moved = LGTV(name: "LG TV", host: "192.168.1.156")
        let location = await TVReach.locate(saved, responds: { _ in false }, search: {
            [moved, LGTV(name: "Salon", host: "192.168.1.40", brand: .samsung)]
        })
        XCTAssertEqual(location, .moved(moved))
    }

    func testRespondingAddressIsNotSearched() async {
        var searched = false
        let location = await TVReach.locate(saved, responds: { _ in true }, search: { searched = true; return [] })
        XCTAssertEqual(location, .here)
        XCTAssertFalse(searched)
    }

    func testSilentAndNotFoundIsSilent() async {
        let location = await TVReach.locate(saved, responds: { _ in false }, search: { [] })
        XCTAssertEqual(location, .silent)
    }

    /// Ağda iki tanınmayan LG varsa tahmin edilmez (başka odadaki TV'ye geçilmez).
    func testDoesNotGuessBetweenTwoUnknownTVs() async {
        let location = await TVReach.locate(saved, responds: { _ in false }, search: {
            [LGTV(name: "Yatak odası", host: "192.168.1.20"), LGTV(name: "Mutfak", host: "192.168.1.21")]
        })
        XCTAssertEqual(location, .silent)
    }

    func testRefusedConnectionCountsAsAnswer() {
        XCTAssertTrue(TVReach.isRefusal(.posix(.ECONNREFUSED)))
        XCTAssertFalse(TVReach.isRefusal(.posix(.ETIMEDOUT)))
        XCTAssertFalse(TVReach.isRefusal(.posix(.EHOSTUNREACH)))
        XCTAssertFalse(TVReach.isRefusal(.posix(.EHOSTDOWN)))
    }

    /// Yerel makinede kapalı kapı hemen reddeder: "yanıt veriyor" sayılır (TV açık ama o kapı kapalı).
    func testLocalRefusalIsAnAnswer() async {
        let answered = await TVReach.answers(host: "127.0.0.1", port: 9, timeout: .seconds(2))
        XCTAssertTrue(answered)
    }

    func testTexts() {
        XCTAssertEqual(TVReach.notRespondingLine, "TV bu adreste yanıt vermiyor (açık ve aynı ağda mı?)")
        XCTAssertEqual(TVReach.movedLine(from: "192.168.1.238", to: "192.168.1.156"),
                       "TV'nin adresi değişmiş: 192.168.1.238 → 192.168.1.156")
    }
}
