// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ocr

import com.couchsubs.mobile.core.CropRegion
import com.couchsubs.mobile.core.GamePhoneGeometry
import com.couchsubs.mobile.core.GamePhoneReader
import com.couchsubs.mobile.core.GrayFrame
import com.couchsubs.mobile.core.PhoneCapture
import com.couchsubs.mobile.core.PhoneImage
import com.couchsubs.mobile.remoteplay.VideoFrame

/** Çözücünün sınırlı aralıklı parlaklığından (16–235) oyun telefonu kurallarının tonu: 256 × tam aralıklı parlaklık. */
internal fun phoneTone(luma: Int): Int = (298 * (luma - 16)).coerceIn(0, 65280)

/**
 * Canlı kare, oyun telefonunu aramak için ([com.couchsubs.mobile.core.GamePhoneGeometry.locate] yalnız parlaklığa
 * bakar). Yalnız kare çağrısı süresince geçerlidir; saklanmaz.
 */
class LivePhoneImage(frame: VideoFrame) : PhoneImage {
    private val buffer = frame.buffer
    private val stride = frame.rowStride
    override val width = frame.width
    override val height = frame.height

    override fun tone(x: Int, y: Int): Int = phoneTone(buffer.get(y * stride + x).toInt() and 0xff)

    override fun rgb(x: Int, y: Int): Int {
        val gray = tone(x, y) shr 8
        return (gray shl 16) or (gray shl 8) or gray
    }
}

/**
 * Telefonun çevresinden kopyalanmış kare parçası. Koordinatlar bütün karenindir; parçanın dışındaki nokta parçanın
 * kenarına sıkıştırılır. Kare renk taşımıyorsa renkler gri tondur.
 */
class CopiedPhoneImage(override val width: Int, override val height: Int, private val pixels: RegionPixels) : PhoneImage {
    private val color = pixels.color

    private fun x(x: Int) = (x - pixels.left).coerceIn(0, pixels.width - 1)
    private fun y(y: Int) = (y - pixels.top).coerceIn(0, pixels.height - 1)

    override fun tone(x: Int, y: Int): Int = phoneTone(pixels.nv21[y(y) * pixels.width + x(x)].toInt() and 0xff)

    override fun rgb(x: Int, y: Int): Int {
        color?.let { return it(x(x), y(y)) }
        val gray = tone(x, y) shr 8
        return (gray shl 16) or (gray shl 8) or gray
    }

    override fun gray(region: CropRegion): GrayFrame? {
        val left = x((region.left * width).toInt())
        val top = y((region.top * height).toInt())
        val w = (x((region.right * width).toInt()) - left).coerceAtLeast(0)
        val h = (y((region.bottom * height).toInt()) - top).coerceAtLeast(0)
        if (w < 2 || h < 2) return null
        val luma = ByteArray(w * h)
        for (row in 0 until h) System.arraycopy(pixels.nv21, (top + row) * pixels.width + left, luma, row * w, w)
        return GrayFrame(luma, w, h)
    }
}

object PhoneFrames {
    /** Kopyalanan parçanın, okunacak alanın çevresindeki payı (piksel): kırpma çift piksele yuvarlanır, okuma 2 piksel taşar. */
    private const val MARGIN = 6

    /**
     * Açık telefonun karesi: telefon kutusunu ve eğik ekranın tamamını içine alan parça kopyalanır (canlı kare sonraki
     * karede üzerine yazılır). Kare bozuksa ya da parça çok küçükse null.
     */
    fun copy(frame: VideoFrame, pose: GamePhoneGeometry.Pose): PhoneCapture? {
        if (frame.width <= 0 || frame.height <= 0) return null
        val bounds = pose.bounds
        val screen = GamePhoneReader.screenRect(frame.width, frame.height, pose)
        val region = CropRegion(
            top = ((minOf(bounds.top * frame.height, screen[1]) - MARGIN) / frame.height).coerceIn(0.0, 1.0),
            bottom = ((maxOf(bounds.bottom * frame.height, screen[3]) + MARGIN) / frame.height).coerceIn(0.0, 1.0),
            left = ((minOf(bounds.left * frame.width, screen[0]) - MARGIN) / frame.width).coerceIn(0.0, 1.0),
            right = ((maxOf(bounds.right * frame.width, screen[2]) + MARGIN) / frame.width).coerceIn(0.0, 1.0),
        )
        val pixels = SubtitleReader.copyRegion(frame, region) ?: return null
        return PhoneCapture(CopiedPhoneImage(frame.width, frame.height, pixels), pose)
    }
}
