// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

final class GamePackImporterTests: XCTestCase {
    func testFlatJSONHashesEnglishAndCountsInvalidRecords() throws {
        let preview = try parse(#"{"You fucked up now, boy!":"  Bu kez işi batırdın!  ","...":"x","":"x","Blank":"  ","Number":7}"#, "flat.JSON")
        XCTAssertNil(preview.suggestedTitle)
        XCTAssertEqual(preview.entries, ["e7f18c8f6d1083ab": "Bu kez işi batırdın!"])
        XCTAssertEqual(preview.invalidCount, 4)
    }

    func testJSONEnvelopeUsesMetadataAndOnlyReadsSubtitlePairs() throws {
        let preview = try parse(#"{"game":"  Test Game  ","title":"Alternate","subtitles":{"Get Down!":"Yere yat!"},"other":"ignored"}"#, "game.json")
        XCTAssertEqual(preview.suggestedTitle, "Test Game")
        XCTAssertEqual(preview.entries, ["ebf811f2fee9a8cc": "Yere yat!"])
        XCTAssertEqual(preview.invalidCount, 0)
    }

    func testHashedJSONValidatesAndLowercasesKeysWithoutRehashing() throws {
        let preview = try parse(#"{"format":1,"id":"ignored","title":"Existing Game","entries":{"0123456789ABCDEF":"Türkçe","0123456789abcdef":"Türkçe","+123456789abcdef":"bad","g123456789abcdef":"bad","fedcba9876543210":null,"9999999999999999":"  ","123":"bad"}}"#, "existing.json")
        XCTAssertEqual(preview.suggestedTitle, "Existing Game")
        XCTAssertEqual(preview.entries, ["0123456789abcdef": "Türkçe"])
        XCTAssertEqual(preview.invalidCount, 5)
        XCTAssertEqual(preview.duplicateCount, 1)
    }

    func testCanonicalJSONDuplicatesAreCountedAndConflictsOmitted() throws {
        let preview = try parse(#"{"Get Down!":"Yere \u0079at!","get down":"Yere yat!","get DOWN?":"Çök!","GET DOWN.":"Yere yat!","Who is that?":"Kim o?"}"#, "repeat.json")
        XCTAssertEqual(preview.entries, ["ce61a5b5526ea81a": "Kim o?"])
        XCTAssertEqual(preview.duplicateCount, 2)
        XCTAssertEqual(preview.conflictCount, 1)
    }

    func testRepeatedJSONMembersReachThePairAccumulator() throws {
        let fixtures = [
            (#"{"Get Down!":"Yere yat!","Get Down!":"Çök!","Get Down!":"Çök!","Who is that?":"Kim o?","Who is that?":"Kim o?"}"#, "ce61a5b5526ea81a"),
            (#"{"subtitles":{"Get Down!":"Yere yat!","Get Down!":"Çök!","Get Down!":"Çök!","Who is that?":"Kim o?","Who is that?":"Kim o?"}}"#, "ce61a5b5526ea81a"),
            (#"{"format":1,"entries":{"0123456789abcdef":"Yere yat!","0123456789abcdef":"Çök!","0123456789abcdef":"Çök!","ffffffffffffffff":"Kim o?","ffffffffffffffff":"Kim o?"}}"#, "ffffffffffffffff"),
        ]
        for (source, survivingKey) in fixtures {
            let preview = try parse(source, "repeats.json")
            XCTAssertEqual(preview.entries, [survivingKey: "Kim o?"], source)
            XCTAssertEqual(preview.duplicateCount, 2, source)
            XCTAssertEqual(preview.conflictCount, 1, source)
        }
    }

    func testNumericFormatRequiresAnEntriesObject() {
        let malformed = [
            #"{"format":1,"title":"Existing Game","entries":[]}"#,
            #"{"format":1,"title":"Existing Game","entries":"text"}"#,
            #"{"format":1,"title":"Existing Game","entries":[true,"Get Down!","Yere yat!"]}"#,
            #"{"format":1,"title":"Existing Game","subtitles":{"Get Down!":"Yere yat!"}}"#,
            #"{"format":2,"title":"Existing Game","entries":null}"#,
        ]
        for source in malformed {
            XCTAssertThrowsError(try parse(source, "broken-pack.json"), source)
        }
    }

    func testTXTHandlesBOMCRLFAndBothDelimiters() throws {
        let preview = try parse("\u{FEFF}  # ignored\r\n\r\nGet Down! = Yere yat! = şimdi\r\nWho is that?\tKim o?\r\nbroken\r\nEmpty = \r\n\tMissing\r\nExtra\tfield\tline\r\n", "pairs.txt")
        XCTAssertEqual(preview.entries, ["ebf811f2fee9a8cc": "Yere yat! = şimdi", "ce61a5b5526ea81a": "Kim o?"])
        XCTAssertEqual(preview.invalidCount, 4)
    }

    func testConflictingCanonicalKeyStaysOmittedAfterMoreRecords() throws {
        let preview = try parse("Get Down! = Yere yat!\nget down = Yere yat!\n<b>GET DOWN</b> = Çök!\nGet down? = Yere yat!\nGet down = Eğil!\nWho is that? = Kim o?", "pairs.txt")
        XCTAssertEqual(preview.entries, ["ce61a5b5526ea81a": "Kim o?"])
        XCTAssertEqual(preview.duplicateCount, 2)
        XCTAssertEqual(preview.conflictCount, 1)
        XCTAssertEqual(preview.invalidCount, 0)
    }

    func testBilingualSRTSkipsInvalidCueShapesWithoutLosingNeighbors() throws {
        let cues = [
            "1\n00:00:01,250 --> 00:00:03,999\n Get Down! \n Yere yat! ",
            "2\n00:00:04,000 --> 00:00:05,000\nOne line",
            "3\n00:00:06,000 --> 00:00:07,000\nThree\nText\nLines",
            "x\n00:00:08,000 --> 00:00:09,000\nBad\nIndex",
            "5\n00:60:00,000 --> 00:60:01,000\nBad\nClock",
            "6\n00:00:11.000 --> 00:00:11.999\nBad\nSeparator",
            "7\n00:00:13,000 --> 00:00:12,000\nReversed\nClock",
            "8\n00:00:14,000 --> 00:00:15,000\nWho is that?\nKim o?",
        ]
        let preview = try parse("\u{FEFF}" + cues.joined(separator: "\n \t\n").replacingOccurrences(of: "\n", with: "\r\n"), "pairs.SRT")
        XCTAssertEqual(preview.entries, ["ebf811f2fee9a8cc": "Yere yat!", "ce61a5b5526ea81a": "Kim o?"])
        XCTAssertEqual(preview.invalidCount, 6)
    }

    func testInvalidFileShapesAndUnsupportedFormatsThrow() {
        XCTAssertThrowsError(try parse("pairs", "file.csv"))
        XCTAssertThrowsError(try GamePackImporter.parse(Data([0xff]), fileName: "file.txt"))
        XCTAssertThrowsError(try parse("[1, 2]", "file.json"))
        XCTAssertThrowsError(try parse(#"{"oops",1}"#, "file.json"))
        XCTAssertThrowsError(try parse(#"{"format":2,"entries":{"0123456789ABCDEF":"Türkçe"}}"#, "file.json"))
        XCTAssertThrowsError(try parse(#"{"format":true,"entries":{"0123456789ABCDEF":"Türkçe"}}"#, "file.json"))
    }

    func testIDsUseStablePathSafeASCII() {
        XCTAssertEqual(GamePackImporter.makeID(title: " ../My GAME\\a:a... "), "community-my-game-a-a")
        XCTAssertEqual(GamePackImporter.makeID(title: "../遊戲"), "community-game")
        XCTAssertEqual(GamePackImporter.makeID(title: String(repeating: "a", count: 300)), "community-" + String(repeating: "a", count: 80))
    }

    func testInstallWritesPackTheLibraryCanReloadAndRequiresReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = GamePackLibrary(bundled: nil, user: directory)
        XCTAssertTrue(library.packs.isEmpty)
        let initial = try parse("Get Down! = Yere yat!", "pairs.txt")
        XCTAssertThrowsError(try GamePackImporter.install(initial, title: " \n ", directory: directory, replacing: false))
        let url = try GamePackImporter.install(initial, title: " Test Game ", directory: directory, replacing: false)
        XCTAssertEqual(url.lastPathComponent, "community-test-game.json")
        let original = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? NSDictionary)
        XCTAssertEqual(object, ["format": 1, "id": "community-test-game", "title": "Test Game", "entries": ["ebf811f2fee9a8cc": "Yere yat!"]] as NSDictionary)
        library.reload()
        XCTAssertEqual(library.packs.map(\.title), ["Test Game"])
        XCTAssertEqual(library.packs.map(\.entries), [1])
        XCTAssertEqual(library.translation(forKey: "ebf811f2fee9a8cc"), "Yere yat!")

        let updated = try parse("Get Down! = Çök!", "pairs.txt")
        XCTAssertThrowsError(try GamePackImporter.install(updated, title: "Test Game", directory: directory, replacing: false))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try GamePackImporter.install(updated, title: "Test Game", directory: directory, replacing: true), url)
        library.reload()
        XCTAssertEqual(library.translation(forKey: "ebf811f2fee9a8cc"), "Çök!")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [url.lastPathComponent])
    }

    func testEmptyPreviewCannotReplaceAUsablePack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try parse("Get Down! = Yere yat!", "pairs.txt")
        let url = try GamePackImporter.install(initial, title: "Test Game", directory: directory, replacing: false)
        let original = try Data(contentsOf: url)
        let empty = try parse("# no pairs\ninvalid", "pairs.txt")
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertThrowsError(try GamePackImporter.install(empty, title: "Test Game", directory: directory, replacing: true))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInstallCannotReplaceItsOwnSourceThroughAnAlias() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let source = directory.appendingPathComponent("community-test-game.json")
        let alias = directory.appendingPathComponent("original.json")
        let original = Data(#"{"Get Down!":"Yere yat!"}"#.utf8)
        try original.write(to: source)
        try manager.createSymbolicLink(at: alias, withDestinationURL: source)
        let preview = try GamePackImporter.parse(original, fileName: source.lastPathComponent)
        for sourceURL in [source, alias] {
            XCTAssertThrowsError(try GamePackImporter.install(preview, title: "Test Game", directory: directory,
                                                               replacing: true, sourceURL: sourceURL))
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    private func parse(_ source: String, _ name: String) throws -> GamePackImportPreview {
        try GamePackImporter.parse(Data(source.utf8), fileName: name)
    }
}
