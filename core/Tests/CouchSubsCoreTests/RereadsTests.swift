// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Yarım ya da bozuk okumanın aynı satır sayılma kuralları (Windows: SubtitlePipeline.IsRereadOf, Android: ReadingHoldTest).
final class RereadsTests: XCTestCase {
    func testHalfReadLineIsRereadOfWholeLine() {
        XCTAssertTrue(Rereads.isRereadOf("Get Franklin close to the", "Get Franklin close to the house."))
    }

    func testSeparateShortSentenceIsNotReread() {
        XCTAssertFalse(Rereads.isRereadOf("You kill me!", "I swear to God, you kill me!"))
    }

    func testDroppedWordIsReread() {
        XCTAssertTrue(Rereads.isRereadOf("Go to Bluffs", "Go to Pacific Bluffs."))
    }

    /// OCR'ın sözcüğü böldüğü bozuk okuma, sözcük sayısı değişse de aynı satırdır (#296).
    func testSplitWordMisreadIsReread() {
        XCTAssertTrue(Rereads.isRereadOf("That smo e...", "That smoke..."))
        XCTAssertTrue(Rereads.isRereadOf("Y u ave to ask?", "You have to ask?"))
        XCTAssertFalse(Rereads.isRereadOf("That's my b at, kid.", "That smoke..."))
    }

    func testSameLetters() {
        XCTAssertTrue(TextMatch.sameLetters("that smo e", "that smoke"))
        XCTAssertFalse(TextMatch.sameLetters("get 0n", "get on")) // kısa: harf benzerliği aranmaz
        XCTAssertFalse(TextMatch.sameLetters("that s my b at kid", "that smoke"))
    }

    func testCompleteness() {
        XCTAssertTrue(Rereads.looksComplete("Hold the gate."))
        XCTAssertFalse(Rereads.looksComplete("hold the gate"))
        XCTAssertFalse(Rereads.looksComplete("Get Franklin close to the"))
    }

    func testMissingSecondLineIsKept() {
        XCTAssertEqual(Rereads.keepMissingLines("You did it.", older: "You did it.\nI don't care!"), "You did it.\nI don't care!")
    }

    func testRelated() {
        XCTAssertTrue(Rereads.related("Get Franklin close", "Get Franklin close to the house."))
        XCTAssertFalse(Rereads.related("And you watch your language!", "r guage! fair!"))
    }
}
