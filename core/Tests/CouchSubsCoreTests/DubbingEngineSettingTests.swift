// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// "Ses: Doğal / Hızlı" (Windows DubbingEngine ile aynı): eski kayıtlar doğal sesle açılır, seçim kalıcıdır.
final class DubbingEngineSettingTests: XCTestCase {
    func testOldSettingsUseNaturalVoicesAndFastSurvivesSaving() throws {
        let old = try JSONDecoder().decode(DubbingSettings.self, from: Data(#"{"enabled":true,"output":"tv"}"#.utf8))
        XCTAssertEqual(old.engine, .natural)
        var settings = DubbingSettings()
        settings.engine = .fast
        let saved = try JSONDecoder().decode(DubbingSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved.engine, .fast)
    }

    /// Sistem sesi duygu etiketini okumaz; ton ve hız sesin `systemTone`'undan gelir.
    func testSystemVoiceTextHasNoEmotionTag() {
        let utterance = SystemSpeech.utterance("Geri çekil!", voice: .male2)
        XCTAssertEqual(utterance.speechString, "geri çekil!")
        XCTAssertEqual(utterance.pitchMultiplier, 1.05, accuracy: 0.001)
    }
}
