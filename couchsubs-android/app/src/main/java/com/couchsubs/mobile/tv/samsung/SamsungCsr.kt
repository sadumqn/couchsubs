// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import java.io.ByteArrayOutputStream
import java.security.KeyPair
import java.security.Signature
import java.util.Base64

/** Yalnız sertifika isteği için gereken kadar DER (ASN.1) yazıcı; Android'de CertificateRequest karşılığı yok. */
internal object Der {
    fun tlv(tag: Int, content: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(tag)
        val length = content.size
        when {
            length < 0x80 -> out.write(length)
            length < 0x100 -> { out.write(0x81); out.write(length) }
            length < 0x10000 -> { out.write(0x82); out.write(length shr 8); out.write(length and 0xFF) }
            else -> { out.write(0x83); out.write(length shr 16); out.write((length shr 8) and 0xFF); out.write(length and 0xFF) }
        }
        out.write(content)
        return out.toByteArray()
    }

    fun sequence(vararg items: ByteArray) = tlv(0x30, concat(*items))
    fun set(vararg items: ByteArray) = tlv(0x31, concat(*items))
    fun integer(value: Int) = tlv(0x02, byteArrayOf(value.toByte()))
    fun utf8(text: String) = tlv(0x0C, text.toByteArray(Charsets.UTF_8))
    fun ia5(text: String, tag: Int = 0x16) = tlv(tag, text.toByteArray(Charsets.US_ASCII))
    fun octets(content: ByteArray) = tlv(0x04, content)
    fun bits(content: ByteArray) = tlv(0x03, byteArrayOf(0) + content)
    val NULL = byteArrayOf(0x05, 0x00)

    fun oid(dotted: String): ByteArray {
        val parts = dotted.split('.').map { it.toLong() }
        val out = ByteArrayOutputStream()
        out.write((parts[0] * 40 + parts[1]).toInt())
        for (part in parts.drop(2)) {
            val groups = ArrayList<Int>()
            var value = part
            do {
                groups.add((value and 0x7F).toInt())
                value = value shr 7
            } while (value > 0)
            for (i in groups.indices.reversed()) out.write(groups[i] or if (i > 0) 0x80 else 0)
        }
        return tlv(0x06, out.toByteArray())
    }

    fun concat(vararg items: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        items.forEach { out.write(it) }
        return out.toByteArray()
    }
}

/**
 * Samsung'a gönderilen PKCS#10 sertifika istekleri (masaüstünde SamsungCertificates.AuthorRequest ve DistributorRequest).
 * Yazar ve dağıtıcı isteği aynı RSA anahtarıyla, SHA-256 ile imzalanır.
 */
object SamsungCsr {
    private const val COMMON_NAME = "2.5.4.3"
    private const val EMAIL = "1.2.840.113549.1.9.1"
    private const val EXTENSION_REQUEST = "1.2.840.113549.1.9.14"
    private const val SUBJECT_ALT_NAME = "2.5.29.17"
    private const val SHA256_WITH_RSA = "1.2.840.113549.1.1.11"

    /** Yazar sertifikası isteği: CN=CouchSubs. */
    fun author(key: KeyPair): ByteArray = pem(request(key, name(Der.utf8("CouchSubs"), null), null))

    /**
     * Dağıtıcı isteği: CN=TizenSDK (ve hesabın e-postası). TV, imzayı yalnız kendi DUID'i sertifikada yazılıysa kabul
     * eder; adlar olduğu gibi (büyük harfle) URI olarak yazılır.
     */
    fun distributor(key: KeyPair, duid: String, email: String): ByteArray {
        val names = Der.sequence(
            Der.ia5("URN:tizen:packageid=", 0x86),
            Der.ia5("URN:tizen:deviceid=$duid", 0x86),
        )
        val extension = Der.sequence(Der.oid(SUBJECT_ALT_NAME), Der.octets(names))
        return pem(request(key, name(Der.utf8("TizenSDK"), email.takeIf { it.isNotBlank() }), Der.sequence(extension)))
    }

    private fun name(commonName: ByteArray, email: String?): ByteArray {
        val cn = Der.set(Der.sequence(Der.oid(COMMON_NAME), commonName))
        return if (email == null) Der.sequence(cn) else Der.sequence(cn, Der.set(Der.sequence(Der.oid(EMAIL), Der.ia5(email))))
    }

    private fun request(key: KeyPair, subject: ByteArray, extensions: ByteArray?): ByteArray {
        val attributes = if (extensions == null) Der.tlv(0xA0, ByteArray(0))
        else Der.tlv(0xA0, Der.sequence(Der.oid(EXTENSION_REQUEST), Der.set(extensions)))
        // SubjectPublicKeyInfo, Java'nın X.509 biçimindeki açık anahtarının kendisidir.
        val info = Der.sequence(Der.integer(0), subject, key.public.encoded, attributes)
        val signature = Signature.getInstance("SHA256withRSA").run { initSign(key.private); update(info); sign() }
        return Der.sequence(info, Der.sequence(Der.oid(SHA256_WITH_RSA), Der.NULL), Der.bits(signature))
    }

    fun pem(der: ByteArray, label: String = "CERTIFICATE REQUEST"): ByteArray {
        val body = Base64.getEncoder().encodeToString(der).chunked(64).joinToString("\n")
        return "-----BEGIN $label-----\n$body\n-----END $label-----".toByteArray(Charsets.US_ASCII)
    }
}
