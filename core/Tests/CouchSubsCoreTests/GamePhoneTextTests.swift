// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class GamePhoneTextTests: XCTestCase {
    private func line(_ text: String, _ y: Double, _ left: Double = 0.2, _ right: Double = 0.8) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: y, right: right, bottom: y + 0.031))
    }

    func testCaptionsRemainTranslatableButStandaloneTagsAndUserNamesStayInTheGame() {
        let reading = Reading(lines: [line("@vice.305", 0.63), line("Meet me #NightRide", 0.68),
                                      line("#sunset #leonida", 0.73), line("Tell @vice.305 to wait.", 0.80)])
        let kept = GamePhoneText.forTranslation(reading)
        XCTAssertEqual(GamePhoneText.groups(kept).flatMap(\.paragraphs), ["Meet me #NightRide", "Tell @vice.305 to wait."])
        let source = "Send the photo to @KaterinaDiva."
        XCTAssertEqual(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı @katerinadiva'ya gönder."),
                       "Fotoğrafı @KaterinaDiva'ya gönder.")
        XCTAssertNil(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı ona gönder."))
        XCTAssertNil(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı @Joey'e gönder."))
    }

    func testEnglishShorthandAndNumericOcrCorrectionRespectNamesAndCodes() {
        let text = "We're in this 2gether. I left it 4u."
        XCTAssertEqual(GamePhoneText.englishModelInput(text), "We're in this together. I left it for you.")
        XCTAssertEqual(GamePhoneText.groups(Reading(lines: [line(text, 0.5)])).flatMap(\.paragraphs), [text])
        let codes = "Use B4, @4u, #2gether or gate C4."
        XCTAssertEqual(GamePhoneText.englishModelInput(codes), codes)
        XCTAssertEqual(GamePhoneText.englishModelInput("IO min out."), "10 min out.")
        XCTAssertEqual(GamePhoneText.englishModelInput("IO port. I owe him."), "IO port. I owe him.")
    }

    func testContactsOnlyRemovedInRecognizableMessageListAndCutWordsAreNeverCompleted() {
        let rows = [line("Suggestions", 0.04), line("Chase", 0.12), line("call me after ...", 0.16),
                    line("May", 0.25), line("Don't leave yet.", 0.29), line("Messages", 0.42),
                    line("Rose", 0.54), line("Meet me at 06:40.", 0.58)]
        let kept = GamePhoneText.forTranslation(Reading(lines: rows))
        XCTAssertEqual(kept.lines.map(\.text), ["Suggestions", "call me after...", "Don't leave yet.", "Messages", "Meet me at 06:40."])
        XCTAssertTrue(GamePhoneText.forTranslation(Reading(lines: Array(rows.dropFirst()))).lines.map(\.text).contains("May"))
    }

    func testOpposingRepliesAndWrappedMessagesUseFlatDisplayCoordinates() {
        let rows = [line("Find someone who", 0.30, 0.10, 0.69), line("knows this road.", 0.334, 0.10, 0.64),
                    line("on my way", 0.372, 0.38, 0.93)]
        XCTAssertEqual(GamePhoneText.groups(Reading(lines: rows)).flatMap(\.paragraphs), ["Find someone who knows this road.", "on my way"])
        func tilted(_ text: String, _ x: Double, _ y: Double, _ right: Double) -> TextLine {
            var row = TextLine(text, box: TextBox(left: x, top: y, right: right, bottom: y + 0.068))
            row.phoneBox = TextBox(left: x, top: y, right: right, bottom: y + 0.026)
            return row
        }
        let angled = [tilted("That was quite a", 0.1, 0.20, 0.75), tilted("surprise!", 0.1, 0.237, 0.35),
                      tilted("Did you see it?", 0.1, 0.325, 0.70), tilted("Ask later", 0.52, 0.78, 0.88),
                      tilted("No problem", 0.50, 0.862, 0.88)]
        let groups = GamePhoneText.groups(Reading(lines: angled))
        XCTAssertEqual(groups.flatMap(\.paragraphs), ["That was quite a surprise!", "Did you see it?", "Ask later", "No problem"])
        XCTAssertEqual(groups.first?.box, angled[0].box!.union(angled[1].box!))
    }

    /// Önizlemenin üç noktası tek yazımla; son sözcük tamamlanmaz (Windows ile aynı).
    func testPreviewEllipsisHasOneSpellingWithoutCompletingTheLastWord() {
        for (preview, expected) in [("Meet me there ..", "Meet me there..."), ("Meet me there ...", "Meet me there..."),
                                    ("Meet me there...", "Meet me there..."), ("Meet me at 6.", "Meet me at 6.")] {
            let reading = Reading(lines: [line("Suggested", 0.02), line("Jordan", 0.10), line(preview, 0.14),
                                          line("Chase", 0.22), line("Call me back.", 0.26), line("Messages", 0.40),
                                          line("Robin", 0.50), line("On my way.", 0.54)])
            XCTAssertTrue(GamePhoneText.forTranslation(reading).lines.contains { $0.text == expected }, preview)
        }
    }

    /// Yan yana iki kısa sözcükte birer harf oynaması OCR sapmasıdır; kısa yanıtlar ve anlam değişiklikleri değildir.
    func testOnlyAdjacentLetterSlipsInALongMessageWaitForOcrConfirmation() {
        XCTAssertTrue(GamePhoneText.hasAdjacentOcrEdits("Cool. I'll check it out. Would be nice to clear my head for a second.",
                                                        "Cool. I'll check ct ocut. Would be nice to clear my head for a second."))
        for (old, next) in [("Go", "No"),
                            ("Meet me at the back gate with 24 red bags.", "Meet me at the back gate with 25 bed bags."),
                            ("We can do it now if you bring the truck.", "We can not do it now if you bring the truck."),
                            ("I heard they all went to the left door.", "I heard they all went to the rear door."),
                            ("That was all I needed to hear from your friend.", "The next message just came in from the office.")] {
            XCTAssertFalse(GamePhoneText.hasAdjacentOcrEdits(old, next), next)
        }
    }

    /// Doğrulanmış listede "Okay" gibi tek sözcüklük önizleme başka bir kişi adı sanılmaz.
    func testSingleWordPreviewInAConfirmedListIsNotMistakenForAnotherContact() {
        for message in ["Okay", "No", "Thanks"] {
            let rows = Reading(lines: [line("Suggestions", 0.02), line("Chase", 0.09), line("call me soon", 0.13),
                                       line("May", 0.21), line("Don't leave yet.", 0.25), line("Messages", 0.34),
                                       line("Rose", 0.42), line("Meet me here.", 0.46), line("Jason", 0.56), line(message, 0.60),
                                       line("Martin", 0.73), line("Lucia", 0.85)])
            XCTAssertEqual(GamePhoneText.forTranslation(rows).lines.map(\.text),
                           ["Suggestions", "call me soon", "Don't leave yet.", "Messages", "Meet me here.", message])
        }
    }

    /// Aynı taraftaki ayrı yanıtlar telefon kıpırdarken de ayrı kalır; cümleden sonra alt satıra geçen ikinci cümle birliktedir.
    func testSameSideRepliesRemainSeparateAsThePhoneMoves() {
        let h = 0.04
        func flat(_ text: String, _ y: Double, _ x: Double) -> TextLine {
            let box = TextBox(left: x, top: y, right: 0.8, bottom: y + h)
            var row = TextLine(text, box: box)
            row.phoneBox = box
            return row
        }
        for spacing in [0.72, 1.03] {
            let y = 0.12 + h * (1 + spacing), next = y + h * (2.1 + spacing)
            let reading = Reading(lines: [flat("Jason.", 0.12, 0.10), flat("Kirk is paying.", y, 0.15),
                                          flat("He is on his way.", y + h * 1.10, 0.15), flat("Meet me outside.", next, 0.10)])
            XCTAssertEqual(GamePhoneText.groups(reading).flatMap(\.paragraphs),
                           ["Jason.", "Kirk is paying. He is on his way.", "Meet me outside."], "\(spacing)")
        }
    }
}
