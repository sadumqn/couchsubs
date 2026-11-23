// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Oyuna göre alan profilinin ne zaman uygulandığı ve `GameAreas` akışı (Windows AreaProfilesTests/AreaProfileTests ve
/// Android AreaProfilesTest ile aynı örnekler).
final class AreaProfilesTests: XCTestCase {
    private let farCry = "far cry 3|stream"
    private let general = CropRegion(top: 0.62, bottom: 0.97, left: 0.14, right: 0.86)
    private let farCryArea = CropRegion(top: 0.70, bottom: 0.95, left: 0.20, right: 0.80)

    private func run(_ active: String?, _ game: String?, _ source: GameSense.Source?, area: AreaSource = .stream,
                     saved: [String]? = nil, declined: [String] = []) -> AreaProfiles.Step {
        let saved = saved ?? [farCry]
        return AreaProfiles.decide(active: active, game: game, source: source, areaSource: area,
                                   exists: { saved.contains($0) }, declined: { declined.contains($0) })
    }

    func testKeyUsesTheServersGameKeyAndTheSource() {
        XCTAssertEqual(AreaProfiles.key("Grand Theft Auto VI", source: .stream), "gta 6|stream")
        XCTAssertEqual(AreaProfiles.key("GTA 6", source: .window), "gta 6|window")
        XCTAssertNil(AreaProfiles.key("", source: .stream))
        XCTAssertNil(AreaProfiles.key(nil, source: .stream))
    }

    func testACertainGameAppliesAndAPackGuessIsOffered() {
        XCTAssertEqual(run(nil, "Far Cry 3", .console), .apply(farCry))
        XCTAssertEqual(run(nil, "Far Cry 3", .user), .apply(farCry))
        XCTAssertEqual(run(nil, "Far Cry 3", .pack), .offer(farCry))
    }

    func testTheSameProfileOrAnUnknownGameChangesNothing() {
        XCTAssertEqual(run(farCry, "Far Cry III", .console), AreaProfiles.Step.none)
        XCTAssertEqual(run(farCry, nil, nil), AreaProfiles.Step.none)
        XCTAssertEqual(run(nil, nil, nil), AreaProfiles.Step.none)
    }

    func testAnotherGameSwitchesOrGoesBackToTheGeneralAreas() {
        XCTAssertEqual(run(farCry, "Hades", .console), .useGeneral)
        XCTAssertEqual(run(nil, "Hades", .console), AreaProfiles.Step.none)
        XCTAssertEqual(run(farCry, "Hades", .user, saved: [farCry, "hades|stream"]), .apply("hades|stream"))
    }

    func testADeclinedProfileIsNotAppliedOrOfferedAgain() {
        XCTAssertEqual(run(nil, "Far Cry 3", .console, declined: [farCry]), AreaProfiles.Step.none)
        XCTAssertEqual(run(nil, "Far Cry 3", .pack, declined: [farCry]), AreaProfiles.Step.none)
        XCTAssertEqual(run("hades|stream", "Far Cry 3", .console, declined: [farCry]), .useGeneral)
    }

    func testTheWindowSourceHasItsOwnProfile() {
        XCTAssertEqual(run(nil, "Far Cry 3", .console, area: .window), AreaProfiles.Step.none)
        XCTAssertEqual(run(nil, "Far Cry 3", .console, area: .window, saved: [farCry, "far cry 3|window"]),
                       .apply("far cry 3|window"))
    }

    func testSavingMovesTheProfileToTheEndAndKeepsTwenty() {
        XCTAssertEqual(AreaProfiles.saved(["a", "b", "c"], "b") { $0 }, ["a", "c", "b"])
        let full = (0..<AreaProfiles.maxCount).map { "g\($0)" }
        let next = AreaProfiles.saved(full, "new") { $0 }
        XCTAssertEqual(next.count, AreaProfiles.maxCount)
        XCTAssertEqual(next.first, "g1")
        XCTAssertEqual(next.last, "new")
    }

    // MARK: - GameAreas

    @MainActor
    func testSavedAreasComeBackWithTheGameAndTheSessionEndsWithTheGeneralAreas() {
        var store = UserSettings()
        store.setCustomRegion(general)
        let areas = GameAreas(read: { store }, write: { store = $0 })
        XCTAssertNil(areas.target)
        areas.save()
        XCTAssertTrue(store.areaProfiles.isEmpty)

        areas.start()
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .user)
        XCTAssertEqual(areas.target, "Far Cry 3")
        store.setCustomRegion(farCryArea)
        store.extraAreas = [ExtraArea(name: "Görev", region: ExtraAreaPreset.quest.region)]
        areas.save()
        XCTAssertEqual(store.areaProfiles.map(\.key), [farCry])
        XCTAssertEqual(areas.activeGame, "Far Cry 3")
        XCTAssertFalse(areas.unsaved)
        areas.stop()

        // Profil yokken yapılan değişiklik genel ayardı: genel alanlar yeniden ayarlanır.
        store.setCustomRegion(general)
        store.extraAreas = []
        areas.start()
        areas.follow(game: RunningGame(name: "Far Cry III"), source: .console)
        XCTAssertEqual(store.region, farCryArea)
        XCTAssertEqual(store.extraAreas.count, 1)
        XCTAssertEqual(store.generalAreas?.region, general)

        store.setCustomRegion(general)
        XCTAssertTrue(areas.unsaved)
        areas.stop()
        XCTAssertEqual(store.region, general)
        XCTAssertTrue(store.extraAreas.isEmpty)
        XCTAssertNil(store.activeAreaProfile)
        XCTAssertNil(store.generalAreas)
        XCTAssertEqual(store.areaProfiles.first?.areas.region, farCryArea)
    }

    @MainActor
    func testUndoOfferAndAnotherGame() {
        var store = UserSettings()
        store.setCustomRegion(general)
        store.areaProfiles = [AreaProfile(key: farCry, game: "Far Cry 3",
                                          areas: AreaSet(region: farCryArea, areaPreset: .custom, extraAreas: []))]
        let areas = GameAreas(read: { store }, write: { store = $0 })
        areas.start()

        // Paketten tanınan oyunda sorulur; "Hayır" bu oturumda yeniden sormaz.
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .pack)
        XCTAssertEqual(areas.offeredGame, "Far Cry 3")
        XCTAssertEqual(store.region, general)
        areas.declineOffered()
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .pack)
        XCTAssertNil(areas.offered)
        areas.stop()

        // "Kullan".
        areas.start()
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .pack)
        areas.useOffered()
        XCTAssertEqual(store.region, farCryArea)
        // Elle seçilince aynı profil yeniden uygulanmaz.
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .user)
        XCTAssertEqual(store.activeAreaProfile, farCry)

        // "Geri al": genel alanlar, aynı oturumda yeniden uygulanmaz.
        areas.undo()
        XCTAssertEqual(store.region, general)
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .console)
        XCTAssertEqual(store.region, general)
        areas.stop()

        // Başka (profilsiz) oyun genel alanlara döndürür; silme de.
        areas.start()
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .console)
        XCTAssertEqual(store.region, farCryArea)
        areas.follow(game: RunningGame(name: "Hades"), source: .console)
        XCTAssertEqual(store.region, general)
        areas.follow(game: RunningGame(name: "Far Cry 3"), source: .console)
        areas.delete()
        XCTAssertTrue(store.areaProfiles.isEmpty)
        XCTAssertEqual(store.region, general)
    }

    @MainActor
    func testAProfileLeftOpenIsClosedAtStartupAndOldSettingsHaveNone() throws {
        var open = UserSettings()
        open.setCustomRegion(general)
        open.saveAreaProfile(for: "Far Cry 3")
        open.setCustomRegion(farCryArea)
        let restored = GameAreas.restored(open)
        XCTAssertEqual(restored.region, general)
        XCTAssertNil(restored.activeAreaProfile)
        XCTAssertEqual(restored.areaProfiles.count, 1)

        let old = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"region":{"top":0.5,"bottom":0.9,"left":0.1,"right":0.9}}"#.utf8))
        XCTAssertTrue(old.areaProfiles.isEmpty)
        XCTAssertNil(old.activeAreaProfile)
        let copy = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(copy.areaProfiles, restored.areaProfiles)
    }

    // MARK: - Oyun profilleri (her oyun bağımsız)

    private let gta = "gta 6|stream"
    private let gtaArea = CropRegion(top: 0.74, bottom: 0.93, left: 0.18, right: 0.82)
    private let acArea = CropRegion(top: 0.80, bottom: 0.98, left: 0.10, right: 0.90)

    func testARememberedChoiceIsOfferedNotApplied() {
        XCTAssertEqual(run(nil, "Far Cry 3", .remembered), .offer(farCry))
        XCTAssertEqual(run(farCry, "Hades", .remembered), .useGeneral)
    }

    func testAChoiceFromAnEarlierSessionIsRemembered() {
        let sense = GameSense()
        sense.choose("Grand Theft Auto VI")
        sense.startSession()
        // Çeviri dururken (Ayarlar'da) seçilen oyun bu oturum içindir.
        XCTAssertEqual(sense.source, .user)
        sense.endSession()
        sense.startSession()
        XCTAssertEqual(sense.source, .user)
        sense.choose("GTA 6")
        XCTAssertEqual(sense.source, .user)
        sense.endSession()
        // Oturumda seçilen oyun sonraki oturumda yalnız hatırlanır.
        sense.startSession()
        XCTAssertEqual(sense.source, .remembered)
        XCTAssertEqual(sense.current?.name, "GTA 6")
        sense.choose("Assassin's Creed Valhalla")
        XCTAssertEqual(sense.source, .user)
    }

    /// Kullanıcının bildirdiği durum: GTA 6 için alanlar kaydedildi, sonraki oturumda Assassin's Creed oynandı, oyun
    /// seçimi GTA 6'da kaldı. Eskiden GTA 6 profili kendiliğinden uygulanıyor, AC için yapılan değişiklik "Profile
    /// kaydet" ile GTA 6'nın üzerine yazılıyordu.
    @MainActor
    func testAnotherGamesAreasNeverOverwriteAProfile() {
        var store = UserSettings()
        store.setCustomRegion(general)
        let sense = GameSense()
        let areas = GameAreas(read: { store }, write: { store = $0 })
        areas.onChoose = { sense.choose($0) }

        sense.startSession()
        areas.start()
        sense.choose("GTA 6")
        areas.follow(game: sense.current, source: sense.source)
        store.setCustomRegion(gtaArea)
        areas.save()
        XCTAssertEqual(store.areaProfiles.map(\.key), [gta])
        areas.stop()
        sense.endSession()
        store.setCustomRegion(general)

        // Sonraki oturum: seçim GTA 6'da kaldı ama oyun AC. Profil sorulur, uygulanmaz; kaydet GTA 6'ya yazmaz.
        sense.startSession()
        areas.start()
        areas.follow(game: sense.current, source: sense.source)
        XCTAssertEqual(areas.offeredGame, "GTA 6")
        XCTAssertEqual(store.region, general)
        areas.declineOffered()
        store.setCustomRegion(acArea)
        XCTAssertTrue(areas.targetHasOtherProfile)
        areas.save()
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, gtaArea)

        // Listede olmayan oyun adıyla yeni profil: oynanan oyun da o olur.
        XCTAssertEqual(areas.saveAs("Assassin's Creed Valhalla"), .done)
        areas.follow(game: sense.current, source: sense.source)
        XCTAssertEqual(sense.current?.name, "Assassin's Creed Valhalla")
        XCTAssertEqual(store.activeAreaProfile, "assassins creed valhalla|stream")
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, gtaArea)
        XCTAssertEqual(store.areaProfile("assassins creed valhalla|stream")?.areas.region, acArea)
        // Var olan oyunun adıyla yeni profil açılmaz.
        XCTAssertEqual(areas.saveAs("Grand Theft Auto VI"), .exists)
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, gtaArea)

        // AC'de alan değişikliği yalnız AC profiline yazılır.
        store.setCustomRegion(general)
        areas.save()
        XCTAssertEqual(store.areaProfile("assassins creed valhalla|stream")?.areas.region, general)
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, gtaArea)

        // Listeden GTA 6 seçilir: onun alanları gelir, oyun GTA 6 olur.
        areas.use(gta)
        areas.follow(game: sense.current, source: sense.source)
        XCTAssertEqual(store.region, gtaArea)
        XCTAssertEqual(sense.current?.name, "GTA 6")
        XCTAssertEqual(sense.source, .user)
        // Oturum bitince profilsizken kullanılan (AC'den önceki) alanlar geri gelir; profiller kendi alanlarında kalır.
        areas.stop()
        sense.endSession()
        XCTAssertEqual(store.region, acArea)
        XCTAssertNil(store.activeAreaProfile)
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, gtaArea)
        XCTAssertEqual(store.areaProfile("assassins creed valhalla|stream")?.areas.region, general)
    }

    @MainActor
    func testProfilesCanBeRenamedDuplicatedAndDeleted() {
        var store = UserSettings()
        store.setCustomRegion(general)
        var chosen: [String] = []
        let areas = GameAreas(read: { store }, write: { store = $0 })
        areas.onChoose = { chosen.append($0) }

        // Çeviri dururken de profil açılır.
        XCTAssertEqual(areas.saveAs("GTA 6"), .done)
        XCTAssertEqual(areas.saveAs("  "), .empty)
        XCTAssertEqual(chosen, ["GTA 6"])
        store.setCustomRegion(gtaArea)
        areas.save()
        XCTAssertEqual(store.areaProfile(gta)?.areas.region, general, "çeviri dururken Kaydet bir şey yapmaz")

        XCTAssertEqual(areas.duplicate(gta, as: "Mafia: The Old Country"), .done)
        XCTAssertEqual(areas.duplicate(gta, as: "Grand Theft Auto VI"), .exists)
        XCTAssertEqual(store.areaProfile("mafia the old country|stream")?.areas.region, general)
        XCTAssertEqual(store.activeAreaProfile, gta)

        // Başka profilin adına çevrilemez; etkin profilin adı değişince etkin kalır, oyun da yeni ad olur.
        XCTAssertEqual(areas.rename(gta, to: "Mafia The Old Country"), .exists)
        XCTAssertEqual(areas.rename(gta, to: "Grand Theft Auto VI"), .done)
        XCTAssertEqual(store.activeAreaProfile, gta)
        XCTAssertEqual(store.areaProfile(gta)?.game, "Grand Theft Auto VI")
        XCTAssertEqual(areas.rename(gta, to: "Red Dead Redemption 2"), .done)
        XCTAssertEqual(store.activeAreaProfile, "rdr 2|stream")
        XCTAssertEqual(chosen.last, "Red Dead Redemption 2")
        XCTAssertEqual(areas.rename("yok|stream", to: "X"), .missing)

        XCTAssertEqual(store.gameProfiles.map(\.game), ["Mafia: The Old Country", "Red Dead Redemption 2"])
        areas.delete("rdr 2|stream")
        XCTAssertNil(store.activeAreaProfile)
        XCTAssertEqual(store.region, general)
        XCTAssertEqual(store.areaProfiles.map(\.key), ["mafia the old country|stream"])
    }

    /// Eski sürümün kaydı (en çok 20 profil, biri etkin kalmış): ilk açılışta hiçbiri kaybolmaz, her oyun kendi profilinde
    /// kalır, açık kalan profil kapanıp genel alanlar geri gelir.
    @MainActor
    func testOldSettingsKeepEveryGamesProfile() throws {
        var old = UserSettings()
        old.setCustomRegion(general)
        old.areaProfiles = (0..<20).map { AreaProfile(key: "game \($0)|stream", game: "Game \($0)",
                                                      areas: AreaSet(region: farCryArea, areaPreset: .custom, extraAreas: [])) }
        old.areaProfiles.append(AreaProfile(key: gta, game: "GTA 6", areas: AreaSet(region: gtaArea, areaPreset: .custom, extraAreas: [])))
        old.areaProfiles.removeFirst()
        old.useAreaProfile(old.areaProfile(gta)!)
        let data = try JSONEncoder().encode(old)
        let loaded = GameAreas.restored(try JSONDecoder().decode(UserSettings.self, from: data))
        XCTAssertEqual(loaded.areaProfiles.count, 20)
        XCTAssertEqual(loaded.areaProfile(gta)?.areas.region, gtaArea)
        XCTAssertEqual(loaded.areaProfile("game 5|stream")?.areas.region, farCryArea)
        XCTAssertEqual(loaded.region, general)
        XCTAssertNil(loaded.activeAreaProfile)
    }

    func testPopularGamesAreSuggested() {
        let found = GameCatalog.suggestions(query: "assassin", packs: [], last: nil, limit: 10)
        XCTAssertTrue(found.contains("Assassin's Creed Valhalla"))
        XCTAssertTrue(found.contains("Assassin's Creed Shadows"))
        XCTAssertTrue(GameCatalog.suggestions(query: "resident evil 4", packs: [], last: nil).contains("Resident Evil 4"))
        XCTAssertTrue(GameCatalog.suggestions(query: "wolverine", packs: [], last: nil).contains("Marvel's Wolverine"))
        XCTAssertEqual(Set(GameCatalog.popular.map(GameName.key)).count, GameCatalog.popular.count)
    }
}
