// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * "Arka planda sürdür (Resim içinde resim)": pencere yalnız çeviri sürerken ve ayar açıkken açılır; iki etkinlik de PiP
 * destekler; ayar adı ve açıklaması iPhone'dakiyle aynıdır (platform eşitliği).
 */
class BackgroundPipTest {
    private fun file(vararg candidates: String): File =
        candidates.flatMap { listOf(it, "couchsubs-android/$it", "../$it") }.map(::File).first { it.exists() }

    @Test
    fun windowOpensOnlyWhileTranslatingWithSettingOn() {
        assertTrue(BackgroundPip.eligible(running = true, enabled = true, supported = true))
        assertFalse(BackgroundPip.eligible(running = false, enabled = true, supported = true))
        assertFalse(BackgroundPip.eligible(running = true, enabled = false, supported = true))
        assertFalse(BackgroundPip.eligible(running = true, enabled = true, supported = false))
    }

    @Test
    fun bothActivitiesSupportPictureInPicture() {
        val manifest = file("app/src/main/AndroidManifest.xml", "src/main/AndroidManifest.xml").readText()
        assertEquals(2, Regex("android:supportsPictureInPicture=\"true\"").findAll(manifest).count())
        // Çeviri hizmeti ağdaki konsol ve TV ile konuşur: Android 14+ türü connectedDevice (Play beyanı bununla yapıldı).
        assertTrue(manifest.contains("android:foregroundServiceType=\"connectedDevice\""))
    }

    @Test
    fun settingTextMatchesIPhone() {
        val english = file("app/src/main/res/values-en/strings.xml", "src/main/res/values-en/strings.xml").readText()
        val turkish = file("app/src/main/res/values/strings.xml", "src/main/res/values/strings.xml").readText()
        val catalog = file("../mac/CouchSubs/Resources/Localizable.xcstrings", "mac/CouchSubs/Resources/Localizable.xcstrings").readText()
        for (strings in listOf(english, turkish)) for (name in listOf("settings_background_pip", "settings_background_pip_short")) {
            val text = Regex("<string name=\"$name\">([^<]*)</string>").find(strings)!!.groupValues[1]
            assertTrue("$name iPhone'da yok: $text", catalog.contains("\"$text\""))
        }
    }
}
