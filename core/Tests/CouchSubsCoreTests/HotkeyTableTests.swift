// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import XCTest

/// Mac'in değiştirilebilir kısayolları: Windows HotkeyTableTests ile aynı işler, aynı sıra, aynı varsayılanlar ve aynı
/// çakışma kuralları; tuş kuralları macOS'a göre (⌥ yalnız, ⌘ yalnız, ekran görüntüsü tuşları).
final class HotkeyTableTests: XCTestCase {
    private let keypad: [UInt32] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
    private let row: [UInt32] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]

    /// Sayı tuş takımı olmayan Mac'te de her iş yapılabilsin: her işin bir Num tuşu ve bir ⌃⇧rakam tuşu var.
    func testEveryActionHasKeypadAndControlShiftKey() {
        for action in HotkeyAction.allCases {
            let keys = HotkeyTable.bindings.filter { $0.action == action }.map(\.key)
            XCTAssertEqual(keys.count, 2, "\(action)")
            XCTAssertEqual(keys.filter { $0.modifiers == [] }.count, 1)
            XCTAssertEqual(keys.filter { $0.modifiers == [.control, .shift] }.count, 1)
        }
    }

    /// Windows'taki rakamlar: Num 9 ile ⌃⇧9 ekranı çevirir, diğerleri de aynı.
    func testDigitsMatchWindows() {
        let expected: [(HotkeyAction, Int)] = [(.pauseSubtitles, 0), (.extraRegion1, 1), (.extraRegion2, 2), (.extraRegion3, 3),
                                               (.freeArea, 5), (.clickThrough, 7), (.snapshot, 8), (.screen, 9)]
        for (action, digit) in expected {
            XCTAssertEqual(HotkeyTable.key(nil, action, slot: 0), HotkeyKey([], keypad[digit]))
            XCTAssertEqual(HotkeyTable.key(nil, action, slot: 1), HotkeyKey(.combo, row[digit]))
            XCTAssertEqual(HotkeyTable.key(nil, action, slot: 0)?.label, "Num \(digit)")
            XCTAssertEqual(HotkeyTable.key(nil, action, slot: 1)?.label, "⌃⇧\(digit)")
        }
        // İşlerin adları Windows ayar dosyasındakiyle aynı.
        XCTAssertEqual(HotkeyAction.allCases.map(\.rawValue),
                       ["ExtraRegion1", "ExtraRegion2", "ExtraRegion3", "FreeArea", "Snapshot", "PauseSubtitles", "Screen", "ClickThrough"])
        XCTAssertEqual(HotkeyTable.order, [.screen, .freeArea, .extraRegion1, .extraRegion2, .extraRegion3, .pauseSubtitles, .clickThrough, .snapshot])
    }

    func testNoKeyIsRegisteredTwiceAndKeypadComesFirst() {
        let bindings = HotkeyTable.bindings
        XCTAssertEqual(Set(bindings.map(\.key)).count, bindings.count)
        XCTAssertTrue(bindings.prefix(HotkeyTable.digits.count).allSatisfy { $0.key.modifiers == [] })
        XCTAssertEqual(HotkeyTable.resolve([]), bindings)
    }

    func testDefaultsAreValid() {
        for binding in HotkeyTable.bindings { XCTAssertEqual(HotkeyTable.validate(binding.key), .none) }
    }

    /// Ekranı çevir için Num 9 yerine ⌥⌘T: ⌃⇧9 kalır, Num 9 artık hiçbir işi yapmaz.
    func testChangedKeyReplacesOnlyThatSlot() {
        let optionCommandT = HotkeyKey([.option, .command], 0x11)
        let (choices, displaced) = HotkeyTable.assign([], .screen, slot: 0, key: optionCommandT)
        XCTAssertNil(displaced)
        XCTAssertEqual(HotkeyTable.keys(choices, .screen), [optionCommandT, HotkeyKey(.combo, 0x19)])
        XCTAssertFalse(HotkeyTable.resolve(choices).contains { $0.key == HotkeyKey([], 0x5C) })
        XCTAssertEqual(optionCommandT.label, "⌥⌘T")
    }

    /// Başka işin tuşu seçilirse o işten kaldırılır; iki iş aynı tuşu tutmaz.
    func testTakenKeyMovesFromOtherAction() {
        let num5 = HotkeyKey([], 0x57)
        let (choices, displaced) = HotkeyTable.assign([], .screen, slot: 0, key: num5)
        XCTAssertEqual(displaced, .freeArea)
        XCTAssertEqual(HotkeyTable.resolve(choices).first { $0.key == num5 }?.action, .screen)
        XCTAssertNil(HotkeyTable.key(choices, .freeArea, slot: 0))
        XCTAssertEqual(HotkeyTable.keys(choices, .freeArea), [HotkeyKey(.combo, 0x17)])
    }

    /// Kısayol kapatılabilir; varsayılana dönen yuva ayarlarda yer kaplamaz.
    func testClearingAndRestoringKeys() {
        let cleared = HotkeyTable.assign([], .clickThrough, slot: 1, key: nil).choices
        XCTAssertEqual(HotkeyTable.keys(cleared, .clickThrough).count, 1)
        let restored = HotkeyTable.assign(cleared, .clickThrough, slot: 1, key: HotkeyTable.defaultKey(.clickThrough, slot: 1)).choices
        XCTAssertTrue(restored.isEmpty)
    }

    /// Ayarlar elle bozulsa da (aynı tuş iki işte, geçersiz tuş) tutulan tabloda çakışma olmaz.
    func testResolveSkipsDuplicateAndInvalidChoices() {
        let choices = [HotkeyChoice(action: .screen, slot: 1, key: HotkeyKey([], 0x00)),
                       HotkeyChoice(action: .freeArea, slot: 1, key: HotkeyKey([], 0x5C))]
        let bindings = HotkeyTable.resolve(choices)
        XCTAssertEqual(Set(bindings.map(\.key)).count, bindings.count)
        XCTAssertFalse(bindings.contains { $0.key.keyCode == 0x00 })
        XCTAssertEqual(bindings.first { $0.key == HotkeyKey([], 0x5C) }?.action, .screen)
    }

    func testValidation() {
        let cases: [(HotkeyModifiers, UInt32, HotkeyProblem)] = [
            ([], 0x5C, .none),                         // Num 9
            ([], 0x78, .none),                         // F2
            ([], 0x35, .unsupportedKey),               // Esc
            ([], 0x24, .unsupportedKey),               // Return
            ([], 0x11, .needsModifier),                // T
            ([.shift], 0x11, .needsModifier),          // ⇧T büyük harf yazar
            ([.command], 0x08, .needsModifier),        // ⌘C kopyalar
            ([.control], 0x00, .needsModifier),        // ⌃A satır başına gider
            ([.command, .shift], 0x11, .needsModifier),
            ([.control, .shift], 0x11, .none),         // ⌃⇧T
            ([.option, .command], 0x11, .none),        // ⌥⌘T (eski Mac kısayolu)
            ([.control, .option], 0x11, .none),
            ([.control, .command], 0x11, .none),
            ([.option], 0x11, .optionOnly),            // ⌥T özel karakter yazar; macOS 15 almaz
            ([.option, .shift], 0x5C, .optionOnly),
            ([.command, .shift], 0x14, .reserved),     // ⌘⇧3 ekran görüntüsü
            ([.control, .command, .shift], 0x15, .reserved),
            ([.control, .command], 0x0C, .reserved),   // ⌃⌘Q ekranı kilitler
        ]
        for (modifiers, code, expected) in cases {
            XCTAssertEqual(HotkeyTable.validate(HotkeyKey(modifiers, code)), expected, HotkeyKey(modifiers, code).label)
        }
    }

    /// Seçim ayarlarla kaydedilip geri okunur; eski kayıt (kısayol yok) ve bozuk tek bir kayıt varsayılanları bozmaz.
    func testChoicesSurviveTheSettingsFile() throws {
        var settings = UserSettings()
        settings.hotkeys = HotkeyTable.assign([], .screen, slot: 0, key: HotkeyKey([.option, .command], 0x11)).choices
        settings.hotkeys = HotkeyTable.assign(settings.hotkeys, .screen, slot: 1, key: nil).choices
        settings.freeAreaTarget = .both
        let data = try JSONEncoder().encode(settings)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"Screen\""))
        let loaded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(HotkeyTable.resolve(loaded.hotkeys), HotkeyTable.resolve(settings.hotkeys))
        XCTAssertEqual(loaded.freeAreaTarget, .both)
        let old = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.hotkeys.isEmpty)
        XCTAssertEqual(old.freeAreaTarget, .tv)
        let broken = #"{"hotkeys":[{"action":"Teleport","slot":0},{"action":"Screen","slot":1,"key":{"modifiers":2304,"keyCode":17}}]}"#
        let partly = try JSONDecoder().decode(UserSettings.self, from: Data(broken.utf8))
        XCTAssertEqual(partly.hotkeys.count, 1)
        XCTAssertEqual(HotkeyTable.key(partly.hotkeys, .screen, slot: 1), HotkeyKey([.option, .command], 0x11))
    }

    /// Önceki Mac sürümünden gelen ayar (kısayol alanı yok): ⌥⌘T ve ⌥⌘L ikinci tuş olur, Num tuşları da çalışır.
    /// Yeni kurulumda (ayar yok) ya da yeni biçimdeki ayarda bir şey değişmez.
    func testLegacyMacShortcutsStayForUpgrades() throws {
        XCTAssertTrue(LegacyMacHotkeys.isLegacy(Data(#"{"sourceLanguage":"en","output":"tv"}"#.utf8)))
        XCTAssertFalse(LegacyMacHotkeys.isLegacy(nil))
        XCTAssertFalse(LegacyMacHotkeys.isLegacy(try JSONEncoder().encode(UserSettings())))
        let choices = LegacyMacHotkeys.apply([])
        XCTAssertEqual(HotkeyTable.keys(choices, .screen), [HotkeyKey([], 0x5C), HotkeyKey([.option, .command], 0x11)])
        XCTAssertEqual(HotkeyTable.keys(choices, .clickThrough), [HotkeyKey([], 0x59), HotkeyKey([.option, .command], 0x25)])
        XCTAssertEqual(LegacyMacHotkeys.screen.label, "⌥⌘T")
        XCTAssertEqual(LegacyMacHotkeys.clickThrough.label, "⌥⌘L")
        // ⌥⌘ birleşimleri macOS 15 kısıtına girmez (yalnız ⌥ / ⌥⇧ girer).
        XCTAssertEqual(HotkeyTable.validate(LegacyMacHotkeys.screen), .none)
        XCTAssertEqual(HotkeyTable.validate(LegacyMacHotkeys.clickThrough), .none)
        // Diğer işler varsayılanda kalır.
        XCTAssertEqual(HotkeyTable.keys(choices, .freeArea), HotkeyTable.keys([], .freeArea))
    }

    func testAreaActionsAreNumbered() {
        XCTAssertEqual(HotkeyAction.extraRegion1.areaNumber, 1)
        XCTAssertEqual(HotkeyAction.extraRegion3.areaNumber, 3)
        XCTAssertNil(HotkeyAction.screen.areaNumber)
    }
}

/// Alanın tek seferlik çevirisi (Windows RegionTranslationTests ile aynı örnekler).
final class RegionTranslationTests: XCTestCase {
    private final class Reader: TextReader, @unchecked Sendable {
        var reading: Reading
        init(_ reading: Reading) { self.reading = reading }
        func read(_ image: CGImage) throws -> String { reading.text }
        func read(_ image: CGImage, deep: Bool) throws -> String { reading.text }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { reading }
    }

    private final class Translator: TextTranslator {
        func translate(_ text: String) async throws -> String { "TR: " + text }
    }

    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func lines(_ texts: String...) -> Reading { Reading(lines: texts.map { TextLine($0) }) }

    func testLinesOfOneSentenceAreJoined() {
        XCTAssertEqual(RegionTranslation.blocks(lines("Find the blacksmith in", "the village square")).map(\.text),
                       ["Find the blacksmith in the village square"])
    }

    func testFinishedSentenceStartsANewBlock() {
        XCTAssertEqual(RegionTranslation.blocks(lines("Find the blacksmith.", "Bring him three iron bars.")).map(\.text),
                       ["Find the blacksmith.", "Bring him three iron bars."])
    }

    func testBigGapStartsANewBlockAndBulletsAreKept() {
        let reading = Reading(lines: [
            TextLine("Current quest", box: TextBox(left: 0, top: 0.00, right: 1, bottom: 0.10)),
            TextLine("Find the blacksmith", box: TextBox(left: 0, top: 0.30, right: 1, bottom: 0.40)),
            TextLine("in the square", box: TextBox(left: 0, top: 0.42, right: 1, bottom: 0.52)),
            TextLine("◇ Bring iron", box: TextBox(left: 0, top: 0.54, right: 1, bottom: 0.64)),
        ])
        XCTAssertEqual(RegionTranslation.blocks(reading),
                       [.init(text: "Current quest", bullet: false), .init(text: "Find the blacksmith in the square", bullet: false),
                        .init(text: "Bring iron", bullet: true)])
    }

    func testNoTextGivesNil() async throws {
        let result = try await RegionTranslation.translateOnce(image(), region: CropRegion(), reader: Reader(.empty), translator: Translator())
        XCTAssertNil(result)
    }

    func testBlocksAreTranslatedAndPlacedInTheRegion() async throws {
        let reading = Reading(lines: [TextLine("Find the blacksmith.", box: TextBox(left: 0, top: 0, right: 1, bottom: 0.5)),
                                      TextLine("• Bring iron.", box: TextBox(left: 0, top: 0.5, right: 1, bottom: 1))])
        let region = CropRegion(top: 0.1, bottom: 0.3, left: 0.6, right: 1)
        let result = try await RegionTranslation.translateOnce(image(), region: region, reader: Reader(reading), translator: Translator())
        XCTAssertEqual(result?.translation, "TR: Find the blacksmith.\n• TR: Bring iron.")
        XCTAssertEqual(result?.structured, true)
        XCTAssertEqual(result?.box, TextBox(left: 0.6, top: 0.1, right: 1, bottom: 0.3))
    }

    func testDisplayTimeGrowsWithTheText() {
        XCTAssertEqual(RegionTranslation.displayMilliseconds("kısa"), 6000)
        XCTAssertEqual(RegionTranslation.displayMilliseconds(String(repeating: "a", count: 1000)), 25000)
    }
}
