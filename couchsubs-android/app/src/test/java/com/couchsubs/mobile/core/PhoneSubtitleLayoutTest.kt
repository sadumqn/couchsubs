// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** "Bu telefonda" ekranında parmakla yer ve yazı boyu: iPhone'daki SubtitlePositionTests ile aynı durumlar. */
class PhoneSubtitleLayoutTest {
    @Test fun dragAndPinchStayInBounds() {
        assertEquals(-0.2f, PhoneSubtitleLayout.offset(0f, -200f, 1000f), 1e-6f)
        assertEquals(-PhoneSubtitleLayout.LARGEST_OFFSET, PhoneSubtitleLayout.offset(-0.3f, -500f, 1000f))
        assertEquals(0.1f, PhoneSubtitleLayout.offset(0.1f, 50f, 0f))
        assertEquals(0f, PhoneSubtitleLayout.clampOffset(Float.NaN))
        assertEquals(1.5f, PhoneSubtitleLayout.scale(1f, 1.5f))
        assertEquals(PhoneSubtitleLayout.LARGEST_SCALE, PhoneSubtitleLayout.scale(1.5f, 4f))
        assertEquals(PhoneSubtitleLayout.SMALLEST_SCALE, PhoneSubtitleLayout.scale(1f, 0.1f))
        assertEquals(1.2f, PhoneSubtitleLayout.scale(1.2f, Float.NaN))
        assertEquals(1f, PhoneSubtitleLayout.clampScale(-1f))
    }
}
