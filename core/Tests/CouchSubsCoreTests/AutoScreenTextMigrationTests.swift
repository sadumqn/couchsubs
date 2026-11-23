// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// "Ekran yazılarını otomatik çevir" varsayılan kapalı; beta.63'te açık gelen ayar bir kez kapatılır (Windows
/// AutoScreenTextMigration, Android aynı kural).
final class AutoScreenTextMigrationTests: XCTestCase {
    func testOffByDefaultAndInOldSettings() throws {
        XCTAssertFalse(UserSettings().autoScreenText)
        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"showSpeakerNames": false}"#.utf8))
        XCTAssertFalse(old.autoScreenText)
        XCTAssertFalse(old.autoScreenTextReset)
    }

    func testBeta63SettingIsTurnedOffOnceWithANotice() throws {
        var beta63 = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"autoScreenText": true}"#.utf8))
        XCTAssertTrue(beta63.migratingAutoScreenText())
        XCTAssertFalse(beta63.autoScreenText)
        XCTAssertTrue(beta63.autoScreenTextReset)
        // Kaydedilip yeniden açılınca göç tekrarlanmaz; kullanıcı açtıysa açık kalır.
        var reopened = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(beta63))
        reopened.autoScreenText = true
        XCTAssertFalse(reopened.migratingAutoScreenText())
        XCTAssertTrue(reopened.autoScreenText)
    }

    func testFreshInstallIsMigratedSilently() {
        var fresh = UserSettings()
        XCTAssertFalse(fresh.migratingAutoScreenText())
        XCTAssertFalse(fresh.autoScreenText)
        XCTAssertTrue(fresh.autoScreenTextReset)
    }

    /// Hazır alanlar kullanıcının altyazı alanını ve ek alanlarını değiştirmez (yalnız okunacak alan listesine eklenir).
    func testPresetAreasLeaveTheUsersAreasAlone() {
        var settings = UserSettings()
        settings.region = CropRegion(top: 0.7, bottom: 0.9, left: 0.2, right: 0.8)
        let before = settings
        _ = settings.watchedExtraAreas(game: "GTA 6", phoneOpen: false)
        XCTAssertEqual(settings, before)
        XCTAssertEqual(settings.region, CropRegion(top: 0.7, bottom: 0.9, left: 0.2, right: 0.8))
        XCTAssertTrue(settings.extraAreas.isEmpty)
    }

    /// beta.63–68: hazır alanlar varsayılan açıktı; otomatik ekran yazısı kapalıyken de GTA 6'da menü ve bildirimler
    /// çevriliyordu. Göç ikisini (hazır alanlar, GTA 6 telefonu) bir kez kapatır.
    func testPresetsAndPhoneAreTurnedOffOnceWhenAutoScreenTextIsOff() throws {
        var beta68 = try JSONDecoder().decode(UserSettings.self, from: Data(
            #"{"autoScreenText": false, "autoScreenTextReset": true, "gameAreaPresets": true, "autoReadGamePhone": true}"#.utf8))
        beta68.migratingAutoScreenText()
        XCTAssertTrue(beta68.migratingScreenTextExtras())
        XCTAssertFalse(beta68.gameAreaPresets)
        XCTAssertFalse(beta68.autoReadGamePhone)
        XCTAssertTrue(beta68.screenTextExtrasReset)
        XCTAssertTrue(beta68.watchedExtraAreas(game: "GTA 6").isEmpty)
        XCTAssertFalse(beta68.readsGamePhone)
        // Kullanıcı sonra bilerek açarsa göç tekrarlanmaz, açık kalır.
        var reopened = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(beta68))
        reopened.gameAreaPresets = true
        reopened.autoReadGamePhone = true
        XCTAssertFalse(reopened.migratingScreenTextExtras())
        XCTAssertTrue(reopened.gameAreaPresets)
        XCTAssertTrue(reopened.autoReadGamePhone)
    }

    /// beta.63 kaydı (otomatik ekran yazısı açık geliyordu): önce o kapatılır, ardından hazır alanlar da kapanır.
    func testBeta63RecordLosesPresetsToo() throws {
        var beta63 = try JSONDecoder().decode(UserSettings.self, from: Data(
            #"{"autoScreenText": true, "gameAreaPresets": true}"#.utf8))
        beta63.migratingAutoScreenText()
        beta63.migratingScreenTextExtras()
        XCTAssertFalse(beta63.autoScreenText)
        XCTAssertFalse(beta63.gameAreaPresets)
    }

    /// Kullanıcı otomatik ekran yazısını kendisi açmışsa hazır alanlara ve telefona dokunulmaz.
    func testUsersWhoTurnedAutoScreenTextOnKeepPresets() throws {
        var on = try JSONDecoder().decode(UserSettings.self, from: Data(
            #"{"autoScreenText": true, "autoScreenTextReset": true, "gameAreaPresets": true, "autoReadGamePhone": true}"#.utf8))
        on.migratingAutoScreenText()
        XCTAssertFalse(on.migratingScreenTextExtras())
        XCTAssertTrue(on.autoScreenText)
        XCTAssertTrue(on.gameAreaPresets)
        XCTAssertTrue(on.autoReadGamePhone)
        XCTAssertTrue(on.screenTextExtrasReset)
    }

    /// Otomatik ekran yazısı kapalıyken (varsayılan) altyazı alanı dışında okunan hiçbir alan yok: hazır alan ve telefon
    /// yok (görev satırı ve menü alanı da yalnız otomatik ekran yazısı açıkken eklenir).
    func testNothingOutsideTheSubtitleAreaByDefault() {
        var fresh = UserSettings()
        fresh.migratingAutoScreenText()
        fresh.migratingScreenTextExtras()
        XCTAssertTrue(fresh.watchedExtraAreas(game: "GTA 6").isEmpty)
        XCTAssertTrue(fresh.watchedExtraAreas(game: "Grand Theft Auto VI").isEmpty)
        XCTAssertFalse(fresh.readsGamePhone)
        XCTAssertFalse(fresh.autoScreenText)
    }
}
