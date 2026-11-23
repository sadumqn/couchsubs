// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// Paket kapağı (Windows GameCoverStoreTests ile aynı durumlar).
final class GameCoverStoreTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+V8dMAAAAASUVORK5CYII=")!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testUnsafePackIdsHaveNoCoverPath() {
        for id in ["../gta-v", "gta/v", "GTA-V", "", "gta-v.png", "-gta"] {
            XCTAssertNil(GameCoverStore.url(for: id, in: directory), id)
        }
        XCTAssertNil(GameCoverStore.url(for: nil, in: directory))
    }

    func testUserCoverIsStoredLocallyAndCanBeRemoved() throws {
        let file = try XCTUnwrap(GameCoverStore.url(for: "gta-v", in: directory))
        XCTAssertEqual(file.lastPathComponent, "gta-v.png")
        try GameCoverStore.save(png, for: "gta-v", in: directory)
        XCTAssertEqual(try Data(contentsOf: file), png)
        XCTAssertTrue(GameCoverStore.remove(for: "gta-v", in: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(GameCoverStore.remove(for: "gta-v", in: directory))
    }

    func testOversizedOrNonPngCoverNeverOverwritesAnExistingCover() throws {
        try GameCoverStore.save(png, for: "elden-ring", in: directory)
        XCTAssertThrowsError(try GameCoverStore.save(Data("not a png".utf8), for: "elden-ring", in: directory))
        XCTAssertThrowsError(try GameCoverStore.save(png + Data(count: GameCoverStore.maxCoverBytes), for: "elden-ring", in: directory))
        XCTAssertEqual(try Data(contentsOf: GameCoverStore.url(for: "elden-ring", in: directory)!), png)
    }
}
