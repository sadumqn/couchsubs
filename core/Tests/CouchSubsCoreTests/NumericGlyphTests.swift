// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class NumericGlyphTests: XCTestCase {
    func testNumberChangesAreNotHiddenByLettersElsewhere() {
        for (reread, sent) in [
            ("I have 1 bullet left.", "I have 5 bullets left."),
            ("I have 1 bullet left.", "I have 5 bullet left."),
            ("1 have 1 bullet left.", "I have 5 bullets left."),
            ("I need 1 more key.", "I need more keys."),
            ("I have 1 and 1 left.", "I have 1 left."),
            ("I have 1 and 1 left.", "I have 1 and 5 left."),
            ("O, we have 0 keys left.", "O, we have 5 keys left."),
            ("I have 10 keys left.", "I have 5 keys left."),
            ("I have 1 key left.", "I have\n5 keys left."),
        ] {
            XCTAssertTrue(TextMatch.addsMeaning(reread, to: sent), reread)
            XCTAssertFalse(TextMatch.isSameSubtitle(TextMatch.normalize(reread), TextMatch.normalizeRows(sent)), reread)
            XCTAssertFalse(TextMatch.isWorseReread(reread, of: sent), reread)
        }
    }

    func testAlignedLetterDigitNoiseDoesNotAddANumber() {
        for (reread, sent) in [
            ("1 can do that.", "I can do that."),
            ("0, we should leave now.", "O, we should leave now."),
            ("Now 1 can do that.", "Now I can do that."),
            ("Ycs 1 can do thal.", "Yes I can do that."),
            ("Yes 1 can do that.", "Well I can do that."),
            ("1 can do that now.", "I can do that."),
            ("Now 1 can do that.", "I can do that."),
            ("1 have 1 key left.", "I have 1 key left."),
            ("1 said 1 can do that.", "I said I can do that."),
            ("1 have 5 keys left.", "I have 5 keys left."),
        ] { XCTAssertFalse(TextMatch.addsMeaning(reread, to: sent), reread) }
    }

    func testStabilizerSendsNumericCorrectionButNotLetterNoise() {
        var s = SubtitleStabilizer()
        let first = "I have 5 bullets left."
        let corrected = "I have 1 bullet left."
        XCTAssertEqual(s.feed(first), .translate(first))
        XCTAssertEqual(s.feed("1 have 5 bullets left."), .none)
        XCTAssertEqual(s.feed(corrected), .translate(corrected))
        XCTAssertEqual(s.feed("1 have 1 bullet left."), .none)
    }
}
