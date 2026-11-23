// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Oyuna göre alan profilinin ne zaman uygulandığı ve [GameAreas] akışı (Windows ve Mac/iPhone ile aynı örnekler). */
class AreaProfilesTest {
    private val farCry = "far cry 3|stream"
    private val general = CropRegion(0.62, 0.97, 0.14, 0.86)
    private val farCryArea = CropRegion(0.70, 0.95, 0.20, 0.80)

    private class MemoryStore(override var areas: AreaSet) : AreaStore {
        override var areaProfiles: List<AreaProfile> = emptyList()
        override var activeAreaProfile: String? = null
        override var generalAreas: AreaSet? = null
    }

    private fun run(active: String?, game: String?, source: GameSense.Source?, area: AreaSource = AreaSource.STREAM,
                    saved: List<String> = listOf(farCry), declined: List<String> = emptyList()) =
        AreaProfiles.decide(active, game, source, area, exists = { it in saved }, declined = { it in declined })

    private fun store() = MemoryStore(AreaSet(general, AreaPreset.CUSTOM, emptyList()))
    private fun game(name: String) = RunningGame.named(name)

    @Test
    fun keyUsesTheServersGameKeyAndTheSource() {
        assertEquals("gta 6|stream", AreaProfiles.key("Grand Theft Auto VI", AreaSource.STREAM))
        assertEquals("gta 6|window", AreaProfiles.key("GTA 6", AreaSource.WINDOW))
        assertNull(AreaProfiles.key("", AreaSource.STREAM))
        assertNull(AreaProfiles.key(null, AreaSource.STREAM))
    }

    @Test
    fun aCertainGameAppliesAndAPackGuessIsOffered() {
        assertEquals(AreaProfiles.Step.Apply(farCry), run(null, "Far Cry 3", GameSense.Source.CONSOLE))
        assertEquals(AreaProfiles.Step.Apply(farCry), run(null, "Far Cry 3", GameSense.Source.USER))
        assertEquals(AreaProfiles.Step.Offer(farCry), run(null, "Far Cry 3", GameSense.Source.PACK))
    }

    @Test
    fun theSameProfileOrAnUnknownGameChangesNothing() {
        assertEquals(AreaProfiles.Step.None, run(farCry, "Far Cry III", GameSense.Source.CONSOLE))
        assertEquals(AreaProfiles.Step.None, run(farCry, null, null))
        assertEquals(AreaProfiles.Step.None, run(null, null, null))
    }

    @Test
    fun anotherGameSwitchesOrGoesBackToTheGeneralAreas() {
        assertEquals(AreaProfiles.Step.UseGeneral, run(farCry, "Hades", GameSense.Source.CONSOLE))
        assertEquals(AreaProfiles.Step.None, run(null, "Hades", GameSense.Source.CONSOLE))
        assertEquals(AreaProfiles.Step.Apply("hades|stream"), run(farCry, "Hades", GameSense.Source.USER, saved = listOf(farCry, "hades|stream")))
    }

    @Test
    fun aDeclinedProfileIsNotAppliedOrOfferedAgain() {
        assertEquals(AreaProfiles.Step.None, run(null, "Far Cry 3", GameSense.Source.CONSOLE, declined = listOf(farCry)))
        assertEquals(AreaProfiles.Step.None, run(null, "Far Cry 3", GameSense.Source.PACK, declined = listOf(farCry)))
        assertEquals(AreaProfiles.Step.UseGeneral, run("hades|stream", "Far Cry 3", GameSense.Source.CONSOLE, declined = listOf(farCry)))
    }

    @Test
    fun theWindowSourceHasItsOwnProfile() {
        assertEquals(AreaProfiles.Step.None, run(null, "Far Cry 3", GameSense.Source.CONSOLE, AreaSource.WINDOW))
        assertEquals(AreaProfiles.Step.Apply("far cry 3|window"),
            run(null, "Far Cry 3", GameSense.Source.CONSOLE, AreaSource.WINDOW, saved = listOf(farCry, "far cry 3|window")))
    }

    @Test
    fun savingMovesTheProfileToTheEndAndKeepsTwenty() {
        assertEquals(listOf("a", "c", "b"), AreaProfiles.saved(listOf("a", "b", "c"), "b") { it })
        val full = (0 until AreaProfiles.MAX_COUNT).map { "g$it" }
        val next = AreaProfiles.saved(full, "new") { it }
        assertEquals(AreaProfiles.MAX_COUNT, next.size)
        assertEquals("g1", next.first())
        assertEquals("new", next.last())
    }

    @Test
    fun savedAreasComeBackWithTheGameAndTheSessionEndsWithTheGeneralAreas() {
        val store = store()
        val areas = GameAreas()
        assertNull(areas.target)
        areas.save()
        assertTrue(store.areaProfiles.isEmpty())

        areas.start(store)
        areas.follow(game("Far Cry 3"), GameSense.Source.USER)
        assertEquals("Far Cry 3", areas.target)
        store.areas = AreaSet(farCryArea, AreaPreset.CUSTOM, listOf(ExtraArea(name = "Görev", region = ExtraAreaPreset.QUEST.region)))
        areas.save()
        assertEquals(listOf(farCry), store.areaProfiles.map { it.key })
        assertEquals("Far Cry 3", areas.activeGame)
        assertFalse(store.areasDifferFromProfile)
        areas.stop()

        // Profil yokken yapılan değişiklik genel ayardı: genel alanlar yeniden ayarlanır.
        store.areas = AreaSet(general, AreaPreset.CUSTOM, emptyList())
        areas.start(store)
        areas.follow(game("Far Cry III"), GameSense.Source.CONSOLE)
        assertEquals(farCryArea, store.areas.region)
        assertEquals(1, store.areas.extraAreas.size)
        assertEquals(general, store.generalAreas?.region)

        store.areas = store.areas.copy(region = general)
        assertTrue(store.areasDifferFromProfile)
        areas.stop()
        assertEquals(general, store.areas.region)
        assertTrue(store.areas.extraAreas.isEmpty())
        assertNull(store.activeAreaProfile)
        assertNull(store.generalAreas)
        assertEquals(farCryArea, store.areaProfiles.single().areas.region)
    }

    @Test
    fun undoOfferAndAnotherGame() {
        val store = store()
        store.areaProfiles = listOf(AreaProfile(farCry, "Far Cry 3", AreaSet(farCryArea, AreaPreset.CUSTOM, emptyList())))
        var changes = 0
        val areas = GameAreas { changes++ }
        areas.start(store)

        // Paketten tanınan oyunda sorulur; "Hayır" bu oturumda yeniden sormaz.
        areas.follow(game("Far Cry 3"), GameSense.Source.PACK)
        assertEquals("Far Cry 3", areas.offeredGame)
        assertEquals(general, store.areas.region)
        areas.declineOffered()
        areas.follow(game("Far Cry 3"), GameSense.Source.PACK)
        assertNull(areas.offered)
        areas.stop()

        // "Kullan"; elle seçilince aynı profil yeniden uygulanmaz.
        areas.start(store)
        areas.follow(game("Far Cry 3"), GameSense.Source.PACK)
        areas.useOffered()
        assertEquals(farCryArea, store.areas.region)
        areas.follow(game("Far Cry 3"), GameSense.Source.USER)
        assertEquals(farCry, store.activeAreaProfile)

        // "Geri al": genel alanlar, aynı oturumda yeniden uygulanmaz.
        areas.undo()
        assertEquals(general, store.areas.region)
        areas.follow(game("Far Cry 3"), GameSense.Source.CONSOLE)
        assertEquals(general, store.areas.region)
        areas.stop()

        // Başka (profilsiz) oyun genel alanlara döndürür; silme de.
        areas.start(store)
        areas.follow(game("Far Cry 3"), GameSense.Source.CONSOLE)
        assertEquals(farCryArea, store.areas.region)
        areas.follow(game("Hades"), GameSense.Source.CONSOLE)
        assertEquals(general, store.areas.region)
        areas.follow(game("Far Cry 3"), GameSense.Source.CONSOLE)
        areas.delete()
        assertTrue(store.areaProfiles.isEmpty())
        assertEquals(general, store.areas.region)
        assertTrue(changes > 0)
    }

    @Test
    fun aProfileLeftOpenIsClosedAtStartupAndProfilesSurviveJson() {
        val store = store()
        store.saveAreaProfile("Far Cry 3", AreaSource.STREAM)
        store.areas = store.areas.copy(region = farCryArea)
        store.restoreAreas()
        assertEquals(general, store.areas.region)
        assertNull(store.activeAreaProfile)
        assertEquals(1, store.areaProfiles.size)

        val withExtra = store.areaProfiles + AreaProfile("hades|stream", "Hades",
            AreaSet(farCryArea, AreaPreset.CUSTOM, listOf(ExtraArea(id = "a1", name = "Görev", region = ExtraAreaPreset.QUEST.region, enabled = false))))
        assertEquals(withExtra, AreaProfile.listFromJson(AreaProfile.listToJson(withExtra)))
        assertTrue(AreaProfile.listFromJson(null).isEmpty())
        assertTrue(AreaProfile.listFromJson("bozuk").isEmpty())
    }

    // --- Oyun profilleri (her oyun bağımsız) ---

    private val gta = "gta 6|stream"
    private val gtaArea = CropRegion(0.74, 0.93, 0.18, 0.82)
    private val acArea = CropRegion(0.80, 0.98, 0.10, 0.90)

    private fun MemoryStore.region(region: CropRegion) {
        areas = AreaSet(region, AreaPreset.CUSTOM, emptyList())
    }

    @Test
    fun aRememberedChoiceIsOfferedNotApplied() {
        assertEquals(AreaProfiles.Step.Offer(farCry), run(null, "Far Cry 3", GameSense.Source.REMEMBERED))
        assertEquals(AreaProfiles.Step.UseGeneral, run(farCry, "Hades", GameSense.Source.REMEMBERED))
    }

    @Test
    fun aChoiceFromAnEarlierSessionIsRemembered() {
        val sense = GameSense()
        sense.choose("Grand Theft Auto VI")
        sense.startSession()
        // Çeviri dururken (Ayarlar'da) seçilen oyun bu oturum içindir.
        assertEquals(GameSense.Source.USER, sense.source)
        sense.endSession()
        sense.startSession()
        assertEquals(GameSense.Source.USER, sense.source)
        sense.choose("GTA 6")
        sense.endSession()
        sense.startSession()
        assertEquals(GameSense.Source.REMEMBERED, sense.source)
        assertEquals("GTA 6", sense.current?.name)
        sense.choose("Assassin's Creed Valhalla")
        assertEquals(GameSense.Source.USER, sense.source)
    }

    /**
     * Kullanıcının bildirdiği durum: GTA 6 için alanlar kaydedildi, sonraki oturumda Assassin's Creed oynandı, seçim GTA 6'da
     * kaldı. Eskiden GTA 6 profili kendiliğinden uygulanıyor, AC için yapılan değişiklik GTA 6'nın üzerine yazılıyordu.
     */
    @Test
    fun anotherGamesAreasNeverOverwriteAProfile() {
        val store = store()
        val sense = GameSense()
        val areas = GameAreas()
        areas.onChoose = { name ->
            sense.choose(name)
            areas.follow(sense.current, sense.source)
        }

        sense.startSession()
        areas.start(store)
        sense.choose("GTA 6")
        areas.follow(sense.current, sense.source)
        store.region(gtaArea)
        areas.save()
        assertEquals(listOf(gta), store.areaProfiles.map { it.key })
        areas.stop()
        sense.endSession()
        store.region(general)

        sense.startSession()
        areas.start(store)
        areas.follow(sense.current, sense.source)
        assertEquals("GTA 6", areas.offeredGame)
        assertEquals(general, store.areas.region)
        areas.declineOffered()
        store.region(acArea)
        assertTrue(areas.targetHasOtherProfile)
        areas.save()
        assertEquals(gtaArea, store.findAreaProfile(gta)?.areas?.region)

        assertEquals(AreaProfiles.Edit.DONE, areas.saveAs("Assassin's Creed Valhalla", store))
        assertEquals("Assassin's Creed Valhalla", sense.current?.name)
        assertEquals("assassins creed valhalla|stream", store.activeAreaProfile)
        assertEquals(AreaProfiles.Edit.EXISTS, areas.saveAs("Grand Theft Auto VI", store))
        store.region(general)
        areas.save()
        assertEquals(general, store.findAreaProfile("assassins creed valhalla|stream")?.areas?.region)
        assertEquals(gtaArea, store.findAreaProfile(gta)?.areas?.region)

        areas.use(gta, store)
        assertEquals(gtaArea, store.areas.region)
        assertEquals("GTA 6", sense.current?.name)
        areas.stop()
        assertEquals(acArea, store.areas.region)
        assertEquals(2, store.areaProfiles.size)
    }

    @Test
    fun profilesCanBeAddedRenamedDuplicatedAndDeletedWhileStopped() {
        val store = store()
        val chosen = mutableListOf<String>()
        val areas = GameAreas()
        areas.onChoose = { chosen += it }
        assertEquals(AreaProfiles.Edit.DONE, areas.saveAs("GTA 6", store))
        assertEquals(AreaProfiles.Edit.EMPTY, areas.saveAs("  ", store))
        assertEquals(listOf("GTA 6"), chosen)
        assertEquals(AreaProfiles.Edit.DONE, areas.duplicate(gta, "Mafia: The Old Country", store))
        assertEquals(AreaProfiles.Edit.EXISTS, areas.duplicate(gta, "Grand Theft Auto VI", store))
        assertEquals(AreaProfiles.Edit.EXISTS, areas.rename(gta, "Mafia The Old Country", store))
        assertEquals(AreaProfiles.Edit.DONE, areas.rename(gta, "Red Dead Redemption 2", store))
        assertEquals("rdr 2|stream", store.activeAreaProfile)
        assertEquals("Red Dead Redemption 2", chosen.last())
        assertEquals(AreaProfiles.Edit.MISSING, areas.rename("yok|stream", "X", store))
        assertEquals(listOf("Mafia: The Old Country", "Red Dead Redemption 2"), store.gameProfiles(AreaSource.STREAM).map { it.game })
        areas.delete("rdr 2|stream", store)
        assertNull(store.activeAreaProfile)
        assertEquals(general, store.areas.region)
        assertEquals(listOf("mafia the old country|stream"), store.areaProfiles.map { it.key })
    }

    /** Eski sürümün kaydı (20 profil): hiçbiri kaybolmaz, her oyun kendi alanlarında kalır. */
    @Test
    fun oldSettingsKeepEveryGamesProfile() {
        val old = (0 until 20).map { AreaProfile("game $it|stream", "Game $it", AreaSet(gtaArea, AreaPreset.CUSTOM, emptyList())) }
        val loaded = AreaProfile.listFromJson(AreaProfile.listToJson(old))
        assertEquals(20, loaded.size)
        assertEquals(old, loaded)
    }

    @Test
    fun popularGamesAreSuggested() {
        val found = GameCatalog.suggestions("assassin", emptyList(), null, 10)
        assertTrue("Assassin's Creed Valhalla" in found)
        assertTrue("Assassin's Creed Shadows" in found)
        assertTrue("Resident Evil 4" in GameCatalog.suggestions("resident evil 4", emptyList(), null))
        assertTrue("Marvel's Wolverine" in GameCatalog.suggestions("wolverine", emptyList(), null))
        assertEquals(GameCatalog.POPULAR.size, GameCatalog.POPULAR.map { GameName.key(it) }.toSet().size)
    }
}
