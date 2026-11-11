// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Masaüstünün kurduğu APK'da katman modu açıktır (siyah ekran sorunu olan TV'ler için). */
public class SideloadFlavorTest {
    @Test
    public void overlayModeIsOn() {
        assertTrue(BuildConfig.OVERLAY_MODE);
    }
}
