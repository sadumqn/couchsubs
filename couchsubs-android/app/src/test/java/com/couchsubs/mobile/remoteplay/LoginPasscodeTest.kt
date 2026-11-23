// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** PS5 giriş şifresi: kayıtlıysa ilk istekte gönderilir; yoksa ya da yanlışsa oturum kapanır (Mac/Windows ile aynı). */
class LoginPasscodeTest {
    @Test
    fun onlyFourDigitsAreKept() {
        assertEquals("1234", LoginPasscode.normalized(" 1234 "))
        assertEquals("0007", LoginPasscode.normalized("0007"))
        assertNull(LoginPasscode.normalized(null))
        assertNull(LoginPasscode.normalized(""))
        assertNull(LoginPasscode.normalized("123"))
        assertNull(LoginPasscode.normalized("12345"))
        assertNull(LoginPasscode.normalized("12a4"))
        assertNull(LoginPasscode.normalized("١٢٣٤"))
    }

    @Test
    fun savedPasscodeIsSentAsAsciiOnFirstRequest() {
        val reply = LoginPasscode.reply("1234", incorrect = false)
        assertTrue(reply is LoginPasscode.Reply.Send)
        assertArrayEquals(byteArrayOf(0x31, 0x32, 0x33, 0x34), (reply as LoginPasscode.Reply.Send).pin)
    }

    @Test
    fun missingPasscodeStopsTheSession() {
        assertEquals(LoginPasscode.Reply.Stop(DisconnectKind.LOGIN_PASSCODE), LoginPasscode.reply(null, incorrect = false))
        assertEquals(LoginPasscode.Reply.Stop(DisconnectKind.LOGIN_PASSCODE), LoginPasscode.reply("12", incorrect = false))
    }

    /** PS5 şifreyi yeniden istiyorsa önceki yanlıştı: aynı şifre tekrar gönderilmez. */
    @Test
    fun incorrectPasscodeIsNotResent() {
        assertEquals(LoginPasscode.Reply.Stop(DisconnectKind.LOGIN_PASSCODE_INCORRECT), LoginPasscode.reply("1234", incorrect = true))
    }
}
