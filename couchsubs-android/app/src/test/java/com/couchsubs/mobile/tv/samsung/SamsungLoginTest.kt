// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.concurrent.thread

/** Samsung girişinin geri dönüşü (masaüstündeki SamsungTests ile aynı örnekler). */
class SamsungLoginTest {
    private val state = "accountcheckdogeneratedstatetext"

    @Test
    fun callbackCarriesTokenUserAndEmail() {
        val json = """{"access_token":"tok","userId":"u1","inputEmailID":"a@b.c"}"""
        val body = "code=${URLEncoder.encode(json, "UTF-8").replace("+", "%20")}&state=$state"
        assertEquals(SamsungAccount("tok", "u1", "a@b.c"), SamsungLogin.parseCallback(body))
    }

    @Test
    fun plusInTheTokenIsKept() {
        // Masaüstü Uri.UnescapeDataString kullanır: '+' boşluğa çevrilmez.
        val body = "code=%7B%22access_token%22%3A%22a+b%22%2C%22userId%22%3A%22u%22%7D&state=$state"
        assertEquals("a+b", SamsungLogin.parseCallback(body)?.accessToken)
    }

    @Test
    fun wrongStateOrBrokenJsonIsRejected() {
        val json = """{"access_token":"tok","userId":"u1"}"""
        assertNull(SamsungLogin.parseCallback("code=$json&state=baska"))
        assertNull(SamsungLogin.parseCallback("state=$state&code=bozuk"))
        assertNull(SamsungLogin.parseCallback("state=$state&code=${URLEncoder.encode("""{"userId":"u1"}""", "UTF-8")}"))
        assertEquals("", SamsungLogin.parseCallback("code=${URLEncoder.encode(json, "UTF-8")}&state=$state")?.email)
    }

    @Test
    fun problemNamesFieldsButNotTheToken() {
        val problem = SamsungLogin.callbackProblem("code=gizli&state=$state&error=access_denied&error_description=User+cancelled")
        assertEquals("code, state=$state, error=access_denied, error_description=User cancelled", problem)
    }

    @Test
    fun authorizeUrlPointsBackToThePhone() {
        val url = SamsungLogin.authorizeUrl
        assertTrue(url.startsWith("https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?"))
        assertTrue(url.contains("redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback"))
        assertTrue(url.contains("clientId=v285zxnl3h"))
        assertTrue(url.endsWith("&state=$state&tokenType=TOKEN"))
    }

    @Test
    fun requestIsReadWithItsBody() {
        val raw = "POST /signin/callback HTTP/1.1\r\nHost: localhost\r\nContent-Length: 7\r\n\r\ncode=ab"
        val (method, path, body) = SamsungLogin.readRequest(ByteArrayInputStream(raw.toByteArray()))
        assertEquals("POST", method)
        assertEquals("/signin/callback", path)
        assertEquals("code=ab", body)
    }

    @Test
    fun listenerReturnsTheAccountPostedByTheBrowser() {
        val listener = SamsungLogin.Listener()
        var status = 0
        var stray = 0
        val browser = thread {
            // Önce başka bir istek (ör. favicon), sonra Samsung'un POST'u.
            stray = (URL("http://127.0.0.1:${SamsungLogin.CALLBACK_PORT}/favicon.ico").openConnection() as HttpURLConnection).responseCode
            val connection = URL("http://127.0.0.1:${SamsungLogin.CALLBACK_PORT}${SamsungLogin.CALLBACK_PATH}").openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            val json = """{"access_token":"tok","userId":"u1","inputEmailID":"a@b.c"}"""
            connection.outputStream.use { it.write("code=${URLEncoder.encode(json, "UTF-8")}&state=$state".toByteArray()) }
            status = connection.responseCode
        }
        val account = listener.await(10_000)
        browser.join(5000)
        assertEquals(SamsungAccount("tok", "u1", "a@b.c"), account)
        assertEquals(404, stray)
        assertEquals(200, status)
    }

    @Test
    fun listenerTimesOutWithALoginError() {
        try {
            SamsungLogin.Listener().await(300)
            fail()
        } catch (error: SamsungInstallException) {
            assertEquals(SamsungInstallError.LOGIN_FAILED, error.error)
        }
    }

    @Test
    fun closingTheListenerCancelsTheWait() {
        val listener = SamsungLogin.Listener()
        thread { Thread.sleep(200); listener.close() }
        try {
            listener.await(10_000)
            fail()
        } catch (error: SamsungInstallException) {
            assertEquals(SamsungInstallError.LOGIN_FAILED, error.error)
            assertEquals("giriş iptal edildi", error.detail)
        }
    }
}
