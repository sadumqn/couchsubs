// SPDX-License-Identifier: AGPL-3.0-only
// Samsung'un sertifika uç noktaları ve istek biçimleri Apps2Samsung'dan (MIT, Patrick Stel) alındı; masaüstündeki
// windows/src/CouchSubs.TvInstall/Samsung/SamsungCertificates.cs'in Kotlin karşılığı.
package com.couchsubs.mobile.tv.samsung

import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Samsung hesabıyla girişten dönen bilgiler; sertifika istemek için gerekir. */
data class SamsungAccount(val accessToken: String, val userId: String, val email: String)

/**
 * Bir TV için imza dosyaları. Masaüstü PKCS#12 kullanır; burada anahtar (PKCS#8) ve sertifikalar (DER) uygulamanın
 * kendi klasöründe ayrı dosyalardır, parola gerekmez.
 */
class SigningProfile(val directory: File) {
    val keyFile = File(directory, "key.pk8")
    val authorFile = File(directory, "author.cer")
    val distributorFile = File(directory, "distributor.cer")
    val deviceProfileFile = File(directory, "device-profile.xml")
    private val duidFile = File(directory, "duid.txt")

    val exists get() = keyFile.exists() && authorFile.exists() && distributorFile.exists()

    fun privateKey(): PrivateKey = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(keyFile.readBytes()))
    fun author(): X509Certificate = SamsungCertificates.readCertificate(authorFile.readBytes())
    fun distributor(): X509Certificate = SamsungCertificates.readCertificate(distributorFile.readBytes())

    /** Sertifikalar hâlâ geçerli mi (bir gün pay bırakılarak; masaüstündeki IsValid gibi)? */
    fun isValid(now: Date = Date()): Boolean {
        if (!exists) return false
        return try {
            val margin = now.time + DAY
            listOf(author(), distributor()).all { it.notBefore.time <= margin && it.notAfter.time >= margin }
        } catch (error: Exception) {
            false
        }
    }

    /** Dağıtıcı sertifikası bu TV için mi alındı? */
    fun isFor(duid: String): Boolean = try {
        !duidFile.exists() || duidFile.readText().trim() == duid
    } catch (error: IOException) {
        false
    }

    fun describe(now: Date, duid: String): String {
        if (!exists) return "yok"
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }
            val author = author()
            val distributor = distributor()
            val state = if (!isFor(duid)) "başka TV'nin" else if (isValid(now)) "geçerli" else "süresi dolmuş"
            "$state; yazar ${format.format(author.notBefore)}–${format.format(author.notAfter)} UTC, " +
                "dağıtıcı ${format.format(distributor.notBefore)}–${format.format(distributor.notAfter)} UTC, " +
                "dağıtıcıyı veren ${distributor.issuerX500Principal.name}"
        } catch (error: Exception) {
            "okunamadı (${error.message})"
        }
    }

    internal fun save(key: PrivateKey, author: ByteArray, distributor: ByteArray, deviceProfile: ByteArray, duid: String) {
        directory.mkdirs()
        keyFile.writeBytes(key.encoded)
        authorFile.writeBytes(author)
        distributorFile.writeBytes(distributor)
        deviceProfileFile.writeBytes(deviceProfile)
        duidFile.writeText(duid)
    }

    /** TV'nin reddettiği sertifikayı bir kenara koyar; bir sonraki kurulum Samsung'dan yenisini ister. */
    fun discard() {
        if (!directory.exists()) return
        val stamp = SimpleDateFormat("yyyyMMddHHmmss", Locale.ROOT).format(Date())
        if (!directory.renameTo(File(directory.parentFile, "${directory.name}.rejected-$stamp"))) directory.deleteRecursively()
    }

    companion object {
        private const val DAY = 24L * 60 * 60 * 1000
    }
}

/** Sertifika isteğinin multipart/form-data gövdesi. */
internal class Multipart(val boundary: String = "couchsubs-" + UUID.randomUUID().toString()) {
    private val out = ByteArrayOutputStream()

    val contentType get() = "multipart/form-data; boundary=$boundary"

    fun field(name: String, value: String) = apply {
        head("Content-Disposition: form-data; name=\"$name\"\r\nContent-Type: text/plain; charset=utf-8")
        out.write(value.toByteArray(Charsets.UTF_8))
        out.write("\r\n".toByteArray())
    }

    fun file(name: String, fileName: String, data: ByteArray) = apply {
        head("Content-Disposition: form-data; name=\"$name\"; filename=\"$fileName\"\r\nContent-Type: application/octet-stream")
        out.write(data)
        out.write("\r\n".toByteArray())
    }

    private fun head(headers: String) = out.write("--$boundary\r\n$headers\r\n\r\n".toByteArray(Charsets.UTF_8))

    fun build(): ByteArray = out.toByteArray() + "--$boundary--\r\n".toByteArray(Charsets.US_ASCII)
}

/** Bir HTTP isteğinin sonucu; testlerde sahte sunucu verir. */
data class HttpReply(val status: Int, val reason: String, val body: ByteArray)

fun interface HttpPost {
    fun post(url: String, contentType: String, body: ByteArray): HttpReply
}

/**
 * Samsung'dan TV'ye özel imza sertifikası alır: yazar sertifikası Samsung hesabına, dağıtıcı sertifikası TV'nin DUID'ine
 * bağlıdır. Tizen Studio'nun Certificate Manager'ının yaptığının aynısıdır.
 */
class SamsungCertificates(private val http: HttpPost = UrlConnectionPost, private val log: (String) -> Unit = {}) {
    companion object {
        const val AUTHOR_URL = "https://svdca.samsungqbe.com/apis/v3/authors"
        const val DISTRIBUTOR_PROFILE_URL = "https://svdca.samsungqbe.com/apis/v1/distributors"
        const val DISTRIBUTOR_URL = "https://svdca.samsungqbe.com/apis/v3/distributors"

        /** Bir sertifika isteğinin gövdesi (alan sırası masaüstüyle aynı). */
        internal fun requestBody(account: SamsungAccount, csr: ByteArray, fileName: String, distributor: Boolean,
                                 multipart: Multipart = Multipart()): Multipart {
            multipart.field("access_token", account.accessToken).field("user_id", account.userId).field("platform", "VD")
            if (distributor) multipart.field("privilege_level", "public").field("developer_type", "Individual")
            return multipart.file("csr", fileName, csr)
        }

        /** Samsung'un hata yanıtı: JSON ise iletisi ve kodu, değilse metnin başı. */
        fun serverError(body: ByteArray): String {
            val text = String(body, Charsets.UTF_8).trim()
            try {
                val json = JSONObject(text)
                val parts = listOf("code", "errorCode", "error", "message", "errorMessage", "error_description")
                    .mapNotNull { name -> json.opt(name)?.takeIf { it is String || it is Number }?.let { "$name=$it" } }
                if (parts.isNotEmpty()) return parts.joinToString(", ")
            } catch (error: Exception) {
            }
            return if (text.length <= 300) text else text.take(300) + "…"
        }

        /** PEM ya da DER sertifika. */
        fun readCertificate(data: ByteArray): X509Certificate =
            CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(data)) as X509Certificate

        /** Samsung'un geliştirici sertifikalarını veren ara sertifikalar (Tizen Studio'dan, değiştirilmeden). */
        val authorities: List<X509Certificate> by lazy {
            listOf("vd_tizen_dev_author_ca", "author_ca", "vd_tizen_dev_public2", "public2").mapNotNull { name ->
                SamsungCertificates::class.java.getResourceAsStream("/samsung-ca/$name.pem")?.use { readCertificate(it.readBytes()) }
            }
        }

        /** İmzadaki zincir: yaprak ve onu veren Samsung ara sertifikası (kök yok). */
        fun chain(leaf: X509Certificate): List<X509Certificate> {
            // Adlar kanonik biçimde karşılaştırılır (aynı ad farklı ASN.1 dizgi türüyle yazılmış olabilir).
            fun name(principal: javax.security.auth.x500.X500Principal) = principal.getName(javax.security.auth.x500.X500Principal.CANONICAL)
            val issuer = authorities.firstOrNull {
                name(it.subjectX500Principal) == name(leaf.issuerX500Principal) && name(it.subjectX500Principal) != name(it.issuerX500Principal)
            }
            return listOfNotNull(leaf, issuer)
        }
    }

    /** Sertifikaları alır ve [profile] klasörüne yazar. */
    fun create(duid: String, account: SamsungAccount, profile: SigningProfile): SigningProfile {
        val key = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val authorCsr = SamsungCsr.author(key)
        val distributorCsr = SamsungCsr.distributor(key, duid, account.email)
        val author = post(AUTHOR_URL, requestBody(account, authorCsr, "author.csr", distributor = false))
        // Eski TV'ler (Tizen 4 ve öncesi) için cihaz profili; yenilerde kullanılmaz ama saklanır.
        val deviceProfile = post(DISTRIBUTOR_PROFILE_URL, requestBody(account, distributorCsr, "distributor.csr", distributor = true))
        val distributor = post(DISTRIBUTOR_URL, requestBody(account, distributorCsr, "distributor.csr", distributor = true))
        profile.save(key.private, issued(author, "yazar").encoded, issued(distributor, "dağıtıcı").encoded, deviceProfile, duid)
        return profile
    }

    private fun post(url: String, body: Multipart): ByteArray {
        val step = URL(url).path
        val reply = try {
            http.post(url, body.contentType, body.build())
        } catch (error: IOException) {
            log("Sertifika sunucusuna ulaşılamadı ($step): $error")
            throw SamsungInstallException(SamsungInstallError.CERTIFICATE_FAILED,
                "Samsung'un sertifika sunucusuna (${URL(url).host}) ulaşılamadı: ${error.message}")
        }
        log("Sertifika sunucusu $step: ${reply.status} ${reply.reason}, ${reply.body.size} bayt")
        if (reply.status !in 200..299) {
            val text = serverError(reply.body)
            log("Sertifika sunucusunun yanıtı: $text")
            throw SamsungInstallException(SamsungInstallError.CERTIFICATE_FAILED,
                "Samsung sertifika sunucusu $step: ${reply.status} ${reply.reason} $text".trim())
        }
        return reply.body
    }

    /** Samsung bazen başarılı yanıtın içinde sertifika yerine hata metni döndürür. */
    private fun issued(data: ByteArray, kind: String): X509Certificate = try {
        readCertificate(data)
    } catch (error: Exception) {
        val text = serverError(data)
        log("Samsung'un $kind sertifikası okunamadı (${error.message}); yanıt: $text")
        throw SamsungInstallException(SamsungInstallError.CERTIFICATE_FAILED, "Samsung $kind sertifikası vermedi: $text")
    }
}

/** Gerçek HTTP (HttpURLConnection). */
object UrlConnectionPost : HttpPost {
    override fun post(url: String, contentType: String, body: ByteArray): HttpReply {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", contentType)
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            return HttpReply(status, connection.responseMessage ?: "", bytes)
        } finally {
            connection.disconnect()
        }
    }
}
