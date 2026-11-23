// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.couchsubs.mobile.core.RegionEdit.BOTTOM
import com.couchsubs.mobile.core.RegionEdit.LEFT
import com.couchsubs.mobile.core.RegionEdit.MOVE
import com.couchsubs.mobile.core.RegionEdit.RIGHT
import com.couchsubs.mobile.core.RegionEdit.TOP
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Alan çerçevesinin tutamaçları, taşınması ve boyutlandırılması (Windows ve Mac/iPhone ile aynı örnekler). */
class RegionEditTest {
    private val area = CropRegion(top = 0.60, bottom = 0.90, left = 0.20, right = 0.80)
    private val grab = 0.02

    private fun assertClose(expected: CropRegion, actual: CropRegion) =
        assertTrue("$expected != $actual", expected.isClose(actual, 1e-9))

    @Test
    fun handlesAreTheCornersAndEdgeMiddles() {
        assertEquals(LEFT or TOP, RegionEdit.handleAt(area, 0.20, 0.60, grab, grab))
        assertEquals(TOP, RegionEdit.handleAt(area, 0.50, 0.60, grab, grab))
        assertEquals(RIGHT, RegionEdit.handleAt(area, 0.80, 0.75, grab, grab))
        assertEquals(RIGHT or BOTTOM, RegionEdit.handleAt(area, 0.81, 0.91, grab, grab))
        assertEquals(MOVE, RegionEdit.handleAt(area, 0.50, 0.75, grab, grab))
    }

    @Test
    fun farOutsideIsNoHandleAndATinyFrameTakesTheNearerEdge() {
        assertNull(RegionEdit.handleAt(area, 0.10, 0.75, grab, grab))
        assertNull(RegionEdit.handleAt(area, 0.50, 0.30, grab, grab))
        assertEquals(RIGHT, RegionEdit.handleAt(CropRegion(0.50, 0.90, 0.50, 0.51), 0.512, 0.70, grab, grab))
    }

    @Test
    fun eightHandlesSitOnTheCornersAndEdgeMiddles() {
        val handles = RegionEdit.handles(area)
        assertEquals(8, handles.size)
        assertTrue(RegionEdit.Grip(0.50, 0.60, TOP) in handles)
        assertTrue(RegionEdit.Grip(0.80, 0.75, RIGHT) in handles)
        assertTrue(RegionEdit.Grip(0.20, 0.90, LEFT or BOTTOM) in handles)
    }

    @Test
    fun movingKeepsTheSizeAndStaysInTheFrame() {
        assertClose(CropRegion(0.65, 0.95, 0.10, 0.70), RegionEdit.dragged(area, MOVE, -0.10, 0.05, centered = true))
        assertClose(CropRegion(0.70, 1.00, 0.40, 1.00), RegionEdit.dragged(area, MOVE, 0.50, 0.50, centered = false))
    }

    @Test
    fun theSubtitleAreaWidensFromTheMiddle() {
        assertClose(CropRegion(0.60, 0.90, 0.10, 0.90), RegionEdit.dragged(area, RIGHT, 0.10, 0.0, centered = true))
        assertClose(CropRegion(0.60, 0.90, 0.30, 0.70), RegionEdit.dragged(area, LEFT, 0.10, 0.0, centered = true))
        assertClose(CropRegion(0.60, 0.90, 0.00, 1.00), RegionEdit.dragged(area, RIGHT, 0.50, 0.0, centered = true))
        assertClose(CropRegion(0.60, 0.95, 0.15, 0.85), RegionEdit.dragged(area, RIGHT or BOTTOM, 0.05, 0.05, centered = true))
    }

    @Test
    fun extraAreasResizeFromTheDraggedEdgeOnly() {
        assertClose(CropRegion(0.60, 0.90, 0.20, 0.90), RegionEdit.dragged(area, RIGHT, 0.10, 0.0, centered = false))
        assertClose(CropRegion(0.50, 0.90, 0.10, 0.80), RegionEdit.dragged(area, LEFT or TOP, -0.10, -0.10, centered = false))
    }

    @Test
    fun withoutKeepCenteredALeftAlignedSubtitleAreaKeepsItsLeftEdge() {
        // Sola yaslı altyazı: "Ortada tut" kapalıyken sağ kenar çekilince sol kenar yerinde kalır.
        val left = CropRegion(0.80, 0.95, 0.05, 0.45)
        assertClose(CropRegion(0.80, 0.95, 0.05, 0.55), RegionEdit.dragged(left, RIGHT, 0.10, 0.0, centered = false))
        assertClose(CropRegion(0.70, 0.95, 0.00, 0.45), RegionEdit.dragged(left, LEFT or TOP, -0.05, -0.10, centered = false))
        // Açıkken aynı sürükleme sol kenarı da oynatır ve karenin kenarına dayar.
        assertClose(CropRegion(0.80, 0.95, 0.00, 0.50), RegionEdit.dragged(left, RIGHT, 0.10, 0.0, centered = true))
    }

    @Test
    fun aFrameNeverGetsSmallerThanTheMinimumOrFlips() {
        assertEquals(area.right - RegionEdit.MINIMUM_SIZE, RegionEdit.dragged(area, LEFT, 0.90, 0.0, centered = false).left, 1e-9)
        assertEquals(area.bottom - RegionEdit.MINIMUM_SIZE, RegionEdit.dragged(area, TOP, 0.0, 0.90, centered = false).top, 1e-9)
        val centered = RegionEdit.dragged(area, RIGHT, -0.90, 0.0, centered = true)
        assertEquals(RegionEdit.MINIMUM_SIZE, centered.right - centered.left, 1e-9)
        assertEquals(0.50, (centered.left + centered.right) / 2, 1e-9)
    }
}
