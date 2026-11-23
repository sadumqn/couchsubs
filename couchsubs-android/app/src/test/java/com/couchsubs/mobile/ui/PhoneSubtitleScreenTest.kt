// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import android.content.pm.ActivityInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File

/**
 * Telefondaki altyazı ekranı (#559): parlaklık kısılmaz (ekran karanlık kalıyordu) ve "Ekranı döndür" yatayla dik
 * arasında geçer (iPhone ile aynı).
 */
class PhoneSubtitleScreenTest {
    @Test
    fun rotateSwitchesBetweenLandscapeAndPortrait() {
        // Açılışta manifestteki sensorLandscape; ilk dokunuş dike, ikincisi yine yataya.
        val first = PhoneSubtitleActivity.nextOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE)
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT, first)
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, PhoneSubtitleActivity.nextOrientation(first))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
            PhoneSubtitleActivity.nextOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED))
    }

    @Test
    fun subtitleScreenDoesNotDimTheScreen() {
        val source = listOf("src/main/java/com/couchsubs/mobile/ui/PhoneSubtitleActivity.kt",
            "app/src/main/java/com/couchsubs/mobile/ui/PhoneSubtitleActivity.kt").map(::File).first { it.exists() }.readText()
        assertFalse(source.contains("screenBrightness"))
    }
}
