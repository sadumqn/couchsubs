// SPDX-License-Identifier: AGPL-3.0-only
// Microsoft girişi ve Xbox jeton zinciri: Windows köprüsünün kullandığı xal-node `Msal` yolunun birebir karşılığı
// (istemci kimliği, uçlar, başlıklar ve gövdeler aynı; xal-node MIT, unknownskl). SISU ve imzalı istek bu yolda yoktur.
package com.couchsubs.mobile.xbox

import org.json.JSONArray
import org.json.JSONObject

/**
 * Jetonlar bellekte tutulur ve süresi dolmadan (60 sn pay) yenilenir; kalıcı olan yalnız kullanıcı jetonudur, her
 * değiştiğinde [onUserToken] çağrılır (çağıran şifreli depoya yazar). İş parçacığı güvenlidir; çağrılar bloklar.
 */
class XboxAuth(
    private val http: XboxHttp = UrlConnectionHttp,
    private val clock: () -> Long = System::currentTimeMillis,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    @Volatile var userToken: XboxUserToken? = null,
    private val onUserToken: (XboxUserToken?) -> Unit = {},
) {
    companion object {
        const val CLIENT_ID = "1f907974-e22b-4810-a9de-d9647380c97e"
        const val SCOPE = "xboxlive.signin openid profile offline_access"
        const val TRANSFER_SCOPE = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
        const val RP_XBOXLIVE = "http://xboxlive.com"
        const val RP_GSSV = "http://gssv.xboxlive.com/"
        private const val MARGIN_S = 60L
        private const val LOGIN = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
        private const val FORM = "application/x-www-form-urlencoded"
        private const val BROWSER_AGENT =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        /** XSTS'nin 401 yanıtındaki XErr: hesabın Xbox profili yok (…233), çocuk hesabı (…238), ülke (…235). */
        private val NO_ACCOUNT_XERR = setOf(2148916233L, 2148916235L, 2148916236L, 2148916237L, 2148916238L)
    }

    private val lock = Any()
    private var xblUser: XboxXstsToken? = null
    private val xsts = HashMap<String, XboxXstsToken>()
    private var home: XboxHomeEndpoint? = null

    val signedIn: Boolean get() = userToken != null

    /** Girişi başlatır: kullanıcıya gösterilecek kod ve adres. */
    fun startDeviceCode(): XboxDeviceCode {
        val response = http.request("POST", "$LOGIN/devicecode", mapOf("Content-Type" to FORM),
            formBody("client_id" to CLIENT_ID, "scope" to SCOPE))
        return XboxDeviceCode.parse(json(response, "Microsoft cihaz kodu"))
    }

    /**
     * Kullanıcı kodu onaylayana kadar bekler (sunucunun aralığıyla). Onaylanınca kullanıcı jetonu kaydedilir.
     * [cancelled] true dönerse [InterruptedException] atılır.
     *
     * Ağ hatası girişi bitirmez: kullanıcı kodu tarayıcıda yazarken uygulama arka plandadır ve Android (pil tasarrufu,
     * veri tasarrufu, Doze) arka plandaki isteği keser. Eskiden tek bir kesik istek girişi "İnternete bağlanılamadı"
     * ile bitiriyordu; kullanıcı onaylayıp döndüğünde giriş takılı kalıyordu. Kodun süresi dolana kadar sorulmaya devam edilir.
     */
    fun pollDeviceCode(code: XboxDeviceCode, cancelled: () -> Boolean = { false }): XboxUserToken {
        val deadline = clock() + code.expiresInSeconds * 1000L
        var interval = code.intervalSeconds * 1000L
        while (true) {
            if (cancelled()) throw InterruptedException("Microsoft girişi iptal edildi")
            val response = try {
                http.request("POST", "$LOGIN/token", mapOf("Content-Type" to FORM),
                    formBody("grant_type" to "urn:ietf:params:oauth:grant-type:device_code", "client_id" to CLIENT_ID, "device_code" to code.deviceCode))
            } catch (error: XboxException) {
                if (error.kind != XboxError.NETWORK || clock() >= deadline) throw error
                sleep(interval)
                continue
            }
            if (response.ok) {
                val token = XboxUserToken.fromResponse(parseObject(response.body), clock())
                synchronized(lock) { reset(); userToken = token }
                onUserToken(token)
                return token
            }
            when (DeviceCodePoll.classify(response)) {
                DeviceCodePoll.PENDING -> Unit
                DeviceCodePoll.SLOW_DOWN -> interval += 5000
                DeviceCodePoll.EXPIRED -> throw XboxException(XboxError.CODE_EXPIRED, "Microsoft kodunun süresi doldu")
                DeviceCodePoll.DECLINED -> throw XboxException(XboxError.SIGN_IN_DECLINED, "Microsoft girişi reddedildi")
                DeviceCodePoll.FAILED -> throw XboxException(XboxError.SERVICE, "Microsoft girişi: HTTP ${response.status} ${response.body.take(200)}")
            }
            if (clock() >= deadline) throw XboxException(XboxError.CODE_EXPIRED, "Microsoft kodunun süresi doldu")
            sleep(interval)
        }
    }

    /** Çıkış: bütün jetonlar silinir. */
    fun signOut() {
        synchronized(lock) { reset(); userToken = null }
        onUserToken(null)
    }

    private fun reset() {
        xblUser = null
        xsts.clear()
        home = null
    }

    /**
     * Ev yayını hizmeti jetonu süresinden önce reddedildi (HTTP 401): bellekteki jetonlar bırakılır, sonraki istek
     * yenilerini alır. Kullanıcı jetonu korunur; eskiden önbellekteki geçersiz jetonla her yeniden deneme 401 alıyor ve
     * "yeniden giriş yapın" deyip duruyordu (iPhone/Mac XboxAuth.invalidateHomeToken ile aynı).
     */
    fun invalidateHomeToken() {
        synchronized(lock) { reset() }
    }

    /** Microsoft erişim jetonu; 60 sn'den az kaldıysa yenilenir (xal-node `getOrRefreshUserToken`). */
    fun userAccessToken(): String { synchronized(lock) {
        val current = userToken ?: throw XboxException(XboxError.SIGN_IN_REQUIRED, "Microsoft girişi gerekiyor")
        if (current.secondsValid(clock()) > MARGIN_S) return current.accessToken
        return refresh(current).accessToken
    } }

    private fun refresh(current: XboxUserToken): XboxUserToken {
        if (current.refreshToken.isEmpty()) throw XboxException(XboxError.SIGN_IN_REQUIRED, "Microsoft girişi gerekiyor")
        val response = http.request("POST", "$LOGIN/token",
            mapOf("Content-Type" to FORM, "Cache-Control" to "no-store, must-revalidate, no-cache"),
            formBody("client_id" to CLIENT_ID, "grant_type" to "refresh_token", "refresh_token" to current.refreshToken, "scope" to SCOPE))
        // 400: yenileme jetonu geçersiz (xal-node TokenRefreshError); kullanıcı yeniden giriş yapmalı.
        if (response.status == 400) throw XboxException(XboxError.SIGN_IN_REQUIRED, "Microsoft girişinin süresi doldu")
        val token = XboxUserToken.fromResponse(json(response, "Microsoft jeton yenileme"), clock(), current)
        userToken = token
        onUserToken(token)
        return token
    }

    /** Xbox Live kullanıcı jetonu (`user.auth.xboxlive.com`, RPS bileti `d=`). */
    private fun xblUserToken(): XboxXstsToken {
        xblUser?.takeIf { it.secondsValid(clock()) > MARGIN_S }?.let { return it }
        val access = userAccessToken()
        val body = JSONObject()
            .put("Properties", JSONObject().put("AuthMethod", "RPS").put("RpsTicket", "d=$access").put("SiteName", "user.auth.xboxlive.com"))
            .put("RelyingParty", "http://auth.xboxlive.com").put("TokenType", "JWT").toString()
        val response = http.request("POST", "https://user.auth.xboxlive.com/user/authenticate", mapOf(
            "x-xbl-contract-version" to "1", "Cache-Control" to "no-cache", "Content-Type" to "application/json",
            "Origin" to "https://www.xbox.com", "Referer" to "https://www.xbox.com/"), body)
        if (response.status == 401) throw XboxException(XboxError.SIGN_IN_REQUIRED, "Xbox Live girişi kabul etmedi")
        return XboxXstsToken.parse(json(response, "Xbox Live kullanıcı jetonu")).also { xblUser = it }
    }

    /** XSTS jetonu: [relyingParty] `http://xboxlive.com` (konsol listesi) ya da `http://gssv.xboxlive.com/` (yayın). */
    fun xsts(relyingParty: String): XboxXstsToken { synchronized(lock) {
        xsts[relyingParty]?.takeIf { it.secondsValid(clock()) > MARGIN_S }?.let { return it }
        val user = xblUserToken()
        val body = JSONObject()
            .put("Properties", JSONObject().put("SandboxId", "RETAIL").put("UserTokens", JSONArray().put(user.token)))
            .put("RelyingParty", relyingParty).put("TokenType", "JWT").toString()
        val response = http.request("POST", "https://xsts.auth.xboxlive.com/xsts/authorize", mapOf(
            "x-xbl-contract-version" to "1", "Cache-Control" to "no-cache", "Content-Type" to "application/json",
            "Origin" to "https://www.xbox.com", "Referer" to "https://www.xbox.com/", "Accept" to "*/*", "ms-cv" to "0",
            "User-Agent" to BROWSER_AGENT), body)
        if (response.status == 401) {
            val xerr = try { JSONObject(response.body).optLong("XErr") } catch (error: Exception) { 0L }
            if (xerr in NO_ACCOUNT_XERR) throw XboxException(XboxError.NO_XBOX_ACCOUNT, "Bu Microsoft hesabının Xbox profili yok (XErr $xerr)")
            throw XboxException(XboxError.SIGN_IN_REQUIRED, "Xbox yetkisi verilmedi (XErr $xerr)")
        }
        return XboxXstsToken.parse(json(response, "XSTS")).also { xsts[relyingParty] = it }
    } }

    /** Ev yayını adresi ve jetonu: gssv XSTS → `xhome.gssv-play-prod.xboxlive.com/v2/login/user`. */
    fun homeEndpoint(): XboxHomeEndpoint { synchronized(lock) {
        home?.takeIf { it.expiresAtMs > clock() + MARGIN_S * 1000 }?.let { return it }
        val gssv = xsts(RP_GSSV)
        val body = JSONObject().put("token", gssv.token).put("offeringId", "xhome").toString()
        val response = http.request("POST", "https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", mapOf(
            "Content-Type" to "application/json", "Cache-Control" to "no-store, must-revalidate, no-cache",
            "x-gssv-client" to "XboxComBrowser"), body)
        return XboxHomeEndpoint.parse(json(response, "Xbox ev yayını girişi"), clock()).also { home = it }
    } }

    /** Konsola aktarım jetonu (`connect` için; xal-node `getMsalToken().lpt`). */
    fun transferToken(): String {
        userAccessToken()
        val refresh = userToken?.refreshToken ?: throw XboxException(XboxError.SIGN_IN_REQUIRED, "Microsoft girişi gerekiyor")
        val response = http.request("POST", "https://login.live.com/oauth20_token.srf", mapOf("Content-Type" to FORM),
            formBody("client_id" to CLIENT_ID, "scope" to TRANSFER_SCOPE, "grant_type" to "refresh_token", "refresh_token" to refresh))
        if (response.status == 400) throw XboxException(XboxError.SIGN_IN_REQUIRED, "Microsoft girişinin süresi doldu")
        return json(response, "Konsol aktarım jetonu").optString("access_token").takeIf { it.isNotEmpty() }
            ?: throw XboxException(XboxError.SERVICE, "Konsol aktarım jetonu gelmedi")
    }

    private fun json(response: XboxHttpResponse, what: String): JSONObject {
        if (!response.ok) throw XboxException(XboxError.SERVICE, "$what: HTTP ${response.status} ${response.body.take(300)}")
        return parseObject(response.body)
    }
}

internal fun parseObject(text: String): JSONObject = try {
    if (text.isBlank()) JSONObject() else JSONObject(text)
} catch (error: Exception) {
    throw XboxException(XboxError.SERVICE, "Xbox yanıtı okunamadı", error)
}

/** Cihaz kodu beklerken gelen hata yanıtının anlamı (OAuth 2.0 cihaz akışı, RFC 8628). */
enum class DeviceCodePoll {
    PENDING, SLOW_DOWN, EXPIRED, DECLINED, FAILED;

    companion object {
        fun classify(response: XboxHttpResponse): DeviceCodePoll {
            val error = try { JSONObject(response.body).optString("error") } catch (e: Exception) { "" }
            return when (error) {
                "authorization_pending" -> PENDING
                "slow_down" -> SLOW_DOWN
                "expired_token", "code_expired" -> EXPIRED
                "authorization_declined", "access_denied" -> DECLINED
                else -> if (response.status >= 500) PENDING else FAILED
            }
        }
    }
}
