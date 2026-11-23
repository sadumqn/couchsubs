// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import com.couchsubs.mobile.core.GameAreas
import com.couchsubs.mobile.core.GameCatalog
import com.couchsubs.mobile.core.GamePackLibrary
import com.couchsubs.mobile.core.GameSense
import com.couchsubs.mobile.core.RunningGame
import com.couchsubs.mobile.core.restoreAreas
import com.couchsubs.mobile.settings.AppSettings

/**
 * Oynanan oyun: servisin okuma hattı ile ekranlar arasında (Mac ve iPhone'daki GameChoice ile aynı davranış). Servis
 * satırları ve PS5'in bildirdiğini verir, ekran kartı ([LiveStatus.askingGame]) ve "Oynanan oyun: X · Değiştir" satırını
 * ([LiveStatus.game]) gösterir. Seçim oturum boyunca geçerlidir ve PS5'in adıyla saklanır; aynı PS5'te sonraki oturumda
 * kartın ilk önerisi olur.
 */
object PlayedGame {
    val sense = GameSense()
    @Volatile private var console: String? = null
    @Volatile private var settings: AppSettings? = null
    @Volatile private var startedAt = 0L
    @Volatile private var last: RunningGame? = null
    /** Oyun değişti (servis havuza ve paket sunucusuna bağlar); oturum yokken null. */
    @Volatile var onChange: ((RunningGame?) -> Unit)? = null
    /**
     * Oyuna göre alanlar: oyun değişince kayıtlı alanlar uygulanır ya da önerilir (bkz. [GameAreas]). Ekranlar
     * [LiveStatus.areaProfileGame], [LiveStatus.offeredAreaProfileGame] ve [LiveStatus.areaProfileTarget]'ı okur.
     */
    val areas: GameAreas = GameAreas(changed = { publishAreas() }).also {
        // Ayarlar'da oyun profili seçilince ya da yeni profil açılınca oynanan oyun o olur.
        it.onChoose = { name -> choose(name) }
    }

    private fun publishAreas() {
        val state = areas
        LiveState.update {
            val game = state.activeGame
            it.copy(areaProfileGame = game, offeredAreaProfileGame = state.offeredGame, areaProfileTarget = state.target,
                areaProfileTargetSaved = state.targetHasOtherProfile,
                // Çeviri dururken Ayarlar'da profil seçilince de alanlar değişir.
                areasVersion = if (game != it.areaProfileGame || !state.running) it.areasVersion + 1 else it.areasVersion,
                profilesVersion = it.profilesVersion + 1)
        }
    }

    /** Kurulu paketlerin oyun adları (öneriler için). */
    @Volatile var packTitles: () -> List<String> = { emptyList() }
    /** Hazır paketler: kullanıcı elle oyun seçince satırlar yalnız o oyunun paketinde aranır ([GameSense.packLimit], #218). */
    @Volatile var packs: GamePackLibrary? = null
        set(value) {
            field = value
            value?.limitToGame(sense.packLimit)
        }

    /** Çeviri başladı. */
    fun start(console: String, settings: AppSettings, startedAt: Long) {
        sense.startSession()
        this.console = console
        this.settings = settings
        this.startedAt = startedAt
        last = null
        LiveState.update { it.copy(askingGame = false) }
        // Uygulama oturum sürerken kapandıysa oyunun profili açık kalmış olabilir: önce genel alanlar geri gelir.
        settings.restoreAreas()
        areas.start(settings)
        publish()
    }

    /** Çeviri durdu: kart kapanır, oyun havuza artık gitmez. */
    fun stop() {
        sense.endSession()
        onChange = null
        areas.stop()
        LiveState.update { it.copy(askingGame = false) }
    }

    /** Servis periyodik olarak sorar (15 saniyede bir): süre doldu ve oyun bilinmiyorsa kart açılır. */
    fun checkAsk(now: Long) {
        val settings = settings ?: return
        if (!sense.shouldAsk(now - startedAt, settings.askGame && settings.sharePool)) return
        sense.markAsked()
        LiveState.update { it.copy(askingGame = true) }
    }

    /** Ekrana bir satır geldi; [fromPack]: hazır paketten. */
    fun noteLine(fromPack: Boolean, library: GamePackLibrary) {
        val hit = library.takeDistinctiveHit()
        val pack = if (fromPack) hit else null
        if (!sense.noteLine(pack?.id, pack?.title)) return
        LiveState.update { it.copy(askingGame = false) }
        publish()
    }

    /** PS5'in keşif yanıtındaki oyun (yoksa null). */
    fun consoleReported(game: RunningGame?) {
        sense.setConsole(game)
        publish()
    }

    /** Kullanıcı bir oyun seçti ya da adını yazdı. */
    fun choose(name: String) {
        val clean = RunningGame.normalizedName(name) ?: return
        sense.choose(clean)
        val console = console
        val settings = settings
        if (console != null && settings != null) settings.rememberGame(console, clean)
        LiveState.update { it.copy(askingGame = false) }
        publish()
    }

    /** "Değiştir": kart elle açılır. */
    fun ask() {
        sense.markAsked()
        LiveState.update { it.copy(askingGame = true) }
    }

    /** "Sorma": bu oturumda bir daha sorulmaz. */
    fun dismiss() {
        sense.markAsked()
        LiveState.update { it.copy(askingGame = false) }
    }

    /** Bu PS5'te son seçilen oyun. */
    val lastPlayed: String? get() = console?.let { settings?.lastGame(it) }

    fun suggestions(query: String): List<String> = GameCatalog.suggestions(query, packTitles(), lastPlayed)

    private fun publish() {
        packs?.limitToGame(sense.packLimit)
        val current = sense.current
        LiveState.update { it.copy(game = current?.name) }
        areas.follow(current, sense.source)
        if (current == last) return
        last = current
        onChange?.invoke(current)
    }
}
