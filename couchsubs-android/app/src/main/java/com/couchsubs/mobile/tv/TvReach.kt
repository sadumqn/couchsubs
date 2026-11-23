// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import java.io.IOException
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Kayıtlı TV adresi yanıt veriyor mu, vermiyorsa TV ağda yeni bir adreste mi (Mac/iPhone `TVReach`, Windows `TvReach`
 * ile aynı kural).
 *
 * beta.89 (Mac): modem LG TV'ye yeni adres vermişti (192.168.1.238 → .156). Uygulama eski adrese gidip "geliştirici modu
 * kapalı" ve "Key Server kapalı" diyordu; TV'de ikisi de açıktı. Kurulumdan, "TV uygulamasını güncelle"den ve eşli TV
 * kartından önce adres yoklanır: hiçbir kapı yanıt vermiyorsa (zaman aşımı, adreste cihaz yok; "reddedildi" yanıt
 * sayılır) TV ağda yeniden aranır, aynı TV bulunursa adres güncellenir; bulunmazsa "TV bu adreste yanıt vermiyor".
 */
object TvReach {
    /** TV'nin açıkken her zaman dinlediği (ya da reddettiği) kapılar. Geliştirici modu kapalıyken de en az biri yanıt verir. */
    fun ports(brand: TvBrand): List<Int> = when (brand) {
        TvBrand.LG -> listOf(3000, 3001, 9922, 9991, 1990)
        TvBrand.SAMSUNG -> listOf(8001, 8002, 26101, 9197)
        TvBrand.ANDROID_TV -> listOf(5555, 6466, 6467, 8008, 8009)
    }

    /** Günlük satırı (Türkçe; ekran metni strings.xml'den). */
    const val NOT_RESPONDING_LINE = "TV bu adreste yanıt vermiyor (açık ve aynı ağda mı?)"

    fun movedLine(old: String, new: String) = "TV'nin adresi değişmiş: $old → $new"

    /** Kayıtlı TV'nin yeri. */
    sealed interface Location {
        /** Kayıtlı adreste bir şey yanıt veriyor (kapı açık ya da bağlantıyı reddediyor). */
        data object Here : Location
        /** Kayıtlı adres sessiz; aynı TV ağda yeni adreste bulundu. */
        data class Moved(val tv: FoundTv) : Location
        /** Kayıtlı adres sessiz ve TV ağda bulunamadı. */
        data object Silent : Location
    }

    /** Kayıtlı adres yanıt vermiyorsa TV'yi ağda arar (bloklar). Adresi olmayan kayıtta bir şey yapılmaz ([Location.Here]). */
    fun locate(saved: FoundTv, responds: (String) -> Boolean, search: () -> List<FoundTv>): Location {
        if (saved.host.isBlank() || responds(saved.host)) return Location.Here
        return relocated(saved, search())?.let { Location.Moved(it) } ?: Location.Silent
    }

    /**
     * Bulunanlar içinde kayıtlı TV'nin yeni adresi: aynı marka ve aynı ad tekse o, değilse markada tek TV varsa o. Kayıtlı
     * adres listedeyse ya da emin olunamazsa (birden çok tanınmayan TV) null; başka odadaki TV'ye geçilmez (Mac
     * `TVLocator.moved`).
     */
    fun relocated(saved: FoundTv, found: List<FoundTv>): FoundTv? {
        val same = found.filter { it.brand == saved.brand }
        if (same.any { it.host == saved.host }) return null
        val sameName = same.filter { it.name == saved.name }
        if (sameName.size == 1) return sameName[0]
        return same.singleOrNull()
    }

    /**
     * Adreste TV yanıt veriyor mu: kapılardan biri bağlantıyı kabul eder ya da hemen reddederse evet. Hepsi zaman aşımına
     * uğrarsa ya da adrese yol yoksa hayır. Bloklar (en çok ~[timeoutMs]).
     */
    fun responds(host: String, brand: TvBrand, timeoutMs: Int = 1_500, probe: (String, Int, Int) -> Boolean = ::answers): Boolean {
        if (host.isBlank()) return false
        val ports = ports(brand)
        val pool = Executors.newFixedThreadPool(ports.size)
        try {
            val completion = ExecutorCompletionService<Boolean>(pool)
            ports.forEach { port -> completion.submit(Callable { probe(host, port, timeoutMs) }) }
            repeat(ports.size) {
                val done = completion.poll(timeoutMs + 1_000L, TimeUnit.MILLISECONDS) ?: return false
                if (runCatching { done.get() }.getOrDefault(false)) return true
            }
            return false
        } finally {
            pool.shutdownNow()
        }
    }

    /** Kapı bağlantıyı kabul etti ya da reddetti mi (ikisi de adreste bir cihaz olduğunu gösterir). */
    fun answers(host: String, port: Int, timeoutMs: Int): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs) }
        true
    } catch (error: IOException) {
        isRefusal(error)
    }

    /** "Bağlantı reddedildi" ya da sıfırlandı: adreste cihaz var. Zaman aşımı, yol yok, cihaz yok: sessiz. */
    fun isRefusal(error: IOException): Boolean {
        val message = error.message.orEmpty().lowercase()
        if (error is ConnectException && ("refused" in message || "econnrefused" in message)) return true
        return "connection reset" in message || "econnreset" in message
    }
}
