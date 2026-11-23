// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// Paket isteklerinin imzası (server/packs). Windows PackSigningTests.cs ve Android PackSigningTest.kt ile aynı vektör.
final class PackSigningTests: XCTestCase {
    private let secret = "test-secret-not-real"
    private let vector = "c7d9ee8207b98e3d43de0bfd2ecbcaaadf125e718f03b4fe8dae1779f18b5f30"

    func testSharedVector() {
        XCTAssertEqual(PackSigning.signature(secret: secret, method: "GET", path: "/v1/packs/gta-6", time: 1_764_460_800), vector)
    }

    func testMirrorsSignEveryRequestWithItsOwnPath() async {
        let seen = Box<[URLRequest]>([])
        let mirrors = PackMirrors(primary: URL(string: "https://packs.primary.test")!, secret: secret,
                                  clock: { Date(timeIntervalSince1970: 1_764_460_800) })
        _ = await mirrors.get("v1/packs/gta-6", timeout: 5) { request in
            seen.value.append(request)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(seen.value.first?.value(forHTTPHeaderField: "x-couchsubs-time"), "1764460800")
        XCTAssertEqual(seen.value.first?.value(forHTTPHeaderField: "x-couchsubs-signature"), vector)
    }

    func testNoSecretNoHeaders() async {
        let seen = Box<[URLRequest]>([])
        _ = await PackMirrors(primary: URL(string: "https://packs.primary.test")!).get("v1/packs", timeout: 5) { request in
            seen.value.append(request)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertNil(seen.value.first?.value(forHTTPHeaderField: "x-couchsubs-signature"))
    }

    func testConfiguredSecretIgnoresEmptyAndUnexpandedValues() {
        XCTAssertNil(PackSigning.configuredSecret(environment: [:], bundle: Bundle(for: Self.self)))
        XCTAssertNil(PackSigning.configuredSecret(environment: ["COUCHSUBS_PACKS_SECRET": "  "], bundle: Bundle(for: Self.self)))
        XCTAssertNil(PackSigning.configuredSecret(environment: ["COUCHSUBS_PACKS_SECRET": "$(PACKS_APP_SECRET)"],
                                                  bundle: Bundle(for: Self.self)))
        XCTAssertEqual(PackSigning.configuredSecret(environment: ["COUCHSUBS_PACKS_SECRET": "abc"], bundle: Bundle(for: Self.self)), "abc")
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
