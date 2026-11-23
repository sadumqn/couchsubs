// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import android.content.Context
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.tv.lg.LgKeys
import com.couchsubs.mobile.tv.samsung.InstallLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Eşli TV'nin adresi değişince TV'yi yeniden bulma ve eşli TV kartının eylemleri (iPhone `PhoneModel.checkTVReachable`,
 * Mac/Windows `checkTVReachable` / `CheckTvReachableAsync` ile aynı davranış): kart görünürken TV uygulaması bağlı
 * değilse ~10 sn'de bir kayıtlı adres yoklanır ([TvReach.responds]); sessizse kart "Yanıt vermiyor — yeniden aranıyor…"
 * der, ağ en çok 30 sn'de bir aranır ve aynı TV bulunursa kayıt yeni adrese taşınır (kartta yeni adres görünür).
 */
object TvRelocation {
    /** Ağ araması en çok bu aralıkla yapılır (kullanıcının "TV'yi Yeniden Ara"sı hariç). */
    const val SEARCH_INTERVAL_MS = 30_000L

    /** Kart yoklaması aralığı. */
    const val CHECK_INTERVAL_MS = 10_000L

    private val silent = MutableStateFlow(false)

    /** Kayıtlı TV adresi şu an yanıt vermiyor (kart durumu). */
    val notResponding: StateFlow<Boolean> = silent

    @Volatile private var lastSearch = 0L

    /** Testlerde ağa çıkılmaz. */
    @Volatile var responds: (String, TvBrand) -> Boolean = { host, brand -> TvReach.responds(host, brand) }
    @Volatile var search: () -> List<FoundTv> = { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) }
    @Volatile var identify: (String) -> FoundTv? = { host -> runCatching { PairedTv.identify(host) }.getOrNull() }
    @Volatile var clock: () -> Long = System::currentTimeMillis

    fun log(context: Context) = InstallLog(File(context.filesDir, "tvinstall.log"))

    fun lgKeys(context: Context) = LgKeys(File(context.noBackupFilesDir, "lg"))

    /** Kayıtlı TV (ad: kayıtlı ad, yoksa markanın varsayılanı). */
    fun savedTv(): FoundTv? {
        val tv = Services.settings.installedTv ?: return null
        return FoundTv(Services.settings.tvName ?: defaultName(tv.brand), tv.host, tv.brand)
    }

    private fun defaultName(brand: TvBrand) = when (brand) {
        TvBrand.LG -> "LG TV"
        TvBrand.SAMSUNG -> "Samsung TV"
        TvBrand.ANDROID_TV -> "Android TV"
    }

    /**
     * Kayıtlı TV'nin yeri (bloklar). Adres sessizse ağ aranır ([force] değilse en çok 30 sn'de bir); aynı TV bulunursa
     * kayıt taşınır ve günlüğe "TV'nin adresi değişmiş: eski → yeni" yazılır. Kayıtlı TV yoksa null.
     */
    fun locateBlocking(log: InstallLog, lgKeys: LgKeys? = null, force: Boolean = false): TvReach.Location? {
        val saved = savedTv() ?: return null
        val now = clock()
        val location = TvReach.locate(saved, { responds(it, saved.brand) }) {
            if (!force && now - lastSearch < SEARCH_INTERVAL_MS) emptyList<FoundTv>() else { lastSearch = now; search() }
        }
        when (location) {
            TvReach.Location.Here -> silent.value = false
            is TvReach.Location.Moved -> {
                moveTo(location.tv, log, lgKeys)
                silent.value = false
            }
            TvReach.Location.Silent -> {
                if (!silent.value) log.write("${TvReach.NOT_RESPONDING_LINE} (${saved.host})")
                silent.value = true
            }
        }
        return location
    }

    /** Kart yoklaması (~10 sn'de bir). */
    suspend fun checkTvReachable(context: Context): TvReach.Location? =
        withContext(Dispatchers.IO) { locateBlocking(log(context), lgKeys(context)) }

    /** "TV'yi Yeniden Ara": ağ hemen aranır. */
    suspend fun searchTvAgain(context: Context): TvReach.Location? =
        withContext(Dispatchers.IO) { locateBlocking(log(context), lgKeys(context), force = true) }

    /**
     * "IP Adresi Gir": yazılan adresteki TV tanınırsa kayıtlı TV o adrese taşınır (marka değişirse yeni TV gibi seçilir).
     * Tanınmazsa false.
     */
    suspend fun useTvAddress(context: Context, host: String): Boolean = withContext(Dispatchers.IO) {
        val address = host.trim()
        if (address.isEmpty()) return@withContext false
        val found = identify(address) ?: return@withContext false
        val saved = Services.settings.installedTv
        if (saved != null && saved.brand == found.brand) {
            if (saved.host != found.host) moveTo(FoundTv(Services.settings.tvName ?: found.name, found.host, found.brand), log(context), lgKeys(context))
        } else {
            Services.settings.installedTv = TvChoice.select(saved, found)
            Services.settings.tvName = found.name
        }
        silent.value = false
        true
    }

    /**
     * Kayıtlı TV'yi yeni adrese taşır: TV kaydı (sürüm ve ad korunur), LG anahtarı (adrese göre saklanır) ve Samsung'da
     * uygulamanın kurulu bilindiği adres.
     */
    fun moveTo(found: FoundTv, log: InstallLog, lgKeys: LgKeys? = null) {
        val settings = Services.settings
        val saved = settings.installedTv ?: return
        if (saved.host == found.host) return
        log.write(TvReach.movedLine(saved.host, found.host))
        settings.installedTv = saved.copy(host = found.host, port = if (saved.brand == TvBrand.ANDROID_TV) 0 else saved.port)
        if (saved.brand == TvBrand.SAMSUNG && settings.samsungAppSeenHost == saved.host) settings.samsungAppSeenHost = found.host
        if (saved.brand == TvBrand.LG && lgKeys != null) lgKeys.load(saved.host)?.let { lgKeys.save(found.host, it) }
    }

    /** "Eşleşmeyi Kaldır": kayıtlı TV, adı, LG anahtarı ve Samsung kaydı silinir; altyazı hedefi yerinde kalır. */
    fun removeTvPairing(context: Context) {
        val settings = Services.settings
        val saved = settings.installedTv
        if (saved != null) {
            log(context).write("Eşli TV kaldırıldı: ${saved.brand} ${saved.host}")
            if (saved.brand == TvBrand.LG) lgKeys(context).remove(saved.host)
            if (settings.samsungAppSeenHost == saved.host) settings.samsungAppSeenHost = null
        }
        settings.installedTv = null
        settings.tvName = null
        silent.value = false
        TvAppUpdate.forget()
    }

    /** Kurulum hedefinin yeniden bulunma sonucu. */
    sealed interface Retarget {
        /** Adreste TV yanıt veriyor: asıl hata (geliştirici modu, Key Server) gösterilir. */
        data object Responds : Retarget
        /** Aynı TV yeni adreste; kayıt (kayıtlı TV ise) ve LG anahtarı taşındı. */
        data class Moved(val host: String) : Retarget
        /** Adres sessiz, TV ağda bulunamadı: "TV bu adreste yanıt vermiyor". */
        data object Silent : Retarget
    }

    /**
     * Kurulum ekranları (LG, Samsung, Android TV) bağlanamayınca: hedef adres hiç yanıt vermiyorsa ağ hemen aranır,
     * aynı TV bulunursa günlüğe "TV'nin adresi değişmiş" yazılır ve kayıt taşınır. Bloklar.
     */
    fun retarget(target: String, brand: TvBrand, log: InstallLog, lgKeys: LgKeys? = null): Retarget {
        if (responds(target, brand)) return Retarget.Responds
        val settings = Services.settings
        val saved = settings.installedTv?.takeIf { it.brand == brand && it.host == target }
        val name = saved?.let { settings.tvName } ?: defaultName(brand)
        lastSearch = clock()
        val found = TvReach.relocated(FoundTv(name, target, brand), search())
        if (found == null) {
            log.write("${TvReach.NOT_RESPONDING_LINE} ($target)")
            return Retarget.Silent
        }
        if (saved != null) moveTo(found, log, lgKeys)
        else {
            log.write(TvReach.movedLine(target, found.host))
            if (brand == TvBrand.LG && lgKeys != null) lgKeys.load(target)?.let { lgKeys.save(found.host, it) }
        }
        silent.value = false
        return Retarget.Moved(found.host)
    }

    /** Testler için. */
    fun reset() {
        silent.value = false
        lastSearch = 0L
        responds = { host, brand -> TvReach.responds(host, brand) }
        search = { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) }
        identify = { host -> runCatching { PairedTv.identify(host) }.getOrNull() }
        clock = System::currentTimeMillis
    }
}
