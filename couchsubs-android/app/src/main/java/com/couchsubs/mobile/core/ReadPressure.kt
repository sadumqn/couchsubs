// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Altyazı okuması her zaman önce gelir: ek alanların ve kendiliğinden bulunan ekran yazılarının okuması altyazı okumasını
 * geciktiriyorsa kendini kısar (#679; Mac ve iPhone: ReadQueue.backgroundSlowdown, Windows: ReadPressure).
 */
object ReadPressure {
    /** Son altyazı okuması bundan uzun sürdüyse ek alan turları iki kat seyrekleşir. */
    const val SLOW_READ_MS = 700L

    /** Bundan uzun sürdüyse (ya da süren okuma bu kadardır bitmediyse) dört kat. */
    const val VERY_SLOW_READ_MS = 1500L

    /**
     * Ek alan tur aralığının çarpanı (1, 2 ya da 4). [lastReadMs]: son altyazı okumasının süresi; [busyMs]: şu an süren
     * altyazı okumasının ne kadardır sürdüğü (sürmüyorsa 0).
     */
    fun slowdown(lastReadMs: Int?, busyMs: Long): Int {
        val worst = maxOf((lastReadMs ?: 0).toLong(), busyMs)
        return if (worst >= VERY_SLOW_READ_MS) 4 else if (worst >= SLOW_READ_MS) 2 else 1
    }
}
