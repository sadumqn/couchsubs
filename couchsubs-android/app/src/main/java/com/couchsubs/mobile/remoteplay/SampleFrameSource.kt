// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.couchsubs.mobile.core.DemoScript
import java.nio.ByteBuffer

/**
 * Deneme modunun kare kaynağı (iPhone/Mac `DemoFrameSource` ile aynı): konsol akışı yerine kodda çizilmiş örnek
 * "oyun" karelerini saniyede beş kez okuma hattına verir. Sahne bizimdir (kıyı, deniz feneri); altta İngilizce
 * altyazı, sol üstte görev yazısı. Ağ kullanmaz; uygulamaya görsel dosya gömülmez.
 */
class SampleFrameSource(
    private val onFrame: (VideoFrame) -> Unit,
    private val onState: (SessionState) -> Unit,
) : FrameSource {
    companion object {
        const val WIDTH = 1280
        const val HEIGHT = 720
        private const val FRAME_MS = 200L
        /** Altyazının taban çizgisinin üstten oranı; varsayılan altyazı bölgesinin içindedir. */
        private const val SUBTITLE_BASELINE = 0.86f
    }

    @Volatile private var running = false
    @Volatile override var framesReceived = 0L
        private set
    private var thread: Thread? = null

    override fun start() {
        running = true
        thread = Thread(::run, "CouchSubs sample frames").apply {
            isDaemon = true
            start()
        }
    }

    override fun dispose() {
        running = false
        thread?.interrupt()
    }

    private fun run() {
        onState(SessionState.Streaming)
        val begin = System.currentTimeMillis()
        var shown: Int? = -1
        var frame: VideoFrame? = null
        try {
            while (running) {
                val line = DemoScript.lineIndex(System.currentTimeMillis() - begin)
                if (frame == null || line != shown) {
                    frame = render(line)
                    shown = line
                }
                framesReceived++
                frame.buffer.clear()
                onFrame(frame)
                Thread.sleep(FRAME_MS)
            }
        } catch (error: InterruptedException) {
            // Kapatıldı.
        }
    }

    /** Kareyi çizer ve okuma hattının beklediği parlaklık (Y) düzlemine çevirir. */
    private fun render(line: Int?): VideoFrame {
        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawScene(canvas, (line ?: 0) / 4)
        drawText(canvas, DemoScript.objective.english, 24f, centered = false, top = 0.08f)
        if (line != null) drawText(canvas, DemoScript.lines[line % DemoScript.lines.size].english, 36f, centered = true, top = SUBTITLE_BASELINE)
        val pixels = IntArray(WIDTH * HEIGHT)
        bitmap.getPixels(pixels, 0, WIDTH, 0, 0, WIDTH, HEIGHT)
        bitmap.recycle()
        val luma = ByteBuffer.allocateDirect(WIDTH * HEIGHT)
        for (p in pixels) {
            val r = (p shr 16) and 0xff
            val g = (p shr 8) and 0xff
            val b = p and 0xff
            luma.put(((77 * r + 150 * g + 29 * b) shr 8).toByte())
        }
        luma.clear()
        return VideoFrame(luma, WIDTH, HEIGHT, WIDTH)
    }

    private fun drawScene(canvas: Canvas, scene: Int) {
        val w = WIDTH.toFloat()
        val h = HEIGHT.toFloat()
        val palettes = listOf(
            intArrayOf(0xFF293866.toInt(), 0xFFDB8C61.toInt(), 0xFF1A3D5C.toInt(), 0xFF1F3329.toInt()),
            intArrayOf(0xFF141A38.toInt(), 0xFF5C4D80.toInt(), 0xFF0F243D.toInt(), 0xFF141F1F.toInt()),
            intArrayOf(0xFF4D759E.toInt(), 0xFFC7D1CC.toInt(), 0xFF295770.toInt(), 0xFF334D33.toInt()),
        )
        val (sky, horizon, sea, land) = palettes[scene % palettes.size].toList()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, h * 0.62f, sky, horizon, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h * 0.62f, paint)
        paint.shader = null
        paint.color = 0xD9FFEBBF.toInt()
        canvas.drawCircle(w * 0.70f + 45f, h * 0.48f - 45f, 45f, paint)
        paint.color = sea
        canvas.drawRect(0f, h * 0.60f, w, h, paint)
        paint.color = 0x1FFFFFFF
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        for (row in 0 until 6) {
            val y = h * 0.64f + row * 38f
            val wave = Path().apply {
                moveTo(0f, y)
                var x = 0
                while (x <= WIDTH) {
                    lineTo(x.toFloat(), y + if (x / 40 % 2 == 0) -4f else 4f)
                    x += 40
                }
            }
            canvas.drawPath(wave, paint)
        }
        paint.style = Paint.Style.FILL
        paint.color = land
        canvas.drawPath(Path().apply {
            moveTo(0f, h * 0.60f)
            cubicTo(w * 0.06f, h * 0.40f, w * 0.30f, h * 0.42f, w * 0.42f, h * 0.60f)
            close()
        }, paint)
        // Deniz feneri: gövde, şeritler, ışık odası ve ışık.
        val baseX = w * 0.16f
        val baseY = h * 0.50f
        paint.color = 0xFFEDEBE0.toInt()
        canvas.drawPath(Path().apply {
            moveTo(baseX - 26f, baseY)
            lineTo(baseX + 26f, baseY)
            lineTo(baseX + 16f, baseY - 150f)
            lineTo(baseX - 16f, baseY - 150f)
            close()
        }, paint)
        paint.color = 0xFFB8332E.toInt()
        canvas.drawRect(baseX - 22f, baseY - 58f, baseX + 22f, baseY - 40f, paint)
        canvas.drawRect(baseX - 19f, baseY - 111f, baseX + 19f, baseY - 95f, paint)
        paint.color = 0xFFFFE073.toInt()
        canvas.drawRect(baseX - 14f, baseY - 172f, baseX + 14f, baseY - 150f, paint)
        paint.color = 0x2EFFE073
        canvas.drawPath(Path().apply {
            moveTo(baseX, baseY - 161f)
            lineTo(w * 0.55f, baseY - 210f)
            lineTo(w * 0.55f, baseY - 120f)
            close()
        }, paint)
    }

    /** Yazı, okunaklı olsun diye yarı saydam koyu kutunun üstünde beyaz çizilir. [top]: taban çizgisinin üstten oranı. */
    private fun drawText(canvas: Canvas, text: String, size: Float, centered: Boolean, top: Float) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            textSize = size
            color = 0xFFFFFFFF.toInt()
        }
        val width = paint.measureText(text)
        val x = if (centered) (WIDTH - width) / 2 else 48f
        val baseline = HEIGHT * top
        val metrics = paint.fontMetrics
        val pad = size * 0.45f
        val box = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x9E000000.toInt() }
        canvas.drawRoundRect(RectF(x - pad, baseline + metrics.ascent - pad * 0.6f, x + width + pad, baseline + metrics.descent + pad * 0.6f),
            8f, 8f, box)
        canvas.drawText(text, x, baseline, paint)
    }
}
