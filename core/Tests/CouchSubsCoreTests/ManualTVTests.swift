// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Elle yazılan adresteki TV'nin türü: Android TV artık LG sayılmıyor (Windows'taki ManualTvTests ile aynı vakalar).
final class ManualTVTests: XCTestCase {
    private let host = "192.168.1.60"

    func testSamsungThatIntroducesItselfIsSamsung() {
        let samsung = LGTV(name: "Samsung Q80", host: host, brand: .samsung)
        let result = ManualTV.classify(host: host, samsung: samsung, lg: nil, androidPortOpen: true)
        XCTAssertEqual(result, ManualTV.Result(tv: samsung, recognised: true))
    }

    /// Yeni LG'lerde Google Cast portu da açık olabilir: LG yanıt verdiyse LG'dir.
    func testLGThatAnswersIsLGEvenWithACastPortOpen() {
        let lg = LGTV(name: "LG OLED", host: host)
        XCTAssertEqual(ManualTV.classify(host: host, samsung: nil, lg: lg, androidPortOpen: true), ManualTV.Result(tv: lg, recognised: true))
    }

    func testAndroidPortMakesItAnAndroidTVWithItsAddress() {
        let result = ManualTV.classify(host: host, samsung: nil, lg: nil, androidPortOpen: true)
        XCTAssertEqual(result.tv, LGTV(name: "Android TV", host: host, brand: .androidTV))
        XCTAssertTrue(result.recognised)
    }

    /// Hiçbir yoklamaya yanıt yok (ör. webOS 3): eskisi gibi LG sayılır ama tanınmadığı bilinir, kullanıcıya söylenir.
    func testSilentAddressStaysLGButIsNotRecognised() {
        let result = ManualTV.classify(host: host, samsung: nil, lg: nil, androidPortOpen: false)
        XCTAssertEqual(result.tv, LGTV(name: "LG TV", host: host))
        XCTAssertFalse(result.recognised)
    }

    func testAndroidPortsIncludeAdbCastAndRemote() {
        XCTAssertEqual(Set(ManualTV.androidPorts), [5555, 6466, 8008, 8009])
    }
}
