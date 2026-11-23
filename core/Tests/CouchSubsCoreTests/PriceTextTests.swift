// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// "Ekranı çevir": fiyatlar, sayılar ve tuş çubukları. Fiyat kuralları ortak deneme dosyasından (Fixtures/price-text.json;
/// Windows PriceTextTests.cs ve Android PriceTextTest.kt aynı dosyayı okur).
final class PriceTextTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Protect: Decodable { let text, sent, reply, result: String }
        let repair: [[String]]
        let protect: [Protect]
    }

    private func fixture() throws -> (Vectors, [(String, Bool)]) {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("price-text.json")
        let data = try Data(contentsOf: url)
        let vectors = try JSONDecoder().decode(Vectors.self, from: data)
        // "money" satırları [metin, mantıksal] karışık dizi: elle okunur.
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let money = (raw["money"] as! [[Any]]).map { ($0[0] as! String, $0[1] as! Bool) }
        return (vectors, money)
    }

    func testSharedVectors() throws {
        let (vectors, money) = try fixture()
        for pair in vectors.repair { XCTAssertEqual(PriceText.repair(pair[0]), pair[1], pair[0]) }
        for (word, expected) in money { XCTAssertEqual(PriceText.isMoney(word), expected, word) }
        for vector in vectors.protect {
            let protected = PriceText.protect(vector.text)
            func fill(_ template: String) -> String {
                protected.values.enumerated().reduce(template) { $0.replacingOccurrences(of: "{\($1.offset)}", with: $1.element.name) }
            }
            XCTAssertEqual(protected.text, fill(vector.sent), vector.text)
            XCTAssertEqual(PriceText.restore(fill(vector.reply), protected.values), vector.result, vector.text)
        }
    }

    private func line(_ text: String, _ left: Double, _ top: Double, _ right: Double, words: [(String, Double, Double)]? = nil) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: top + 0.03),
                 words: words?.map { TextWord($0.0, box: TextBox(left: $0.1, top: top, right: $0.2, bottom: top + 0.03)) })
    }

    /// Sağ alttaki tuş çubuğu: "SCROLL R3 SEND ✕ BACK ○" atılmıyor; tuşlar çeviriye girmeden yerinde kalıyor, her
    /// etiket kendi kutusunda sözlükten çevriliyor (çeviriler üst üste binmiyor).
    func testPromptBarLabelsAreTranslatedOneByOneAndButtonsStay() async throws {
        let bar = line("SCROLL R3 SEND ✕ BACK ○", 0.70, 0.92, 0.98, words: [
            ("SCROLL", 0.70, 0.76), ("R3", 0.77, 0.79), ("SEND", 0.81, 0.85), ("✕", 0.86, 0.87), ("BACK", 0.89, 0.93), ("○", 0.94, 0.95),
        ])
        var asked: [String] = []
        let items = try await ScreenTranslation.translate(Reading(lines: [bar]), using: { asked.append($0); return $0 })
        XCTAssertEqual(asked, [], "sözlükteki etiketler çevirmene gitmez")
        XCTAssertEqual(items.map(\.translation), ["KAYDIR", "GÖNDER", "GERİ"])
        XCTAssertEqual(items.map(\.box.left), [0.70, 0.81, 0.89])
        XCTAssertEqual(items.map(\.box.right), [0.76, 0.85, 0.93])
        for (a, b) in zip(items, items.dropFirst()) { XCTAssertLessThan(a.box.right, b.box.left) }
    }

    /// Bar menüsü: aynı satıra düşmüş seçenekler geniş boşluktan ayrılır; fiyat çeviriye girmez ve bozulmaz.
    func testOptionsOnOneRowBecomeSeparateBoxesAndPricesStay() async throws {
        let row = line("TIP S10 ORDER BARTENDER", 0.30, 0.80, 0.80, words: [
            ("TIP", 0.30, 0.34), ("S10", 0.35, 0.39), ("ORDER", 0.50, 0.57), ("BARTENDER", 0.68, 0.80),
        ])
        let items = try await ScreenTranslation.translate(Reading(lines: [row]), using: { $0 })
        XCTAssertEqual(items.map(\.translation), ["BAHŞİŞ VER", "SİPARİŞ VER", "BARMEN"])
        XCTAssertEqual(items[0].box.right, 0.34, "fiyat ($10) etiketin kutusuna girmez, ekranda görünür kalır")
    }

    /// Dükkân: "SSSS" (yazı tanımanın okuduğu "$$$$") artık yazı sayılıp çevrilmiyor; cümledeki fiyat korunuyor.
    func testMisreadPricesAreNotTranslatedAndPricesInSentencesSurvive() async throws {
        var asked: [String] = []
        let items = try await ScreenTranslation.translate(Reading(lines: [
            line("SSSS", 0.10, 0.10, 0.16), line("Buy the jacket for S200", 0.10, 0.50, 0.50),
        ]), using: { text in
            asked.append(text)
            return text.replacingOccurrences(of: "Buy the jacket for ", with: "Ceketi şu fiyata al: ")
        })
        XCTAssertEqual(asked.count, 1)
        XCTAssertFalse(asked[0].contains("$") || asked[0].contains("S200"), asked[0])
        XCTAssertEqual(items.map(\.translation), ["Ceketi şu fiyata al: $200"])
    }
}
