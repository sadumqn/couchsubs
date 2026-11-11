// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// Tasarım değerleri design/tokens.json'dan gelir (Windows sürümü de aynı dosyayı kullanır).
/// Bu testler yazıların her iki görünümde de rahat okunmasını güvenceye alır.
final class ThemeTests: XCTestCase {
    private let tokens = Theme.tokens
    private let modes: [KeyPath<DesignTokens.ColorPair, String>] = [\.light, \.dark]

    private func assertContrast(_ text: String, on background: String, atLeast minimum: Double,
                                file: StaticString = #filePath, line: UInt = #line) {
        for mode in modes {
            let foreground = tokens.color[text]![keyPath: mode], back = tokens.color[background]![keyPath: mode]
            let ratio = DesignTokens.contrast(foreground, back)
            XCTAssertGreaterThanOrEqual(ratio, minimum, "\(text) / \(background) (\(foreground) – \(back)): \(ratio)", file: file, line: line)
        }
    }

    func testTokensAreBundledWithTheApp() {
        XCTAssertEqual(tokens.name, "CouchSubs")
        for (name, pair) in tokens.color {
            XCTAssertNotNil(DesignTokens.rgb(pair.light), name)
            XCTAssertNotNil(DesignTokens.rgb(pair.dark), name)
        }
    }

    func testContrastFormulaMatchesWCAG() {
        XCTAssertEqual(DesignTokens.contrast("#000000", "#FFFFFF"), 21, accuracy: 0.01)
        XCTAssertEqual(DesignTokens.contrast("#777777", "#FFFFFF"), 4.48, accuracy: 0.01)
    }

    func testMainTextIsHighlyReadable() {
        assertContrast("textPrimary", on: "background", atLeast: 7)
        assertContrast("textPrimary", on: "surface", atLeast: 7)
    }

    func testSecondaryAndColoredTextIsReadable() {
        for text in ["textSecondary", "accentText", "success", "warning", "danger"] {
            assertContrast(text, on: "background", atLeast: 4.5)
            assertContrast(text, on: "surface", atLeast: 4.5)
        }
        assertContrast("accentText", on: "accentSoft", atLeast: 4.5)
        // Paket moru, tonlu zeminler ve ikinci yüzey (alanlar, ikincil düğme).
        assertContrast("pro", on: "background", atLeast: 4.5)
        assertContrast("pro", on: "surface", atLeast: 4.5)
        assertContrast("pro", on: "proSoft", atLeast: 4.5)
        assertContrast("success", on: "successSoft", atLeast: 4.5)
        assertContrast("danger", on: "dangerSoft", atLeast: 4.5)
        assertContrast("textPrimary", on: "surface2", atLeast: 7)
        assertContrast("textSecondary", on: "surface2", atLeast: 4.5)
    }

    func testGlowsAreDefined() {
        for name in ["primary", "primaryDrop", "activeTile", "activeBorder", "pro", "backgroundAccent", "backgroundPro"] {
            let glow = tokens.glow[name]
            XCTAssertNotNil(glow.flatMap { DesignTokens.rgb($0.color) }, name)
            XCTAssertLessThanOrEqual(glow?.opacity ?? 1, 0.6, "parıltı metnin okunmasını bozmasın: \(name)")
        }
    }

    func testButtonTextIsReadable() {
        assertContrast("onAccent", on: "accent", atLeast: 4.5)
        assertContrast("onDanger", on: "danger", atLeast: 4.5)
    }

    /// macOS'un varsayılan 13 pt'si TV karşısından okunurken küçük kalıyordu.
    func testTextIsLargerThanSystemDefault() {
        XCTAssertGreaterThanOrEqual(tokens.font["body"]!.size, 15)
        XCTAssertGreaterThanOrEqual(tokens.font["caption"]!.size, 12)
    }
}
