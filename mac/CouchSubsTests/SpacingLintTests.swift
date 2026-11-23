// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest

/// Boşluk denetimi: yeni arayüzün ekran dosyalarında (mac/CouchSubs/UI/Yeni) ham sayıyla boşluk yazılmaz; her boşluk
/// tasarim.json › space belirteçlerinden gelir (DS.space(...), DS.unitGap …). Sıfır (boşluksuz yığın) serbesttir.
/// İstisnalar tek yerde, gerekçesiyle `allowed` listesinde. Bileşen tanımları (DS.swift, DSComponents.swift) bileşenin
/// kendi geometrisini (düğmecik payı, rozet iç boşluğu) içerdiği için taranmaz.
final class SpacingLintTests: XCTestCase {
    /// "Dosya: satırın içeriği" → gerekçe.
    static let allowed: [String: String] = [
        "HomeView.swift: HStack(alignment: .bottom, spacing: 3) {": "Gecikme çubuk grafiğinin çubuk aralığı (grafik geometrisi, ritim değil).",
        "SettingsPage.swift: ScrollView(.vertical) { VStack(spacing: DS.space(\"l\")) { left }.padding(.bottom, 1) }":
            "Kaydırma görünümünün alt kenarı kartın 1 pt çerçevesini kırpmasın.",
        "SettingsPage.swift: ScrollView(.vertical) { VStack(spacing: DS.space(\"l\")) { right }.padding(.bottom, 1) }":
            "Kaydırma görünümünün alt kenarı kartın 1 pt çerçevesini kırpmasın.",
        "WizardView.swift: StepBody().frame(maxWidth: .infinity, alignment: .topLeading).padding(.bottom, 2)":
            "Kaydırma görünümünün alt kenarı kartın gölgesini kırpmasın.",
    ]
    /// Bileşen tanımları: DS.swift, DSComponents.swift ve Perde bileşenleri (Perde.swift; Mac ve iPhone ortak). Bileşen
    /// kataloğu (PerdeCatalog.swift) bir ekran gibi taranır.
    static let skipped: Set<String> = ["DS.swift", "DSComponents.swift", "Perde.swift"]

    private static let pattern = try! NSRegularExpression(
        pattern: #"spacing:\s*-?[1-9][0-9.]*|\.padding\((\.[a-zA-Z]+,\s*|\[[^\]]*\],\s*)?-?[1-9][0-9.]*\)|Spacer\(minLength:\s*[1-9]"#)

    func testScreensUseSpacingTokensOnly() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CouchSubs/UI/Yeni", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && !Self.skipped.contains($0.lastPathComponent) }
        XCTAssertFalse(files.isEmpty)
        var violations: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard Self.pattern.firstMatch(in: line, range: range) != nil else { continue }
                let key = "\(file.lastPathComponent): \(trimmed)"
                if Self.allowed[key] == nil { violations.append("\(file.lastPathComponent):\(number + 1): \(trimmed)") }
            }
        }
        print("SPACING_LINT violations=\(violations.count)")
        XCTAssertEqual(violations, [], "Ham boşluk sayısı yerine DS.space(...) belirteci kullanın ya da gerekçesiyle izin listesine ekleyin.")
    }
}
