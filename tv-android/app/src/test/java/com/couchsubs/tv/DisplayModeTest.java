// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class DisplayModeTest {
    @Test
    public void knownNamesAreNormalized() {
        assertEquals(DisplayMode.IN_APP, DisplayMode.normalize("inApp"));
        assertEquals(DisplayMode.IN_APP, DisplayMode.normalize(" in-app "));
        assertEquals(DisplayMode.OVERLAY, DisplayMode.normalize("OVERLAY"));
        assertNull(DisplayMode.normalize("auto"));
        assertNull(DisplayMode.normalize(null));
    }

    @Test
    public void overlayStartsOnlyWithPermission() {
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("overlay", true));
        assertEquals(DisplayMode.Start.IN_APP_NEEDS_PERMISSION, DisplayMode.atLaunch("overlay", false));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("inApp", true));
        // Kayıt yok ya da tanınmıyor: uygulama içinde.
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch(null, true));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("garbage", true));
    }

    @Test
    public void sameModeSentAgainIsNotAChange() {
        // Bilgisayar her bağlantıda ayarı yeniden gönderir; kendiliğinden katmana geçen TV geri dönmemeli.
        assertFalse(DisplayMode.isChange(null, "inApp"));
        assertFalse(DisplayMode.isChange("inApp", "inApp"));
        assertFalse(DisplayMode.isChange("overlay", "overlay"));
        assertFalse(DisplayMode.isChange("overlay", null));
        assertFalse(DisplayMode.isChange("overlay", "unknown"));
        assertTrue(DisplayMode.isChange(null, "overlay"));
        assertTrue(DisplayMode.isChange("inApp", "overlay"));
        assertTrue(DisplayMode.isChange("overlay", "inApp"));
    }
}
