// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Alan çerçevesinin parmakla düzenlenmesi (Ayarlar › Alan önizlemesi): hangi tutamacın tutulduğu, taşıma ve
 * boyutlandırma. Çerçevenin sekiz tutamacı vardır (köşeler ve kenar ortaları). Altyazı alanında "Ortada tut" açıksa
 * (varsayılan, AppSettings.keepAreaCentered) yatay boyut ortadan değişir: sağ kenar çekilince sol kenar da aynı kadar
 * açılır, alan ortalı kalır (oyunların çoğu altyazıyı ortalar). Kapalıysa (sola yaslı ya da köşedeki altyazı) ve ek
 * alanlarda kenarlar serbesttir: yalnız tutulan kenar oynar. Windows'taki CouchSubs.Core/RegionEdit.cs ve
 * Mac/iPhone'daki RegionEdit.swift ile aynı kurallar.
 */
object RegionEdit {
    const val LEFT = 1
    const val TOP = 2
    const val RIGHT = 4
    const val BOTTOM = 8
    /** Taşıma (çerçevenin içi). */
    const val MOVE = 0

    /**
     * Çerçeve düzenlenirken bir kenarın en küçük boyu (kenara oranla); tek satırlık küçük HUD yazıları için
     * kaydırıcıların sınırından ([MINIMUM_REGION_SIZE]) küçüktür.
     */
    const val MINIMUM_SIZE = 0.03

    /**
     * Önizlemedeki nokta (0–1) hangi tutamaçta (kenar bitleri): çerçevenin içinde ve kenarlardan uzaktaysa [MOVE];
     * çerçevenin dışındaysa null. [grabX]/[grabY]: tutma payı (kenara oranla).
     */
    fun handleAt(region: CropRegion, x: Double, y: Double, grabX: Double, grabY: Double): Int? {
        if (x < region.left - grabX || x > region.right + grabX || y < region.top - grabY || y > region.bottom + grabY) return null
        var handle = MOVE
        // Çok küçük bir çerçevede iki kenar üst üste gelirse daha yakın olan tutulur.
        val left = abs(x - region.left)
        val right = abs(x - region.right)
        if (min(left, right) <= grabX) handle = handle or if (left <= right) LEFT else RIGHT
        val top = abs(y - region.top)
        val bottom = abs(y - region.bottom)
        if (min(top, bottom) <= grabY) handle = handle or if (top <= bottom) TOP else BOTTOM
        if (handle == MOVE && (x < region.left || x > region.right || y < region.top || y > region.bottom)) return null
        return handle
    }

    /**
     * [start] çerçevesi [handle]'dan (dx, dy) kadar sürüklendi. [MOVE] taşır; kenarlar boyutlandırır. [centered]: yatay
     * boyut ortadan değişir. Çerçeve karenin dışına taşmaz ve her kenarda en az [MINIMUM_SIZE] kalır.
     */
    fun dragged(start: CropRegion, handle: Int, dx: Double, dy: Double, centered: Boolean): CropRegion {
        if (handle == MOVE) {
            val width = start.right - start.left
            val height = start.bottom - start.top
            val left = clamp(start.left + dx, 0.0, 1 - width)
            val top = clamp(start.top + dy, 0.0, 1 - height)
            return CropRegion(top = top, bottom = top + height, left = left, right = left + width)
        }
        var t = start.top
        var b = start.bottom
        var l = start.left
        var r = start.right
        if (handle and TOP != 0) t = clamp(start.top + dy, 0.0, start.bottom - MINIMUM_SIZE)
        if (handle and BOTTOM != 0) b = clamp(start.bottom + dy, start.top + MINIMUM_SIZE, 1.0)
        if (centered && handle and (LEFT or RIGHT) != 0) {
            val center = (start.left + start.right) / 2
            var half = if (handle and RIGHT != 0) start.right + dx - center else center - (start.left + dx)
            half = clamp(half, MINIMUM_SIZE / 2, max(MINIMUM_SIZE / 2, min(center, 1 - center)))
            l = max(0.0, center - half)
            r = min(1.0, center + half)
        } else {
            if (handle and LEFT != 0) l = clamp(start.left + dx, 0.0, start.right - MINIMUM_SIZE)
            if (handle and RIGHT != 0) r = clamp(start.right + dx, start.left + MINIMUM_SIZE, 1.0)
        }
        return CropRegion(top = t, bottom = b, left = l, right = r)
    }

    /** Bir tutamacın yeri (0–1) ve kenar bitleri. */
    data class Grip(val x: Double, val y: Double, val handle: Int)

    /** Sekiz tutamaç: köşeler ve kenar ortaları, saat yönünde sol üstten. */
    fun handles(region: CropRegion): List<Grip> {
        val midX = (region.left + region.right) / 2
        val midY = (region.top + region.bottom) / 2
        return listOf(
            Grip(region.left, region.top, LEFT or TOP), Grip(midX, region.top, TOP), Grip(region.right, region.top, RIGHT or TOP),
            Grip(region.right, midY, RIGHT), Grip(region.right, region.bottom, RIGHT or BOTTOM), Grip(midX, region.bottom, BOTTOM),
            Grip(region.left, region.bottom, LEFT or BOTTOM), Grip(region.left, midY, LEFT),
        )
    }

    private fun clamp(value: Double, low: Double, high: Double) = min(max(value, low), high)
}
