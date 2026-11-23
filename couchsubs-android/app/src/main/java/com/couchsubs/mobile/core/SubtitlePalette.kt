// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Altyazı Görünümü'nün renk listeleri ve yazı boyu eşlemesi (Mac/iPhone SubtitlePalette, Windows AppearanceEditor ile aynı
 * değerler). [Swatch.name] İngilizce adı; ekranda karşılığı strings.xml'den gelir.
 */
object SubtitlePalette {
    data class Swatch(val name: String, val hex: String?)

    val backgrounds = listOf(
        Swatch("Black", "#101014"), Swatch("Navy", "#0E1A30"), Swatch("Dark Gray", "#2B2D33"), Swatch("Brown", "#2A1F14"),
        Swatch("White", "#FFFFFF"), Swatch("Cream", "#F3EEE4"), Swatch("No Background", null),
    )
    val texts = listOf(
        Swatch("White", "#FFFFFF"), Swatch("Cream", "#F3EEE4"), Swatch("Yellow", "#FFE066"), Swatch("Light Blue", "#BFE3FF"),
        Swatch("Black", "#111114"), Swatch("Navy", "#0E1A30"), Swatch("Dark Gray", "#2B2D33"),
    )
    val names = listOf(
        Swatch("Amber", "#F5B83D"), Swatch("Turquoise", "#4FD1C5"), Swatch("Pink", "#FF8FAB"), Swatch("Purple", "#B794F6"),
        Swatch("Green", "#68D391"), Swatch("Orange", "#F6874F"), Swatch("Red", "#F56565"), Swatch("Blue", "#63B3ED"),
    )

    /** Koyuluk: Açık / Orta / Koyu (Koyu tam örter, İngilizce altyazı görünmez). */
    val darkness = listOf(45, 75, 100)

    /** Kaydırıcıdaki değer (16–50 px) ile TV'nin yazı boyu (16–90) arasında doğrusal eşleme; eski büyük boylar kaybolmaz. */
    fun display(fontSize: Int): Int = (16 + (fontSize.coerceIn(16, 90) - 16) * 34.0 / 74).roundToInt()
    fun fontSize(display: Int): Int = (16 + (display.coerceIn(16, 50) - 16) * 74.0 / 34).roundToInt()

    /** Seçili yazı rengi (eski kayıtta textHex yok: beyaz ya da sarı). */
    fun textHex(style: SubtitleStyle): String =
        SubtitleStyle.hex(style.textHex) ?: if (style.textColor == SubtitleTextColor.YELLOW) "#FFE066" else "#FFFFFF"

    /** Seçili koyuluk (en yakın düzey); zeminsizse null. */
    fun darknessLevel(background: Int): Int? = if (background <= 0) null else darkness.minByOrNull { abs(it - background) }

    fun rgb(hex: String?): Triple<Double, Double, Double>? {
        val value = SubtitleStyle.hex(hex)?.drop(1)?.toLongOrNull(16) ?: return null
        return Triple((value shr 16 and 0xFF) / 255.0, (value shr 8 and 0xFF) / 255.0, (value and 0xFF) / 255.0)
    }

    /** Yarı saydam zemin TV görüntüsüyle karışır: kontrast karışık renge göre (WCAG 4.5; Mac ile aynı sahne rengi). */
    fun lowContrast(style: SubtitleStyle): Boolean {
        val scene = Triple(109.0 / 255, 106.0 / 255, 93.0 / 255)
        val alpha = style.background.coerceIn(0, 100) / 100.0
        val bg = rgb(style.backgroundColor) ?: Triple(0.0, 0.0, 0.0)
        val mixed = Triple(bg.first * alpha + scene.first * (1 - alpha), bg.second * alpha + scene.second * (1 - alpha),
            bg.third * alpha + scene.third * (1 - alpha))
        val text = rgb(textHex(style)) ?: Triple(1.0, 1.0, 1.0)
        fun l(v: Double) = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        fun lum(c: Triple<Double, Double, Double>) = 0.2126 * l(c.first) + 0.7152 * l(c.second) + 0.0722 * l(c.third)
        val x = lum(text)
        val y = lum(mixed)
        return (maxOf(x, y) + 0.05) / (minOf(x, y) + 0.05) < 4.5
    }
}

/**
 * Hızlı / Dengeli / Doğru: bozuk ve yarım okunan satır beklemelerinin hazır değerleri (Mac/iPhone TranslationPace, Windows
 * ile aynı). Gelişmiş'teki iki kaydırıcıyla aynı ayar; başka değerdeyse hiçbiri seçili değildir.
 */
enum class TranslationPace(val misreadMs: Int, val partialMs: Int) {
    FAST(400, 0), BALANCED(SubtitlePipeline.PACK_WAIT_MS, SubtitlePipeline.CLEAN_WAIT_MS), ACCURATE(1000, 800);

    companion object {
        fun of(misreadMs: Int, partialMs: Int): TranslationPace? = entries.firstOrNull { it.misreadMs == misreadMs && it.partialMs == partialMs }
    }
}
