// SPDX-License-Identifier: AGPL-3.0-only

package com.couchsubs.mobile.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Ekran yazılarını otomatik çevir" varsayılan kapalı; beta.63'te açık gelen ayar bir kez kapatılır. */
class AutoScreenTextMigrationTest {
    @Test
    fun beta63SettingIsTurnedOffOnceWithANotice() {
        // Açık kaydedilmiş ya da hiç değiştirilmemiş (beta.63'te varsayılan açık) eski kurulum: bilgi gösterilir.
        assertEquals(AutoScreenTextMigration.Step(notice = true), AutoScreenTextMigration.apply(reset = false, stored = true, existing = true))
        assertEquals(AutoScreenTextMigration.Step(notice = true), AutoScreenTextMigration.apply(reset = false, stored = null, existing = true))
        // Kullanıcı zaten kapatmıştı: sessizce işaret konur.
        assertEquals(AutoScreenTextMigration.Step(notice = false), AutoScreenTextMigration.apply(reset = false, stored = false, existing = true))
    }

    @Test
    fun freshInstallIsMigratedSilentlyAndMigrationRunsOnce() {
        assertEquals(AutoScreenTextMigration.Step(notice = false), AutoScreenTextMigration.apply(reset = false, stored = null, existing = false))
        // Göçten sonra kullanıcı açtıysa bir daha kapatılmaz.
        assertNull(AutoScreenTextMigration.apply(reset = true, stored = true, existing = true))
    }

    /**
     * beta.63–68: hazır alanlar varsayılan açıktı; otomatik ekran yazısı kapalıyken de GTA 6'da menü ve bildirimler
     * çevriliyordu. Göç hazır alanları ve GTA 6 telefonunu bir kez kapatır; kullanıcı otomatik ekran yazısını açmışsa
     * dokunmaz; sonra kullanıcının açtığı ayar bir daha kapatılmaz.
     */
    @Test
    fun presetsAndPhoneAreTurnedOffOnceWhenAutoScreenTextIsOff() {
        assertTrue(ScreenTextExtrasMigration.apply(reset = false, autoScreenText = false)!!)
        assertFalse(ScreenTextExtrasMigration.apply(reset = false, autoScreenText = true)!!)
        assertNull(ScreenTextExtrasMigration.apply(reset = true, autoScreenText = false))
        assertNull(ScreenTextExtrasMigration.apply(reset = true, autoScreenText = true))
    }
}
