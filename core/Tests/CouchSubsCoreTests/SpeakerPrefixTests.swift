// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Android SpeakerPrefixTest ve Windows SpeakerPrefixTests ile aynı örnekler.
final class SpeakerPrefixTests: XCTestCase {
    func testNameIsSplitFromTheSentence() {
        XCTAssertEqual(SpeakerPrefix.split("ARTHUR: We need to go."), .init(name: "ARTHUR", body: "We need to go."))
        XCTAssertEqual(SpeakerPrefix.split("Dutch: I have a plan."), .init(name: "Dutch", body: "I have a plan."))
        XCTAssertEqual(SpeakerPrefix.split("Mrs. Adler：Leave me."), .init(name: "Mrs. Adler", body: "Leave me."))
        XCTAssertEqual(SpeakerPrefix.split("OLD MAN : Hm.")?.name, "OLD MAN")
        XCTAssertEqual(SpeakerPrefix.split("ARTHUR:We go.")?.body, "We go.")
        XCTAssertEqual(SpeakerPrefix.split("Arthur:\nWe need to go.")?.body, "We need to go.")
    }

    func testFalseMatchesAreLeftAlone() {
        XCTAssertNil(SpeakerPrefix.split("10:30 at the station."))
        XCTAssertNil(SpeakerPrefix.split("Meet me at 10:30."))
        XCTAssertNil(SpeakerPrefix.split("HTTPS://example.com"))
        XCTAssertNil(SpeakerPrefix.split("Ratio 16:9"))
        XCTAssertNil(SpeakerPrefix.split("Note: the gate is shut."))
        XCTAssertNil(SpeakerPrefix.split("I told you: get out!"))
        XCTAssertNil(SpeakerPrefix.split("Very Long Name Of Four: words"))
        XCTAssertNil(SpeakerPrefix.split("Bartholomew Montgomeryson: Hi."))
        XCTAssertNil(SpeakerPrefix.split("ARTHUR:"))
    }

    func testPresentAddsOrHidesTheName() {
        let source = "ARTHUR: We need to go."
        XCTAssertEqual(SpeakerPrefix.present("Gitmeliyiz.", source: source, show: true), "ARTHUR: Gitmeliyiz.")
        XCTAssertEqual(SpeakerPrefix.present("Gitmeliyiz.", source: source, show: false), "Gitmeliyiz.")
        // Paket adlı satırı bulduysa ad iki kez yazılmaz.
        XCTAssertEqual(SpeakerPrefix.present("ARTHUR: Gitmeliyiz.", source: source, show: true), "ARTHUR: Gitmeliyiz.")
        XCTAssertEqual(SpeakerPrefix.present("ARTHUR: Evet.\nDUTCH: Hayır.", source: "ARTHUR: Yes.\nDUTCH: No.", show: false), "Evet.\nHayır.")
        // İngilizcede ad olmayan Türkçe başlık atılmaz.
        XCTAssertEqual(SpeakerPrefix.present("Hedef: Kampa dön.", source: "Objective: Return to camp.", show: false), "Hedef: Kampa dön.")
    }

    func testVoicedLinesGetTheSpeaker() {
        let lines = SpeakerPrefix.voiced([SpokenLine(english: "We go.", turkish: "Gidiyoruz.")], prefix: .init(name: "ARTHUR", body: "We go."))
        XCTAssertEqual(lines.map(\.speaker), ["ARTHUR"])
    }

    /// Renkli ad cümleden ayrı okunsa da satır soldan sağa birleşir; ad sona düşmez.
    func testNameReadApartJoinsItsRow() {
        let reading = Reading(lines: [
            TextLine("We need to go.", box: TextBox(left: 0.40, top: 0.501, right: 0.70, bottom: 0.60)),
            TextLine("ARTHUR:", box: TextBox(left: 0.30, top: 0.50, right: 0.385, bottom: 0.60)),
            TextLine("9", box: TextBox(left: 0.95, top: 0.50, right: 0.97, bottom: 0.60)),
        ]).joiningRows()
        XCTAssertEqual(reading.lines.map(\.text).sorted(), ["9", "ARTHUR: We need to go."])
    }
}
