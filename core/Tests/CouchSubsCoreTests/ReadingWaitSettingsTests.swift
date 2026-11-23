// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// "Bozuk okunan satır için bekleme" ve "Yarım okunan satır için bekleme" (Windows MisreadWaitMs/PartialWaitMs ile aynı).
final class ReadingWaitSettingsTests: XCTestCase {
    func testOldSettingsOpenWithTheRecommendedWaits() throws {
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"sourceLanguage":"en"}"#.utf8))
        XCTAssertEqual(old.misreadWaitMs, 800)
        XCTAssertEqual(old.partialWaitMs, 300)
        XCTAssertEqual(old.misreadWaitMs, SubtitlePipeline.packWaitMs)
        XCTAssertEqual(old.partialWaitMs, SubtitlePipeline.cleanWaitMs)
    }

    func testChangedWaitsSurviveSaving() throws {
        var settings = UserSettings()
        settings.misreadWaitMs = 400
        settings.partialWaitMs = 0
        let saved = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved.misreadWaitMs, 400)
        XCTAssertEqual(saved.partialWaitMs, 0)
    }

    @MainActor
    func testWaitsAreAppliedToThePipelineWithinLimits() {
        let pipeline = SubtitlePipeline(reader: EmptyReader(), translator: Echo(), server: Quiet())
        XCTAssertEqual(pipeline.packWait, 800)
        XCTAssertEqual(pipeline.cleanWait, 300)
        var settings = UserSettings()
        settings.misreadWaitMs = 600
        settings.partialWaitMs = 100
        pipeline.applyWaits(from: settings)
        XCTAssertEqual(pipeline.packWait, 600)
        XCTAssertEqual(pipeline.cleanWait, 100)
        settings.misreadWaitMs = -5
        settings.partialWaitMs = 99_000
        pipeline.applyWaits(from: settings)
        XCTAssertEqual(pipeline.packWait, 0)
        XCTAssertEqual(pipeline.cleanWait, UserSettings.maxWaitMs)
    }

    private final class EmptyReader: TextReader, @unchecked Sendable {
        func read(_ image: CGImage) throws -> String { "" }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { .empty }
    }

    private final class Echo: TextTranslator, @unchecked Sendable {
        func translate(_ text: String) async throws -> String { text }
    }

    private final class Quiet: SubtitleSending {
        func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {}
        func clear() {}
    }
}
