// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.promo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/**
 * promo.json'ı arka planda çeker ve gösterilecek popup'ı görseliyle hazırlar. Ağ hatası sessizdir. Görsel yalnız bellekte
 * tutulur (diske önbellek yok); gösterilip kapatılınca bırakılır. İstekte çerez, kimlik ya da cihaz bilgisi gitmez.
 */
object PromoController {
    private const val TAG = "CouchSubsPromo"
    const val URL_CONFIG = "https://couchsubs.enmeraapps.com/promo.json"

    /** Gösterilmeye hazır popup ve görseli. */
    data class Ready(val popup: PromoPopup, val image: Bitmap)

    private val state = MutableStateFlow<Ready?>(null)
    val ready: StateFlow<Ready?> = state
    private val busy = AtomicBoolean(false)
    @Volatile private var popup: PromoPopup? = null
    @Volatile private var fetchedAtMs = 0L
    /** Uygulamanın son ön plana geldiği an: popup bundan 10 sn sonra açılır. */
    @Volatile var foregroundAtMs = 0L
        private set

    private fun prefs(context: Context) = context.getSharedPreferences("promo", Context.MODE_PRIVATE)

    fun record(context: Context): PromoRecord = prefs(context).let {
        PromoRecord(it.getString("shownId", null), it.getLong("shownAt", 0L))
    }

    /**
     * Uygulama ön plana geldi: promo.json soğuk açılışta (süreçte ilk kez) ve sonra en çok günde bir çekilir; popup
     * zamanı geldiyse görseli indirilir. [setupDone] false ise (karşılama, kurulum ya da ilk tur sürüyor) hiçbir şey
     * yapılmaz: yeni kullanıcı ilk açılışında tanıtım görmez.
     */
    fun refresh(context: Context, scope: CoroutineScope, setupDone: Boolean) {
        val app = context.applicationContext
        foregroundAtMs = System.currentTimeMillis()
        if (!setupDone) {
            state.value = null
            return
        }
        if (!busy.compareAndSet(false, true)) return
        scope.launch(Dispatchers.IO) {
            try {
                val now = System.currentTimeMillis()
                if (fetchedAtMs == 0L || now - fetchedAtMs >= PromoPolicy.REFETCH_MS) {
                    // promo.json indirilemezse ya da bozuksa uygulamayla gelen reklam (Mac, Windows ve iPhone ile aynı).
                    popup = try {
                        PromoPolicy.parse(String(download(URL_CONFIG, PromoPolicy.MAX_CONFIG_BYTES), Charsets.UTF_8))
                    } catch (error: IOException) {
                        Log.i(TAG, "promo alınamadı, uygulamadaki reklam: ${error.message}")
                        null
                    } ?: bundled(app)
                    fetchedAtMs = now
                }
                val current = popup
                if (!PromoPolicy.due(current, record(app), now) || current == null) {
                    state.value = null
                    return@launch
                }
                // Görsel zaten hazırsa yeniden inmez; yalnız yeni girişin 10 sn'si beklenir.
                val image = state.value?.takeIf { it.popup == current }?.image
                    ?: decode(if (current.bundled) asset(app, "reklam/" + current.image) else download(current.image, PromoPolicy.MAX_IMAGE_BYTES))
                    ?: return@launch
                state.value = null
                // Girişten 10 sn dolmadan yayımlanmaz (beklerken yeniden ön plana gelindiyse yeni girişten sayılır); ekran
                // o an boştaysa popup hemen açılır.
                while (true) {
                    val wait = foregroundAtMs + PromoPolicy.SHOW_DELAY_MS - System.currentTimeMillis()
                    if (wait <= 0) break
                    kotlinx.coroutines.delay(wait)
                }
                state.value = Ready(current, image)
            } catch (error: IOException) {
                Log.i(TAG, "promo alınamadı: ${error.message}")
            } catch (error: RuntimeException) {
                Log.i(TAG, "promo okunamadı: ${error.message}")
            } finally {
                busy.set(false)
            }
        }
    }

    /** Popup kapatıldı (X, görsele dokunma ya da geri): gösterim kaydedilir, görsel bırakılır. */
    fun dismissed(context: Context, popup: PromoPopup) {
        prefs(context).edit().putString("shownId", popup.id).putLong("shownAt", System.currentTimeMillis()).apply()
        state.value = null
    }

    /** Uygulamayla gelen reklam (assets/reklamlar.json); yoksa ya da bozuksa null. */
    private fun bundled(context: Context): PromoPopup? = try {
        PromoPolicy.parseBundled(String(asset(context, "reklamlar.json"), Charsets.UTF_8))
    } catch (error: IOException) {
        null
    }

    /** Paketteki dosya (görsel yüklenemezse reklam açılmaz). */
    private fun asset(context: Context, name: String): ByteArray =
        context.assets.open(name).use { read(it, PromoPolicy.MAX_IMAGE_BYTES) }

    private fun download(url: String, limit: Int): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = PromoPolicy.TIMEOUT_MS
            connection.readTimeout = PromoPolicy.TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.useCaches = false
            connection.setRequestProperty("User-Agent", "CouchSubs-Android")
            if (connection.responseCode != 200) throw IOException("HTTP ${connection.responseCode}")
            if (connection.contentLengthLong > limit) throw IOException("çok büyük")
            return connection.inputStream.use { read(it, limit) }
        } finally {
            connection.disconnect()
        }
    }

    private fun read(input: InputStream, limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            out.write(buffer, 0, count)
            if (out.size() > limit) throw IOException("çok büyük")
        }
        return out.toByteArray()
    }

    /** Görsel en çok ~1440 px'e küçültülerek açılır (telefon ekranı için yeter, bellek az tutulur). */
    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1440) sample *= 2
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }
}
