// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import com.couchsubs.mobile.settings.AppSettings
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.InetAddress
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * LG bekçisinin kararı: TV kendi HDMI ya da yayın girişine geçtiyse CouchSubs TV yeniden öne getirilir (Windows TvKeeper
 * ve Mac/iPhone TVKeeper ile aynı kural). Eskiden Android telefon LG'de uygulamayı yalnız bir kez açıyordu: PS tuşu
 * (HDMI-CEC) TV'yi PS5'in girişine geçirince uygulama arka planda kalıyor, çeviri bir daha TV'ye gelmiyordu (X, Kas 2026).
 *
 * - Kullanıcının açtığı başka uygulamaya (Netflix) dokunulmaz.
 * - TV uygulamasının gösterdiği HDMI girişine geçiş (PS tuşu) ısrar sayılmaz, her seferinde geri getirilir; yalnız bir
 *   dakikada [CONSOLE_LOOP_LIMIT] kez olursa (bitmeyen CEC döngüsü) bekçi çekilir.
 * - Başka HDMI numarası ya da yayın: [STAND_DOWN_WINDOW_MS] içinde [STAND_DOWN_AFTER] kez geri getirildiyse ve TV yine
 *   girişteyse kullanıcı ısrarlıdır, bekçi çekilir. CouchSubs TV'de yeniden önde görülünce bekçi işine döner.
 * - Geri getirdikten sonra [LAUNCH_SETTLE_MS] beklenir: TV uygulamayı öne alırken önplan bir an eski girişi gösterir.
 */
class LgKeeperRule(private val now: () -> Long = { System.currentTimeMillis() }) {
    enum class Action { NONE, LAUNCH }

    var stoodDown = false
        private set
    private val forced = ArrayDeque<Long>()
    private val consoleReturns = ArrayDeque<Long>()
    private var lastForced: Long? = null

    /** Az önce geri getirildi: önplan henüz sorulmaz. */
    fun settling(): Boolean = lastForced?.let { now() - it < LAUNCH_SETTLE_MS } ?: false

    fun decide(current: String, consolePort: Int?): Action {
        val time = now()
        if (current == APP_ID) {
            // Bekçi çekilmişken uygulama öndeyse kullanıcı onu kendisi açmıştır: bekçi işine döner.
            if (stoodDown) reset()
            return Action.NONE
        }
        if (!isInputOrLiveTv(current) || stoodDown) return Action.NONE
        if (isConsoleInput(current, consolePort)) {
            while (consoleReturns.isNotEmpty() && time - consoleReturns.first() > CONSOLE_LOOP_WINDOW_MS) consoleReturns.removeFirst()
            if (consoleReturns.size >= CONSOLE_LOOP_LIMIT) { stoodDown = true; return Action.NONE }
            consoleReturns.addLast(time)
            lastForced = time
            return Action.LAUNCH
        }
        while (forced.isNotEmpty() && time - forced.first() > STAND_DOWN_WINDOW_MS) forced.removeFirst()
        if (forced.size >= STAND_DOWN_AFTER) { stoodDown = true; return Action.NONE }
        forced.addLast(time)
        lastForced = time
        return Action.LAUNCH
    }

    fun reset() {
        stoodDown = false
        forced.clear()
        consoleReturns.clear()
        lastForced = null
    }

    private var reopens = 0
    private var lastReopen: Long? = null
    private var connectedSince: Long? = null

    /**
     * Yeniden kurulan bağlantıda (ya da "Otomatik açmayı dene"/alındı kesintisinde) uygulama açılabilir mi. #1055 (beta.86,
     * LG OLED C4): her yeni bağlantıda, uygulama açık ve bağlıyken de açma komutu gidiyordu; webOS uygulamayı yeniden
     * başlatıp HDMI görüntüsünü yeniden kuruyor, ekran kararıp "HDR" yazısıyla geri geliyordu. Bağlı uygulamaya hiç açma
     * gitmez; bağlı değilse ilk yeniden açma hemen, sonra [REOPEN_BACKOFF_MS] aralığıyla (Mac/iPhone ve Windows ile aynı).
     * true dönerse açma sayılmıştır.
     */
    fun mayReopen(connected: Boolean): Boolean {
        val time = now()
        noteHealth(connected)
        if (connected) return false
        val last = lastReopen
        if (last != null && reopens > 0 && time - last < REOPEN_BACKOFF_MS[minOf(reopens - 1, REOPEN_BACKOFF_MS.size - 1)]) return false
        reopens++
        lastReopen = time
        lastForced = time
        return true
    }

    /** Uygulama [HEALTHY_RESET_MS] boyunca kesintisiz bağlı kaldıysa yeniden açmanın geri çekilmesi sıfırlanır. */
    fun noteHealth(connected: Boolean) {
        val time = now()
        if (!connected) { connectedSince = null; return }
        val since = connectedSince ?: time
        connectedSince = since
        if (time - since >= HEALTHY_RESET_MS) { reopens = 0; lastReopen = null }
    }

    companion object {
        /** Yeniden kurulan bağlantıda iki açma arasındaki en kısa süre: 30 sn, 1, 2, 5 dk (Mac/iPhone ve Windows ile aynı). */
        val REOPEN_BACKOFF_MS = longArrayOf(30_000L, 60_000L, 120_000L, 300_000L)
        const val HEALTHY_RESET_MS = 600_000L
        const val APP_ID = "com.couchsubs.tv"
        const val STAND_DOWN_AFTER = 3
        const val STAND_DOWN_WINDOW_MS = 90_000L
        const val CONSOLE_LOOP_LIMIT = 10
        const val CONSOLE_LOOP_WINDOW_MS = 60_000L
        const val LAUNCH_SETTLE_MS = 2_000L
        /** Önplandaki uygulamanın sorulma aralığı: PS tuşundan sonra en geç ~2 sn'de geri gelinsin. */
        const val FOREGROUND_POLL_MS = 1_000L
        /** Bağlantı kurulamazsa (TV kapalı) yeniden deneme aralığı. */
        const val RECONNECT_MS = 5_000L

        fun isInputOrLiveTv(appId: String) =
            appId.startsWith("com.webos.app.hdmi") || appId.startsWith("com.webos.app.externalinput") || appId == "com.webos.app.livetv"

        fun isConsoleInput(appId: String, port: Int?) = port != null && port in 1..4 && appId == "com.webos.app.hdmi$port"
    }
}

/** Bekçinin TV ile konuştuğu bağlantı (testlerde sahtesi verilir). */
interface LgControl {
    fun foregroundAppId(): String
    fun launch()
    fun close()
}

object LgKeeper {
    /**
     * Çeviri sürdükçe CouchSubs TV'yi LG'de önde tutar. [open] bağlanır (olmazsa null); ilk bağlantıda uygulama yeni
     * açılmış olduğundan yeniden açılmaz, sonraki bağlantılarda (TV kapanıp açıldı) açılır. Bloklar.
     * [connected]: TV uygulaması telefona bağlı mı. Verilirse açık ve bağlı uygulamaya yeni bağlantıda da "Otomatik açmayı
     * dene"de de açma komutu gitmez; bağlı değilse [LgKeeperRule.mayReopen] aralığıyla açılır (#1055).
     */
    fun keep(open: () -> LgControl?, active: () -> Boolean, consolePort: () -> Int?, rule: LgKeeperRule = LgKeeperRule(),
             sleep: (Long) -> Unit = { Thread.sleep(it) }, log: (String) -> Unit = {},
             onOpenResult: (TvOpenProblem?) -> Unit = {}, retry: () -> Boolean = { false }, connected: (() -> Boolean)? = null) {
        var control: LgControl? = null
        var first = true
        // Yeni bağlantıda ya da istekte açılsın mı: bağlantı bilgisi yoksa eskisi gibi her zaman.
        fun reopen(): Boolean = connected == null || rule.mayReopen(connected())
        try {
            while (active()) {
                if (control == null) {
                    control = try { open() } catch (_: Exception) { null }
                    // Ana ekrandaki satır: TV'ye bağlanılamadı (kapalı, başka ağda ya da saklı izin yok).
                    if (control == null) { onOpenResult(TvOpenProblem.UNREACHABLE); sleep(LgKeeperRule.RECONNECT_MS); continue }
                    onOpenResult(null)
                    if ((!first || retry()) && reopen()) try { control.launch() } catch (_: Exception) { control.close(); control = null }
                    first = false
                    sleep(LgKeeperRule.FOREGROUND_POLL_MS)
                    continue
                }
                connected?.let { rule.noteHealth(it()) }
                // "Otomatik açmayı dene" ya da alındı kesintisi: CouchSubs öne getirilir (bağlı uygulamaya dokunulmaz).
                if (retry() && reopen()) try { control.launch() } catch (_: Exception) { control.close(); control = null; continue }
                if (!rule.settling()) {
                    try {
                        val current = control.foregroundAppId()
                        if (rule.decide(current, consolePort()) == LgKeeperRule.Action.LAUNCH) {
                            log("LG: TV $current girişine geçti; CouchSubs TV öne getiriliyor.")
                            control.launch()
                        }
                    } catch (_: Exception) {
                        control.close()
                        control = null
                    }
                }
                sleep(LgKeeperRule.FOREGROUND_POLL_MS)
            }
        } finally {
            control?.close()
        }
    }

    /**
     * Saklı client-key ve sertifika parmak iziyle SSAP bağlantısı (TV'de izin sorusu çıkmaz; anahtar yoksa bağlanılmaz).
     * Açma komutu [TvSessionLauncher.launchMessage] ile aynıdır.
     */
    fun ssapControl(settings: AppSettings, tv: InstalledTv, remote: InetAddress, server: String, key: String): LgControl? {
        val tokenKey = "tv.control.${tv.brand}.${tv.host}"
        val token = settings.secrets.get(tokenKey) ?: return null
        val pin = settings.secrets.get("$tokenKey.certificate")
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = throw java.security.cert.CertificateException()
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                if (chain.isEmpty()) throw java.security.cert.CertificateException()
                val seen = MessageDigest.getInstance("SHA-256").digest(chain[0].publicKey.encoded).joinToString("") { "%02x".format(it.toInt() and 255) }
                if (pin != null && pin != seen) throw java.security.cert.CertificateException("TV certificate changed")
            }
        }
        val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        val client = OkHttpClient.Builder().connectTimeout(5, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS)
            .dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> =
                    if (hostname == tv.host) listOf(remote) else throw java.net.UnknownHostException(hostname)
            })
            .sslSocketFactory(tls.socketFactory, trust).hostnameVerifier { host, _ -> host == tv.host }.build()
        val host = if (tv.host.contains(':')) "[${tv.host}]" else tv.host
        for (url in listOf("wss://$host:3001", "ws://$host:3000")) {
            val session = SsapSession(client, url, token, TvSessionLauncher.launchMessage(TvBrand.LG, server, key))
            if (session.connect()) return session
            session.release()
        }
        client.dispatcher.executorService.shutdown()
        return null
    }

    private class SsapSession(private val client: OkHttpClient, private val url: String, private val token: String,
                              private val launchMessage: String) : LgControl {
        private val inbox = LinkedBlockingQueue<JSONObject>()
        private var socket: WebSocket? = null
        private var next = 1

        fun connect(): Boolean {
            socket = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send(TvSessionLauncher.registerMessage(token))
                }
                override fun onMessage(webSocket: WebSocket, text: String) {
                    try { inbox.put(JSONObject(text)) } catch (_: Exception) {}
                }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { inbox.put(JSONObject().put("type", "closed")) }
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { inbox.put(JSONObject().put("type", "closed")) }
            })
            // Saklı anahtarla kayıt sorusuz ve hızlıdır; soru çıkarsa (anahtar geçersiz) beklenmez.
            val deadline = System.currentTimeMillis() + 5_000
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) return false
                val message = inbox.poll(left, TimeUnit.MILLISECONDS) ?: return false
                when (message.optString("type")) {
                    "registered" -> return true
                    "error", "closed" -> return false
                }
            }
        }

        private fun request(uri: String): JSONObject {
            val id = "keep_${next++}"
            inbox.clear()
            val sent = socket?.send(JSONObject().put("type", "request").put("id", id).put("uri", uri).toString()) == true
            if (!sent) throw java.io.IOException("SSAP kapalı")
            return awaitReply(id)
        }

        private fun awaitReply(id: String): JSONObject {
            val deadline = System.currentTimeMillis() + 3_000
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) throw java.io.IOException("SSAP yanıt yok")
                val message = inbox.poll(left, TimeUnit.MILLISECONDS) ?: throw java.io.IOException("SSAP yanıt yok")
                if (message.optString("type") == "closed") throw java.io.IOException("SSAP kapandı")
                if (message.optString("id") != id) continue
                if (message.optString("type") == "error") throw java.io.IOException(message.optString("error"))
                return message.optJSONObject("payload") ?: JSONObject()
            }
        }

        override fun foregroundAppId(): String =
            request("ssap://com.webos.applicationManager/getForegroundAppInfo").optString("appId")

        override fun launch() {
            inbox.clear()
            val message = JSONObject(launchMessage).put("id", "keep_${next++}")
            if (socket?.send(message.toString()) != true) throw java.io.IOException("SSAP kapalı")
            val payload = awaitReply(message.getString("id"))
            if (payload.has("returnValue") && !payload.optBoolean("returnValue")) throw java.io.IOException("launch")
        }

        /** Yalnız bu bağlantıyı kapatır; istemci başka adres denemesinde kullanılır. */
        fun release() {
            socket?.close(1000, null)
            socket?.cancel()
            socket = null
        }

        override fun close() {
            release()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
}
