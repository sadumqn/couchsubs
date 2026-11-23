// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * "Başka bir cihazda göster": aynı ağdaki telefon ya da tabletin tarayıcısında canlı altyazı. Sayfa (`/view`) ve akışı
 * (`/events?viewer=second`) erişim anahtarı ister; anahtar adresin içindedir ve QR kodla verilir. Sayfa TV sayılmaz,
 * altyazı hedefi ne olursa olsun olayları alır (Mac/iPhone: SecondScreen.swift, Windows: SecondScreen.cs).
 */
object SecondScreen {
    const val PATH = "/view"
    const val VIEWER = "second"

    /** Tarayıcıda açılan adres: `http://<ağ adresi>:<port>/view?k=<anahtar>`. */
    fun address(host: String, port: Int, key: String): String {
        val shown = if (host.contains(':')) "[$host]" else host
        return "http://$shown:$port$PATH?k=${java.net.URLEncoder.encode(key, "UTF-8")}"
    }

    /** Adresin QR kodu: satır satır modüller (true: koyu), çevresinde dört modül boşlukla. */
    fun qrModules(text: String): Array<BooleanArray> {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 4)
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, hints)
        return Array(matrix.height) { y -> BooleanArray(matrix.width) { x -> matrix[x, y] } }
    }
}
