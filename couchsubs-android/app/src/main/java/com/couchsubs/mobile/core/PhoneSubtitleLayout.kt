// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * "Bu telefonda" altyazı ekranında parmakla verilen yer ve yazı boyu (kalıcı; TV'nin yazı boyuna dokunmaz). Yer, altyazının
 * varsayılan yerinden ekran yüksekliğine oranla kaydırmadır (negatif: yukarı). iPhone: PhoneSubtitleLayout.swift.
 */
object PhoneSubtitleLayout {
    const val SMALLEST_SCALE = 0.6f
    const val LARGEST_SCALE = 2.0f
    /** Altyazı ekranın en çok bu oranı kadar yukarı ya da aşağı kaydırılır (yazı ekrandan çıkmaz). */
    const val LARGEST_OFFSET = 0.4f

    fun clampScale(scale: Float): Float = if (scale.isFinite() && scale > 0f) scale.coerceIn(SMALLEST_SCALE, LARGEST_SCALE) else 1f

    fun clampOffset(offset: Float): Float = if (offset.isFinite()) offset.coerceIn(-LARGEST_OFFSET, LARGEST_OFFSET) else 0f

    /** Sürükleme: [moved] parmağın gittiği yol (piksel), [height] ekran yüksekliği (piksel). */
    fun offset(start: Float, moved: Float, height: Float): Float =
        if (!height.isFinite() || height <= 0f || !moved.isFinite()) clampOffset(start) else clampOffset(start + moved / height)

    /** İki parmakla büyütüp küçültme: [zoom] hareketin çarpanı (1: değişmedi). */
    fun scale(start: Float, zoom: Float): Float =
        if (!zoom.isFinite() || zoom <= 0f) clampScale(start) else clampScale(start * zoom)
}
