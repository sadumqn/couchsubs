// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Altyazı hedefinde TV seçimi (iPhone TargetScreen ile aynı): seçilen TV çeviride açılacak TV olur. */
class TvChoiceTest {
    private val lg = FoundTv("Salon", "192.168.1.30", TvBrand.LG)
    private val samsung = FoundTv("Yatak odası", "192.168.1.31", TvBrand.SAMSUNG)

    @Test
    fun choosingAnotherTvReplacesTheTarget() {
        val installed = InstalledTv(TvBrand.SAMSUNG, "192.168.1.31", 5555, "0.9.50")
        assertEquals(InstalledTv(TvBrand.LG, "192.168.1.30"), TvChoice.select(installed, lg))
        assertSame(installed, TvChoice.select(installed, samsung))
    }

    @Test
    fun savedTvStaysListedWhenItIsNotSeen() {
        val saved = InstalledTv(TvBrand.LG, "10.0.0.8")
        val list = TvChoice.list(listOf(samsung), saved, "Mutfak")
        assertEquals(listOf(FoundTv("Mutfak", "10.0.0.8", TvBrand.LG), samsung), list)
        assertEquals(listOf(lg), TvChoice.list(listOf(lg), InstalledTv(TvBrand.LG, "192.168.1.30"), "x"))
        assertTrue(TvChoice.isSelected(list[0], saved))
        assertFalse(TvChoice.isSelected(samsung, saved))
    }
}
