// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Ek alan modeli dört platformda aynı: adlı liste, en çok üç; her alanın yeri, "sürekli oku" seçimi ve kısayolla
/// okununca sonucun gösterildiği yer (Windows ExtraAreaMigrationTests/ExtraRegionTests, Android AreasTest ile aynı örnekler).
final class ExtraAreaModelTests: XCTestCase {
    /// Hedef seçimi kaydedilir ve geri okunur.
    func testTargetRoundTrips() throws {
        var settings = UserSettings()
        settings.extraAreas = [ExtraArea(id: "area1", name: "Görev", region: ExtraAreaPreset.quest.region, enabled: false, target: .both)]
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.extraAreas, settings.extraAreas)
        XCTAssertEqual(decoded.extraAreas.first?.target, .both)
    }

    /// Eski kayıtta hedef yoktur: TV sayılır, diğer alanlar kaybolmaz.
    func testOldRecordWithoutTargetShowsOnTheTV() throws {
        let json = #"{"extraAreas":[{"id":"q","name":"Görev","region":{"top":0.03,"bottom":0.3,"left":0.66,"right":0.98},"enabled":false}]}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        let area = try XCTUnwrap(settings.extraAreas.first)
        XCTAssertEqual(area.id, "q")
        XCTAssertEqual(area.name, "Görev")
        XCTAssertFalse(area.enabled)
        XCTAssertEqual(area.target, .tv)
    }

    /// Bilinmeyen hedef değeri ayarları bozmaz.
    func testUnknownTargetFallsBackToTV() throws {
        let json = #"{"extraAreas":[{"id":"q","name":"","region":{"top":0.03,"bottom":0.3,"left":0.66,"right":0.98},"target":"watch"}]}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.extraAreas.first?.target, .tv)
    }

    /// Yeni alan sürekli okunur ve sonucu TV'de gösterir; sıradaki alan kısayolun numarasıyla bulunur.
    func testNewAreaDefaultsAndNumbering() {
        var settings = UserSettings()
        let first = settings.addExtraArea(.quest, name: "Görev")
        let second = settings.addExtraArea(.phone, name: "")
        XCTAssertEqual(settings.extraArea(at: 1)?.id, first)
        XCTAssertEqual(settings.extraArea(at: 2)?.id, second)
        XCTAssertNil(settings.extraArea(at: 3))
        XCTAssertNil(settings.extraArea(at: 0))
        XCTAssertTrue(settings.extraAreas.allSatisfy { $0.enabled && $0.target == .tv })
        XCTAssertEqual(settings.extraArea(at: 1)?.displayName(1), "Görev")
        XCTAssertFalse(settings.extraArea(at: 2)?.displayName(2).isEmpty ?? true)
        // Silinen alanın arkasındaki öne gelir.
        settings.removeExtraArea(id: first!)
        XCTAssertEqual(settings.extraArea(at: 1)?.id, second)
    }

    func testTargetRouting() {
        XCTAssertTrue(ResultTarget.tv.toTV)
        XCTAssertFalse(ResultTarget.tv.toComputer)
        XCTAssertFalse(ResultTarget.pc.toTV)
        XCTAssertTrue(ResultTarget.pc.toComputer)
        XCTAssertTrue(ResultTarget.both.toTV && ResultTarget.both.toComputer)
    }
}
