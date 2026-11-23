// SPDX-License-Identifier: AGPL-3.0-only
// Giriş akışı Apps2Samsung'dan (MIT, Patrick Stel) uyarlandı; masaüstündeki SamsungLogin.cs'in Kotlin karşılığı.
package com.couchsubs.mobile.tv.samsung

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * Samsung hesabıyla giriş. Samsung'un SignInGate sayfası jetonu `http://localhost:4794/signin/callback`'e POST eder;
 * telefonda bu adresi uygulamanın içindeki küçük bir dinleyici karşılar (Tizen Studio ve masaüstü uygulamaları da aynı
 * yolu kullanır). Sayfa uygulama içindeki WebView'da ya da telefonun tarayıcısında açılabilir; ikisi de aynı cihazın
 * localhost'una gönderir.
 */
object SamsungLogin {
    private const val SIGN_IN_GATE = "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate"
    private const val CLIENT_ID = "v285zxnl3h"
    private const val STATE = "accountcheckdogeneratedstatetext"
    const val CALLBACK_PORT = 4794
    const val CALLBACK_PATH = "/signin/callback"

    val authorizeUrl: String
        get() = "$SIGN_IN_GATE?locale=&clientId=$CLIENT_ID" +
            "&redirect_uri=${URLEncoder.encode("http://localhost:$CALLBACK_PORT$CALLBACK_PATH", "UTF-8")}" +
            "&state=$STATE&tokenType=TOKEN"

    /** Gövde: `code=<JSON>&state=…`. JSON'da access_token, userId ve inputEmailID bulunur. */
    fun parseCallback(body: String): SamsungAccount? {
        var state: String? = null
        var code: String? = null
        for (part in body.split('&').filter { it.isNotEmpty() }) {
            val pair = part.split('=', limit = 2)
            if (pair.size != 2) continue
            if (pair[0] == "state") state = decode(pair[1])
            // Masaüstündeki gibi (Uri.UnescapeDataString): jetonda olabilecek '+' boşluğa çevrilmez.
            if (pair[0] == "code") code = unescape(pair[1])
        }
        if (state != STATE || code.isNullOrBlank()) return null
        return try {
            val json = JSONObject(code)
            val token = json.optString("access_token").takeIf { json.opt("access_token") is String && it.isNotEmpty() }
            val user = json.optString("userId").takeIf { json.opt("userId") is String && it.isNotEmpty() }
            if (token != null && user != null) SamsungAccount(token, user, (json.opt("inputEmailID") as? String) ?: "") else null
        } catch (error: Exception) {
            null
        }
    }

    /** Geri dönüşte jeton neden yok: alan adları ve Samsung'un hata alanları (jetonun kendisi yazılmaz). */
    fun callbackProblem(body: String): String {
        val text = body.split('&').filter { it.isNotEmpty() }.joinToString(", ") { part ->
            val pair = part.split('=', limit = 2)
            val name = decode(pair[0])
            if (name in setOf("error", "error_description", "error_code", "state")) "$name=${decode(pair.getOrElse(1) { "" })}" else name
        }
        return text.take(200)
    }

    /** Yalnız %XX dizilerini çözer ('+' olduğu gibi kalır). */
    internal fun unescape(text: String): String = decode(text.replace("+", "%2B"))

    private fun decode(text: String): String = try {
        URLDecoder.decode(text, "UTF-8")
    } catch (error: IllegalArgumentException) {
        text
    }

    /** Ham HTTP isteği: yöntem, yol ve gövde. */
    internal fun readRequest(input: InputStream): Triple<String, String, String> {
        val received = ByteArrayOutputStream()
        val buffer = ByteArray(16384)
        var headerEnd: Int
        while (true) {
            headerEnd = indexOfHeaderEnd(received.toByteArray())
            if (headerEnd >= 0) break
            val n = input.read(buffer)
            if (n <= 0 || received.size() > 1024 * 1024) return Triple("", "", "")
            received.write(buffer, 0, n)
        }
        val bytes = received.toByteArray()
        val head = String(bytes, 0, headerEnd, Charsets.US_ASCII)
        val lines = head.split("\r\n")
        val request = lines[0].split(' ')
        val length = lines.firstOrNull { it.startsWith("Content-Length:", ignoreCase = true) }
            ?.substring(15)?.trim()?.toIntOrNull() ?: 0
        val body = ByteArrayOutputStream()
        body.write(bytes, headerEnd + 4, bytes.size - headerEnd - 4)
        while (body.size() < length) {
            val n = input.read(buffer)
            if (n <= 0) break
            body.write(buffer, 0, n)
        }
        return Triple(request.getOrElse(0) { "" }, request.getOrElse(1) { "" }, String(body.toByteArray(), Charsets.UTF_8))
    }

    private fun indexOfHeaderEnd(bytes: ByteArray): Int {
        for (i in 0 until bytes.size - 3)
            if (bytes[i] == '\r'.code.toByte() && bytes[i + 1] == '\n'.code.toByte() && bytes[i + 2] == '\r'.code.toByte() && bytes[i + 3] == '\n'.code.toByte()) return i
        return -1
    }

    /**
     * Geri dönüşü bekleyen dinleyici. Yalnız bu telefonun içinden (127.0.0.1) bağlanılır. [await] girişi bekler;
     * [close] beklemeyi bitirir (kullanıcı vazgeçince).
     */
    class Listener : AutoCloseable {
        private val server: ServerSocket = try {
            ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), CALLBACK_PORT))
            }
        } catch (error: IOException) {
            throw SamsungInstallException(SamsungInstallError.LOGIN_FAILED,
                "giriş dönüşü için localhost:$CALLBACK_PORT açılamadı: ${error.message}")
        }

        /** Girişi [timeoutMs] boyunca bekler. */
        fun await(timeoutMs: Long): SamsungAccount {
            val deadline = System.currentTimeMillis() + timeoutMs
            var rejected: String? = null
            try {
                while (true) {
                    val left = deadline - System.currentTimeMillis()
                    if (left <= 0) break
                    server.soTimeout = left.toInt().coerceAtLeast(1)
                    val client = try {
                        server.accept()
                    } catch (error: SocketTimeoutException) {
                        break
                    }
                    client.use { socket ->
                        socket.soTimeout = 10_000
                        val (method, path, body) = try {
                            readRequest(socket.getInputStream())
                        } catch (error: IOException) {
                            Triple("", "", "")
                        }
                        val isCallback = method == "POST" && path.startsWith(CALLBACK_PATH)
                        val account = if (isCallback) parseCallback(body) else null
                        if (isCallback && account == null) rejected = callbackProblem(body)
                        runCatching { respond(socket.getOutputStream(), if (account != null) 200 else if (isCallback) 400 else 404, account != null) }
                        if (account != null) return account
                    }
                }
            } catch (error: SocketException) {
                // close() ile vazgeçildi.
                throw SamsungInstallException(SamsungInstallError.LOGIN_FAILED, "giriş iptal edildi")
            } finally {
                close()
            }
            throw SamsungInstallException(SamsungInstallError.LOGIN_FAILED,
                "giriş ${timeoutMs / 60000} dakika içinde tamamlanmadı" +
                    (rejected?.let { "; Samsung'un geri dönüşünde hesap bilgisi yoktu ($it)" } ?: ""))
        }

        override fun close() {
            runCatching { server.close() }
        }

        private fun respond(output: java.io.OutputStream, status: Int, signedIn: Boolean) {
            val page = if (signedIn) "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>CouchSubs</title>" +
                "<body style=\"font-family:system-ui;padding:2em\"><h2>Giriş tamam / Signed in</h2>" +
                "<p>CouchSubs'a dönebilirsiniz.<br>You can return to CouchSubs.</p>"
            else "Not found"
            val reason = when (status) { 200 -> "OK"; 400 -> "Bad Request"; else -> "Not Found" }
            val body = page.toByteArray(Charsets.UTF_8)
            output.write(("HTTP/1.1 $status $reason\r\nContent-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: ${body.size}\r\nConnection: close\r\n\r\n").toByteArray(Charsets.US_ASCII))
            output.write(body)
            output.flush()
        }
    }
}
