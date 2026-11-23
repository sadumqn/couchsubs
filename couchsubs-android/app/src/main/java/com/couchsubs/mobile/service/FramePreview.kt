// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import android.graphics.Bitmap
import com.couchsubs.mobile.remoteplay.VideoFrame
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Son PS5 karesinin küçük gri kopyası: Ayarlar › Altyazı alanındaki canlı önizleme (iPhone'daki PhoneFramePreview).
 * Yalnız önizleme açıkken ([watch]) ve saniyede dört kez kopyalanır (çerçeve akan görüntüde yerleştirilir); çeviri
 * hattını yavaşlatmaz.
 */
object FramePreview {
    private const val WIDTH = 320
    private const val INTERVAL_MS = 250L

    private val state = MutableStateFlow<Bitmap?>(null)
    val frame: StateFlow<Bitmap?> = state
    @Volatile private var watchers = 0
    @Volatile private var last = 0L

    /** Önizleme ekranı açıldı ([on]) ya da kapandı. */
    @Synchronized
    fun watch(on: Boolean) {
        watchers = (watchers + if (on) 1 else -1).coerceAtLeast(0)
    }

    /** Çeviri hizmeti her karede çağırır; önizleme izlenmiyorsa hemen döner. */
    fun offer(frame: VideoFrame, now: Long) {
        if (watchers == 0 || now - last < INTERVAL_MS) return
        last = now
        try {
            if (frame.width <= 0 || frame.height <= 0) return
            val height = (WIDTH.toLong() * frame.height / frame.width).toInt().coerceAtLeast(1)
            val buffer = frame.buffer
            val pixels = IntArray(WIDTH * height)
            for (y in 0 until height) {
                val sy = y * frame.height / height
                for (x in 0 until WIDTH) {
                    val sx = x * frame.width / WIDTH
                    val v = buffer.get(sy * frame.rowStride + sx).toInt() and 0xff
                    pixels[y * WIDTH + x] = (0xff shl 24) or (v shl 16) or (v shl 8) or v
                }
            }
            state.value = Bitmap.createBitmap(pixels, WIDTH, height, Bitmap.Config.ARGB_8888)
        } catch (error: RuntimeException) {
            // Kare okunamadı (sınır dışı); sonraki karede yeniden denenir.
        }
    }
}
