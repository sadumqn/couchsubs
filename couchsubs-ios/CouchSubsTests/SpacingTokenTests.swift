// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest

/// Görünümler boşluğu ham sayıyla yazmaz: `spacing:` ve `.padding(…)` yalnız `Mobile.Space` adlarını (ya da 0) kullanır.
/// Ölçü seti tek yerde (MobileTheme.swift › Mobile.Space ve UI/Yeni bileşenleri); bir ekranda "10" ya da "14" gibi
/// değer görünürse sayfalar arasında ritim bozulur.
final class SpacingTokenTests: XCTestCase {
    /// Boşluğu tanımlayan dosyalar (ham değer burada olur).
    private static let allowed = ["MobileTheme.swift", "/UI/Yeni/"]

    func testViewsUseSpacingTokens() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CouchSubs", isDirectory: true)
        let pattern = try NSRegularExpression(pattern: #"(spacing:\s*-?[1-9][0-9.]*\b|\.padding\(\s*(\.[a-zA-Z]+\s*,\s*)?-?[1-9][0-9.]*\s*\))"#)
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "Kaynak dosyalar bulunamadı: \(sources.path)")
        for file in files where !Self.allowed.contains(where: { file.path.contains($0) }) {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if pattern.firstMatch(in: line, range: range) != nil {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Ham boşluk değeri (Mobile.Space kullanın):\n" + offenders.joined(separator: "\n"))
    }
}
