// SPDX-License-Identifier: AGPL-3.0-only
// Xbox konsol listesi ve ev yayını uçları: Windows köprüsündeki (windows/xbox-bridge/bridge.cjs) istekler birebir.
// Protokol sırası Greenlight ve xbox-xcloud-player'dan (MIT, unknownskl; bkz. THIRD-PARTY-NOTICES.md).
package com.couchsubs.mobile.xbox

import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/** ICE adayı (gssv `/ice` biçimi; `candidate` "a=candidate:…" ya da "candidate:…"). */
data class XboxIceCandidate(val candidate: String, val sdpMid: String?, val sdpMLineIndex: Int) {
    fun toJson(): JSONObject = JSONObject().put("candidate", candidate).put("sdpMLineIndex", sdpMLineIndex)
        .put("sdpMid", sdpMid ?: JSONObject.NULL)

    /** libwebrtc'ye verilecek satır: "a=" öneki ve sondaki boşluk atılır; "end-of-candidates" için null. */
    val sdpLine: String?
        get() {
            val line = candidate.trim().removePrefix("a=")
            return line.takeIf { it.startsWith("candidate:") }
        }

    companion object {
        fun parse(o: JSONObject): XboxIceCandidate =
            XboxIceCandidate(o.optString("candidate"), o.optString("sdpMid").takeIf { o.has("sdpMid") && !o.isNull("sdpMid") }, o.optInt("sdpMLineIndex"))
    }
}

/** `/state` yanıtı. */
class XboxSessionStatus(val state: String, val errorDetails: String?)

class XboxHome(
    private val auth: XboxAuth,
    private val http: XboxHttp = UrlConnectionHttp,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
) {
    companion object {
        /** Xbox yalnız tarayıcı/Windows istemcisini kabul ediyor; köprüdeki X-MS-Device-Info birebir. */
        const val DEVICE_INFO = "{\"appInfo\":{\"env\":{\"clientAppId\":\"Microsoft.GamingApp\",\"clientAppType\":\"native\"," +
            "\"clientAppVersion\":\"2203.1001.4.0\",\"clientSdkVersion\":\"8.5.2\",\"httpEnvironment\":\"prod\",\"sdkInstallId\":\"\"}}," +
            "\"dev\":{\"hw\":{\"make\":\"Microsoft\",\"model\":\"Surface Pro\",\"sdktype\":\"native\"}," +
            "\"os\":{\"name\":\"Windows 11\",\"ver\":\"22631.2715\",\"platform\":\"desktop\"}," +
            "\"displayInfo\":{\"dimensions\":{\"widthInPixels\":1920,\"heightInPixels\":1080},\"pixelDensity\":{\"dpiX\":1,\"dpiY\":1}}}}"
        /**
         * SDP/ICE yanıtı ilk 5 sn 250 ms'de bir, sonra saniyede bir, toplam 30 sn sorulur. Eskiden 7,5 sn'de bırakılıyordu:
         * Wi-Fi'daki Xbox yanıtı geç verince oturum Xbox'ta "uzaktan oynatma başladı"dan birkaç saniye sonra kapanıyordu.
         */
        const val EXCHANGE_FAST_ATTEMPTS = 20
        const val EXCHANGE_INTERVAL_MS = 250L
        const val EXCHANGE_SLOW_INTERVAL_MS = 1000L
        const val EXCHANGE_ATTEMPTS = EXCHANGE_FAST_ATTEMPTS + 25

        fun exchangeDelayMs(attempt: Int): Long = if (attempt < EXCHANGE_FAST_ATTEMPTS) EXCHANGE_INTERVAL_MS else EXCHANGE_SLOW_INTERVAL_MS

        /** Oturum kapatma (DELETE) denemeleri arasındaki bekleme (ilki hemen; iPhone/Mac XboxSessionClose ile aynı). */
        val CLOSE_DELAYS_MS = listOf(0L, 1000L, 2000L)

        /** `/play` gövdesi (köprüdeki `start`). */
        fun playBody(consoleId: String, timezoneOffsetMinutes: Int): JSONObject = JSONObject()
            .put("clientSessionId", "").put("titleId", "").put("systemUpdateGroup", "").put("serverId", consoleId)
            .put("fallbackRegionNames", JSONArray())
            .put("settings", JSONObject().put("nanoVersion", "V3;WebrtcTransport.dll").put("enableOptionalDataCollection", false)
                .put("enableTextToSpeech", false).put("highContrast", 0).put("locale", "en-US").put("useIceConnection", false)
                .put("timezoneOffsetMinutes", timezoneOffsetMinutes).put("sdkType", "web").put("osName", "windows"))

        /** `/sdp` teklif gövdesi (kanal sürümleri ve sohbet sesi biçimi köprüdeki gibi). */
        fun sdpBody(sdp: String): JSONObject = JSONObject().put("messageType", "offer").put("sdp", sdp)
            .put("configuration", JSONObject()
                .put("chatConfiguration", JSONObject().put("bytesPerSample", 2).put("expectedClipDurationMs", 20)
                    .put("format", JSONObject().put("codec", "opus").put("container", "webm")).put("numChannels", 1).put("sampleFrequencyHz", 24000))
                .put("chat", range(1, 1)).put("control", range(1, 3)).put("input", range(1, 8)).put("message", range(1, 1)))

        private fun range(min: Int, max: Int) = JSONObject().put("minVersion", min).put("maxVersion", max)

        /** `sessionPath` ("v5/sessions/home/<id>") son parçası. */
        fun sessionId(playResponse: JSONObject): String? =
            playResponse.optString("sessionPath").split('/').lastOrNull()?.takeIf { it.isNotBlank() }

        /** Köprüdeki gibi: "2001" ile başlayan adresten Teredo'nun IPv4 adayları (9002 ve Teredo bağlantı noktası) öne eklenir. */
        fun expandCandidates(candidates: List<XboxIceCandidate>): List<XboxIceCandidate> {
            val expanded = ArrayList<XboxIceCandidate>()
            for (item in candidates) {
                val address = item.candidate.split(' ').getOrNull(4)
                if (address != null && address.startsWith("2001")) {
                    Teredo.inspect(address)?.let { teredo ->
                        for (port in listOf(9002, teredo.udpPort))
                            expanded += item.copy(candidate = "a=candidate:10 1 UDP 1 ${teredo.client4} $port typ host ")
                    }
                }
                expanded += item
            }
            return expanded
        }

        fun timezoneOffsetMinutes(nowMs: Long = System.currentTimeMillis()): Int = TimeZone.getDefault().getOffset(nowMs) / 60_000
    }

    /** Hesaptaki konsollar (xbox-webapi smartglass `getConsolesList`). */
    fun consoles(): List<XboxConsole> {
        val token = auth.xsts(XboxAuth.RP_XBOXLIVE)
        val response = http.request("GET", "https://xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true", mapOf(
            "Accept-Language" to "en-US", "Accept" to "application/json", "x-xbl-contract-version" to "4",
            "Content-Type" to "application/json", "skillplatform" to "RemoteManagement",
            "Authorization" to "XBL3.0 x=${token.userHash};${token.token}"), null)
        if (!response.ok) throw XboxException(XboxError.SERVICE, "Xbox listesi: HTTP ${response.status} ${response.body.take(300)}")
        return XboxConsole.parseList(parseObject(response.body))
    }

    /** gssv isteği (köprüdeki `api`): 204 ya da boş gövde null. */
    fun api(path: String, method: String = "GET", data: JSONObject? = null): JSONObject? {
        var response = send(path, method, data)
        // Hizmet jetonu süresinden önce reddedildi: jeton bir kez yenilenip istek yinelenir.
        if (response.status == 401) {
            auth.invalidateHomeToken()
            response = send(path, method, data)
        }
        if (!response.ok) throw serviceError(response)
        if (response.status == 204 || response.body.isBlank()) return null
        return parseObject(response.body)
    }

    private fun send(path: String, method: String, data: JSONObject?): XboxHttpResponse {
        val endpoint = auth.homeEndpoint()
        return http.request(method, endpoint.baseUrl + path, mapOf(
            "Accept" to "application/json", "Content-Type" to "application/json",
            "Authorization" to "Bearer ${endpoint.token}", "X-Gssv-Client" to "XboxComBrowser",
            "X-MS-Device-Info" to DEVICE_INFO), data?.toString())
    }

    private fun serviceError(response: XboxHttpResponse): XboxException {
        val detail = response.body.take(500)
        val kind = when {
            response.status == 401 || response.status == 403 -> XboxError.SIGN_IN_REQUIRED
            detail.contains("InUse", ignoreCase = true) || detail.contains("Busy", ignoreCase = true) -> XboxError.BUSY
            response.status == 404 || detail.contains("NotFound", ignoreCase = true) || detail.contains("Offline", ignoreCase = true) -> XboxError.CONSOLE_UNAVAILABLE
            else -> XboxError.SERVICE
        }
        return XboxException(kind, "Xbox service HTTP ${response.status}: $detail")
    }

    fun play(consoleId: String): String {
        val result = api("/v5/sessions/home/play", "POST", playBody(consoleId, timezoneOffsetMinutes()))
        return result?.let(::sessionId) ?: throw XboxException(XboxError.SERVICE, "Xbox did not return a stream session")
    }

    fun state(sessionId: String): XboxSessionStatus {
        val status = api("/v5/sessions/home/$sessionId/state") ?: JSONObject()
        val details = status.opt("errorDetails")?.takeIf { it != JSONObject.NULL }?.toString()
        return XboxSessionStatus(status.optString("state"), details)
    }

    fun connect(sessionId: String) {
        api("/v5/sessions/home/$sessionId/connect", "POST", JSONObject().put("userToken", auth.transferToken()))
    }

    /** POST, sonra yanıt gelene kadar GET (köprüdeki `exchange`). */
    private fun exchange(path: String, payload: JSONObject): String {
        api(path, "POST", payload)
        repeat(EXCHANGE_ATTEMPTS) { attempt ->
            val result = api(path)
            val text = result?.optString("exchangeResponse").orEmpty()
            if (text.isNotEmpty()) return text
            sleep(exchangeDelayMs(attempt))
        }
        throw XboxException(XboxError.TIMEOUT, "Xbox WebRTC exchange timed out (${if (path.endsWith("/ice")) "ICE" else "SDP"}, 30 sn)")
    }

    /** SDP yanıtı (Xbox'ın "answer" SDP'si). */
    fun sdp(sessionId: String, offer: String): String {
        val answer = parseObject(exchange("/v5/sessions/home/$sessionId/sdp", sdpBody(offer)))
        return answer.optString("sdp").takeIf { it.isNotEmpty() }
            ?: throw XboxException(XboxError.SERVICE, "Xbox SDP yanıtı boş: ${answer.toString().take(200)}")
    }

    fun ice(sessionId: String, candidates: List<XboxIceCandidate>): List<XboxIceCandidate> {
        val payload = JSONObject().put("messageType", "iceCandidate").put("candidate", JSONArray().apply { candidates.forEach { put(it.toJson()) } })
        val text = exchange("/v5/sessions/home/$sessionId/ice", payload)
        val array = try { JSONArray(text) } catch (error: Exception) { throw XboxException(XboxError.SERVICE, "Xbox ICE yanıtı okunamadı", error) }
        return expandCandidates((0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(XboxIceCandidate::parse) })
    }

    fun keepalive(sessionId: String) {
        api("/v5/sessions/home/$sessionId/keepalive", "POST", JSONObject())
    }

    fun stop(sessionId: String) {
        api("/v5/sessions/home/$sessionId", "DELETE")
    }

    /**
     * Oturumu kapatır; olmazsa [CLOSE_DELAYS_MS] aralıklarıyla yineler. Oturum Xbox hizmetinde zaten yoksa (404/410)
     * kapanmış sayılır. Dönen değer: kapanmadıysa son hata, kapandıysa null.
     */
    fun close(sessionId: String): String? {
        var last: String? = null
        for (delay in CLOSE_DELAYS_MS) {
            if (delay > 0) sleep(delay)
            try {
                stop(sessionId)
                return null
            } catch (error: InterruptedException) {
                throw error
            } catch (error: Exception) {
                val message = error.message ?: error.javaClass.simpleName
                if (XboxKeepalive.sessionGone(message)) return null
                last = message
            }
        }
        return last ?: "?"
    }
}
