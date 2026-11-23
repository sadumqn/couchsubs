// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.packs

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Paket sunucusuna (server/packs) giden isteklerin imzası: paketler yalnız uygulama içinden alınsın.
 * `x-couchsubs-time` (unix saniye) ve `x-couchsubs-signature` = hex(HMAC-SHA256(sır, "GET\n<yol>\n<zaman>")).
 * Sır depoda değildir; yayın derlemesinde CI sırrı PACKS_APP_SECRET'tan BuildConfig.PACKS_APP_SECRET'a gömülür. Sır yoksa
 * (yerel geliştirici derlemesi) paket indirme hiç başlamaz. iPhone/Mac CouchSubsCore/PackSigning.swift ve Windows
 * PackSigning.cs ile aynı imza.
 */
object PackSigning {
    const val TIME_HEADER = "x-couchsubs-time"
    const val SIGNATURE_HEADER = "x-couchsubs-signature"

    fun signature(secret: String, method: String, path: String, time: Long): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return mac.doFinal("$method\n$path\n$time".toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }

    fun headers(secret: String, method: String, path: String, time: Long): Map<String, String> =
        mapOf(TIME_HEADER to time.toString(), SIGNATURE_HEADER to signature(secret, method, path.ifEmpty { "/" }, time))

    /** Boş değer sır sayılmaz. */
    fun secretOrNull(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }
}
