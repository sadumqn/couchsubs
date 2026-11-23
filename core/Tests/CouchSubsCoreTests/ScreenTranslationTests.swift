// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// "Ekranı çevir": ekranın tamamındaki yazılar yerlerine göre gruplanır (Windows: ScreenTranslationTests.cs).
final class ScreenTranslationTests: XCTestCase {
    private func line(_ text: String, _ left: Double, _ top: Double, _ right: Double, height: Double = 0.03) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: top + height))
    }

    func testLinesFarApartBecomeSeparateGroups() {
        let groups = ScreenTranslation.groups(Reading(lines: [
            line("Find the blacksmith in", 0.05, 0.10, 0.30),
            line("the village square", 0.05, 0.135, 0.25),
            line("Press the lever to open the gate.", 0.40, 0.85, 0.60),
            line("New item unlocked", 0.75, 0.60, 0.95),
        ]))
        XCTAssertEqual(groups.map(\.paragraphs), [["Find the blacksmith in the village square"], ["New item unlocked"], ["Press the lever to open the gate."]])
        XCTAssertEqual(groups[0].box.bottom, 0.165, accuracy: 1e-6)
        XCTAssertEqual(groups[0].lineHeight, 0.03, accuracy: 1e-6)
    }

    func testLinesOnTheSameRowButFarApartAreSeparate() {
        XCTAssertEqual(ScreenTranslation.groups(Reading(lines: [line("Settings", 0.05, 0.05, 0.15), line("Back to menu", 0.80, 0.05, 0.95)])).count, 2)
    }

    func testMenuLinesAreTranslatedOneByOne() {
        let groups = ScreenTranslation.groups(Reading(lines: [
            line("Map", 0.05, 0.30, 0.15), line("Inventory", 0.05, 0.34, 0.20), line("Settings", 0.05, 0.38, 0.18),
        ]))
        XCTAssertEqual(groups.map(\.paragraphs), [["Map", "Inventory", "Settings"]])
    }

    func testTitleInBigLettersIsNotMergedWithTheSmallTextBelow() {
        let groups = ScreenTranslation.groups(Reading(lines: [
            line("Chapter One", 0.30, 0.20, 0.70, height: 0.08),
            line("The journey begins in the north.", 0.30, 0.29, 0.70),
        ]))
        XCTAssertEqual(groups.count, 2)
    }

    func testFullWidthHeadingDoesNotAbsorbOneOfTwoColumns() {
        for reversed in [false, true] {
            let lines = [line("Available missions", 0.05, 0.10, 0.95),
                line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
                line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92)]
            let groups = ScreenTranslation.groups(Reading(lines: reversed ? Array(lines.reversed()) : lines))
            XCTAssertEqual(groups.count, 3)
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Available missions"] && abs($0.box.bottom - 0.13) < 1e-6 })
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Find the blacksmith in the village square."] && $0.box.right < 0.5 })
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Bring the medicine to the northern camp."] && $0.box.left > 0.5 })
        }
    }

    func testFullWidthFooterDoesNotJoinEitherColumn() {
        for reversed in [false, true] {
            let lines = [line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
                line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92),
                line("Choose a destination", 0.05, 0.22, 0.95)]
            let groups = ScreenTranslation.groups(Reading(lines: reversed ? Array(lines.reversed()) : lines))
            XCTAssertEqual(groups.count, 3)
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Choose a destination"] && abs($0.box.top - 0.22) < 1e-6 })
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Find the blacksmith in the village square."] })
            XCTAssertTrue(groups.contains { $0.paragraphs == ["Bring the medicine to the northern camp."] })
        }
    }

    func testWrappedParagraphKeepsNarrowOrIndentedContinuation() {
        for (left, right) in [(0.05, 0.4), (0.30, 0.70), (0.60, 0.95)] {
            let groups = ScreenTranslation.groups(Reading(lines: [line("Find the blacksmith in", 0.05, 0.10, 0.95),
                line("the village square.", left, 0.14, right)]))
            XCTAssertEqual(groups.map(\.paragraphs), [["Find the blacksmith in the village square."]])
        }
    }

    func testNearbyUnrelatedColumnDoesNotDetachTheLocalHeading() {
        let groups = ScreenTranslation.groups(Reading(lines: [line("Current objective", 0.05, 0.10, 0.43),
            line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
            line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92)]))
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.contains { $0.paragraphs == ["Current objective", "Find the blacksmith in the village square."] })
    }

    func testFilteredControllerPromptDoesNotCreateAColumnBoundary() {
        let groups = ScreenTranslation.groups(Reading(lines: [line("Find the blacksmith in", 0.05, 0.10, 0.95),
            line("the village square.", 0.05, 0.14, 0.43), line("R2 Swing", 0.57, 0.14, 0.95)]))
        XCTAssertEqual(groups.map(\.paragraphs), [["Find the blacksmith in the village square."]])
    }

    func testSeparatingTheHeadingKeepsTranslationInputsAndText() async throws {
        var requested: [String] = []
        let items = try await ScreenTranslation.translate(Reading(lines: [line("Available missions", 0.05, 0.10, 0.95),
            line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
            line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92)]),
            using: { requested.append($0); return "Türkçe sonuç \(requested.count)" }, progress: { _ in })
        XCTAssertEqual(items.map(\.source), ["Available missions", "Find the blacksmith in the village square.", "Bring the medicine to the northern camp."])
        XCTAssertEqual(items.map(\.source), requested)
        XCTAssertEqual(items.map(\.translation), ["Türkçe sonuç 1", "Türkçe sonuç 2", "Türkçe sonuç 3"])
    }

    /// Silah menüsü: iki sütunda aralıklı etiketler, altta bilgi kutusu. Son satır, üstteki satırın altındaki boşluk
    /// satır yüksekliğinin %90'ı olunca ayrı grup oluyor, 31. grup olduğu için de hiç çevrilmiyordu (Windows: LoadoutMenu).
    private func loadoutMenu(_ labels: Int) -> [TextLine] {
        var lines: [TextLine] = (0..<labels).map { i -> TextLine in
            let (left, right) = i % 2 == 0 ? (0.05, 0.20) : (0.78, 0.95)
            let letter = Character(UnicodeScalar(UInt8(65 + i % 26)))
            return line("Weapon slot \(letter)\(i)", left, 0.04 + Double(i / 2) * 0.045, right, height: 0.02)
        }
        lines.append(line("Weapons lost during a mission can be", 0.30, 0.75, 0.70, height: 0.025))
        lines.append(line("recovered from a weapon locker.", 0.30, 0.7975, 0.62, height: 0.025))
        return lines
    }

    func testLastLineOfAnInfoBoxIsNotLeftOut() {
        let groups = ScreenTranslation.groups(Reading(lines: loadoutMenu(29)))
        XCTAssertTrue(groups.contains { $0.paragraphs == ["Weapons lost during a mission can be recovered from a weapon locker."] })
        XCTAssertFalse(groups.contains { $0.paragraphs.contains("recovered from a weapon locker.") })
    }

    func testCrowdedScreenKeepsTheGroupsWithTheMostText() {
        let groups = ScreenTranslation.groups(Reading(lines: loadoutMenu(40)))
        XCTAssertEqual(groups.count, ScreenTranslation.maxGroups)
        XCTAssertEqual(groups.last?.paragraphs, ["Weapons lost during a mission can be recovered from a weapon locker."])
        XCTAssertEqual(groups.map(\.box.top), groups.map(\.box.top).sorted())
    }

    func testLowercaseLineAfterAFinishedSentenceFarBelowStaysSeparate() {
        let groups = ScreenTranslation.groups(Reading(lines: [
            line("Weapons can be recovered.", 0.30, 0.75, 0.70, height: 0.025),
            line("then continue on later", 0.30, 0.7975, 0.62, height: 0.025),
            line("and this one is far below", 0.30, 0.88, 0.62, height: 0.025),
        ]))
        XCTAssertEqual(groups.count, 3)
    }

    func testNumbersAndPromptsAreNotTranslated() {
        let groups = ScreenTranslation.groups(Reading(lines: [
            line("23m", 0.50, 0.05, 0.55), line("9", 0.90, 0.05, 0.92), line("R2 Swing", 0.80, 0.90, 0.95), line("HP 120/300", 0.05, 0.90, 0.20),
        ]))
        XCTAssertEqual(groups.map(\.paragraphs), [["HP 120/300"]])
    }

    func testEveryGroupIsTranslatedAndProgressIsReported() async throws {
        var reported: [Int] = []
        let items = try await ScreenTranslation.translate(Reading(lines: [
            line("Find the blacksmith.", 0.05, 0.10, 0.30),
            line("Bring him three iron bars.", 0.05, 0.135, 0.30),
            line("KRATOS", 0.60, 0.50, 0.70),
            line("Leave the camp", 0.60, 0.80, 0.90),
        ]), using: { $0 == "KRATOS" ? $0 : "TR: " + $0 }, progress: { reported.append($0.count) })
        XCTAssertEqual(items.map(\.translation), ["TR: Find the blacksmith.\nTR: Bring him three iron bars.", "TR: Leave the camp"])
        XCTAssertTrue(items[0].paragraphs)
        XCTAssertFalse(items[1].paragraphs)
        XCTAssertEqual(reported, [1, 2])
    }

    func testDisplayTimeGrowsWithTextButIsBounded() {
        let item = { (length: Int) in ScreenTranslation.Item(source: "a", translation: String(repeating: "a", count: length), box: TextBox(left: 0, top: 0, right: 1, bottom: 1), lineHeight: 0.03) }
        XCTAssertEqual(ScreenTranslation.displayMilliseconds([item(0)]), 12000)
        XCTAssertEqual(ScreenTranslation.displayMilliseconds([item(200)]), 18000)
        XCTAssertEqual(ScreenTranslation.displayMilliseconds([item(5000)]), 60000)
    }
}
