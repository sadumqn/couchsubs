// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class FastSubtitleDetectionTests: XCTestCase {
    func testOldSettingsKeepTheTwentyFrameDefault() throws {
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"sourceLanguage":"en"}"#.utf8))
        XCTAssertFalse(old.fastSubtitleDetection)
        XCTAssertEqual(ReadScheduler.defaultMaxReuse, 20)
    }

    func testEnabledSettingSurvivesSavingAndRefreshesAfterTwoReusedFrames() throws {
        var settings = UserSettings()
        settings.fastSubtitleDetection = true
        let saved = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(saved.fastSubtitleDetection)

        var scheduler = ReadScheduler(maxReuse: saved.fastSubtitleDetection
            ? ReadScheduler.fastMaxReuse : ReadScheduler.defaultMaxReuse)
        let still = [UInt8](repeating: 40, count: 16)
        XCTAssertEqual(scheduler.plan(signature: still), .read(deep: true))
        scheduler.record("")
        XCTAssertEqual(scheduler.plan(signature: still), .reuse(""))
        XCTAssertEqual(scheduler.plan(signature: still), .reuse(""))
        XCTAssertEqual(scheduler.plan(signature: still), .read(deep: false))
    }
}
