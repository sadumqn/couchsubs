// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.ocr.SubtitleReader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer

/** Yerel çözücünün verdiği Y düzleminden altyazı bölgesinin kopyalanması (ImageReader'sız kare yolu). */
class VideoFrameTest {
    private fun frame(width: Int, height: Int, stride: Int): VideoFrame {
        val buffer = ByteBuffer.allocateDirect(stride * height)
        for (y in 0 until height) for (x in 0 until stride) buffer.put(y * stride + x, if (x < width) (y + x).toByte() else 0x7f.toByte())
        return VideoFrame(buffer, width, height, stride)
    }

    @Test fun copiesRegionRowsWithStride() {
        val source = frame(64, 48, 80)
        val pixels = SubtitleReader.copyRegion(source, CropRegion(top = 0.5, bottom = 1.0, left = 0.25, right = 0.75))
        assertNotNull(pixels)
        assertEquals(32, pixels!!.width)
        assertEquals(24, pixels.height)
        assertEquals(32 * 24 * 3 / 2, pixels.nv21.size)
        // İlk satır: y = 24, x = 16.
        assertEquals((24 + 16).toByte(), pixels.nv21[0])
        assertEquals((24 + 16 + 31).toByte(), pixels.nv21[31])
        assertEquals((47 + 16).toByte(), pixels.nv21[23 * 32])
        // Renk düzlemi nötr.
        assertEquals(128.toByte(), pixels.nv21[32 * 24])
    }

    @Test fun skipsFrameThatIsTooSmallForItsStride() {
        // Arabellek biçimin söylediğinden küçük: okuma sınır dışına taşmaz, kare atlanır.
        val small = VideoFrame(ByteBuffer.allocateDirect(64 * 10), 64, 48, 64)
        assertNull(SubtitleReader.copyRegion(small, CropRegion(top = 0.5, bottom = 1.0, left = 0.0, right = 1.0)))
    }

    @Test fun rejectsStrideBelowWidth() {
        assertNull(SubtitleReader.copyRegion(VideoFrame(ByteBuffer.allocateDirect(4096), 64, 48, 32), CropRegion()))
    }
}
