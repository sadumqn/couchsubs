// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.xbox

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class XboxHttpResponse(val status: Int, val body: String) {
    val ok: Boolean get() = status in 200..299
}

/** Xbox ve Microsoft uçlarına HTTPS isteği (testlerde sahtesi verilir). */
fun interface XboxHttp {
    /** Bloklar; ağ hatasında [XboxException] (NETWORK) atar. */
    fun request(method: String, url: String, headers: Map<String, String>, body: String?): XboxHttpResponse
}

object UrlConnectionHttp : XboxHttp {
    override fun request(method: String, url: String, headers: Map<String, String>, body: String?): XboxHttpResponse {
        val connection = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (error: IOException) {
            throw XboxException(XboxError.NETWORK, "Bağlantı açılamadı: ${error.message}", error)
        }
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.useCaches = false
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty()
            return XboxHttpResponse(status, text)
        } catch (error: IOException) {
            throw XboxException(XboxError.NETWORK, "Xbox hizmetine ulaşılamadı: ${error.message}", error)
        } finally {
            connection.disconnect()
        }
    }
}

internal fun formBody(vararg pairs: Pair<String, String>): String =
    pairs.joinToString("&") { (k, v) -> java.net.URLEncoder.encode(k, "UTF-8") + "=" + java.net.URLEncoder.encode(v, "UTF-8") }
