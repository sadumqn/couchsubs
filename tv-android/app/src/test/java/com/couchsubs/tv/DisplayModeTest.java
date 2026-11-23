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
        // "inApp" eski uygulamaların varsayılanıdır: Otomatik sayılır.
        assertEquals(DisplayMode.AUTO, DisplayMode.normalize("inApp"));
        assertEquals(DisplayMode.AUTO, DisplayMode.normalize(" in-app "));
        assertEquals(DisplayMode.AUTO, DisplayMode.normalize("auto"));
        assertEquals(DisplayMode.IN_APP, DisplayMode.normalize("inAppOnly"));
        assertEquals(DisplayMode.OVERLAY, DisplayMode.normalize("OVERLAY"));
        assertNull(DisplayMode.normalize("garbage"));
        assertNull(DisplayMode.normalize(null));
        assertEquals(DisplayMode.AUTO, DisplayMode.orAuto(null));
        assertEquals(DisplayMode.AUTO, DisplayMode.orAuto("garbage"));
    }

    @Test
    public void relaunchFromRemoteOpensTheAppInsteadOfClosing() {
        // Kumandadan açıldı (parametre yok): katman kapanır, CouchSubs ekranı açılır.
        assertEquals(DisplayMode.Relaunch.OPEN_APP, DisplayMode.whileOverlay(""));
        assertEquals(DisplayMode.Relaunch.OPEN_APP, DisplayMode.whileOverlay(null));
        // Bilgisayar yeni adresle açtı: katman sürer.
        assertEquals(DisplayMode.Relaunch.FORWARD_TO_OVERLAY, DisplayMode.whileOverlay("server=http://192.168.1.4:8787"));
    }

    @Test
    public void leavingOverlayStaysInAppEvenIfOverlayIsPreferred() {
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("overlay", true, null, true));
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("overlay", true, null, false));
        // Diğer durumlar değişmez.
        assertEquals(DisplayMode.Start.IN_APP_NEEDS_PERMISSION, DisplayMode.atLaunch("overlay", false, null, true));
        assertEquals(DisplayMode.Start.IN_APP_OVERLAY_FAILED,
                DisplayMode.atLaunch("overlay", true, DisplayMode.FAILED_WINDOW, true));
    }

    @Test
    public void overlayStartsOnlyWithPermission() {
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("overlay", true));
        assertEquals(DisplayMode.Start.IN_APP_NEEDS_PERMISSION, DisplayMode.atLaunch("overlay", false));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("inAppOnly", true));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("inAppOnly", false));
    }

    /**
     * Philips 55PUS8609 (X, 0.9.73): "test yazısı gözüküyor ama çeviriyi açınca siyah ekran"; başka Android TV'lerde de
     * altyazı yalnız Katman seçilince geliyordu. TvView "görüntü geldi" deyip siyah kalınca kendiliğinden katmana geçiş
     * işlemiyordu. Varsayılan artık Otomatik: izin varsa katmanda açılır; Play paketinde (izin yok) sessizce uygulama
     * içinde kalınır, izin istenmez.
     */
    @Test
    public void defaultOpensInOverlayWhenAllowedAndStaysQuietOtherwise() {
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch(null, true));
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("inApp", true));
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("auto", true));
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("garbage", true));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch(null, false));
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch("inApp", false));
        // Kullanıcı katmandan çıktıysa bu açılışta uygulama içinde kalınır; katman açılamadıysa yeniden denenmez.
        assertEquals(DisplayMode.Start.IN_APP, DisplayMode.atLaunch(null, true, null, true));
        assertEquals(DisplayMode.Start.IN_APP_OVERLAY_FAILED, DisplayMode.atLaunch(null, true, DisplayMode.FAILED_WINDOW));
        assertEquals(DisplayMode.Start.IN_APP_NEEDS_PERMISSION,
                DisplayMode.atLaunch(null, true, DisplayMode.FAILED_PERMISSION));
    }

    @Test
    public void wantsOverlayFollowsPreferenceAndPermission() {
        assertTrue(DisplayMode.wantsOverlay(null, true));
        assertTrue(DisplayMode.wantsOverlay("overlay", true));
        assertFalse(DisplayMode.wantsOverlay("inAppOnly", true));
        assertFalse(DisplayMode.wantsOverlay(null, false));
        assertFalse(DisplayMode.wantsOverlay("overlay", false));
    }

    @Test
    public void failedOverlayDoesNotReopenOverlay() {
        // #275: katman açılamayıp uygulamayı geri açtıysa, kayıtlı tercih katman olsa da yeniden katmana geçilmez;
        // yoksa uygulama ile servis birbirini açıp kapatır ve kullanıcı yalnız uygulamanın kapandığını görür.
        assertEquals(DisplayMode.Start.IN_APP_OVERLAY_FAILED,
                DisplayMode.atLaunch("overlay", true, DisplayMode.FAILED_WINDOW));
        assertEquals(DisplayMode.Start.IN_APP_OVERLAY_FAILED,
                DisplayMode.atLaunch("overlay", true, DisplayMode.FAILED_FOREGROUND));
        assertEquals(DisplayMode.Start.IN_APP_OVERLAY_FAILED,
                DisplayMode.atLaunch("inAppOnly", true, DisplayMode.FAILED_WINDOW));
        // İzin geri alındıysa iznin nasıl verileceği gösterilir.
        assertEquals(DisplayMode.Start.IN_APP_NEEDS_PERMISSION,
                DisplayMode.atLaunch("overlay", true, DisplayMode.FAILED_PERMISSION));
        // Neden yoksa eski davranış.
        assertEquals(DisplayMode.Start.OVERLAY, DisplayMode.atLaunch("overlay", true, null));
    }

    @Test
    public void sameModeSentAgainIsNotAChange() {
        // Bilgisayar her bağlantıda ayarı yeniden gönderir; kendiliğinden katmana geçen TV geri dönmemeli.
        assertFalse(DisplayMode.isChange(null, "inApp"));
        assertFalse(DisplayMode.isChange(null, "auto"));
        assertFalse(DisplayMode.isChange("inApp", "inApp"));
        assertFalse(DisplayMode.isChange("auto", "inApp"));
        assertFalse(DisplayMode.isChange("inAppOnly", "inAppOnly"));
        assertFalse(DisplayMode.isChange("overlay", "overlay"));
        assertFalse(DisplayMode.isChange("overlay", null));
        assertFalse(DisplayMode.isChange("overlay", "unknown"));
        assertTrue(DisplayMode.isChange(null, "overlay"));
        assertTrue(DisplayMode.isChange(null, "inAppOnly"));
        assertTrue(DisplayMode.isChange("inAppOnly", "overlay"));
        assertTrue(DisplayMode.isChange("inAppOnly", "inApp"));
        // Katman kullanıcısı: bilgisayar Otomatik'e (eski "inApp") dönünce kayıt Otomatik olur (izin varsa yine katman).
        assertTrue(DisplayMode.isChange("overlay", "inApp"));
    }

    /**
     * 0.9.56, X'te Android TV 8 (çeviri Mac'ten, beta.74): "TV'den uygulamayı açtığımda çevirili ekran gelip hemen başka bir
     * ekrana geçiyor, HDMI seçemiyorum". Mac'in adresiyle gelen yeniden açılış kayıtlı katman tercihine dönüp ekranı
     * kapatıyordu. Adresli açılış ekranı değiştirmez; katmandan çıkan kullanıcı kumandadan açınca da ekranda kalır.
     */
    @Test
    public void reopeningWithTheComputerAddressNeverLeavesTheScreen() {
        String params = "{\"server\":\"http://192.168.1.4:8787\"}";
        assertFalse(DisplayMode.switchOnNewIntent(params, true, "overlay", true));
        assertFalse(DisplayMode.switchOnNewIntent(params, false, "overlay", true));
        assertFalse(DisplayMode.switchOnNewIntent("", true, "overlay", true));
        assertFalse(DisplayMode.switchOnNewIntent(null, true, "overlay", true));
        // Katmana hiç girilmemiş ekranda kumandadan açılış kayıtlı katman tercihine uyar (eski davranış).
        assertTrue(DisplayMode.switchOnNewIntent("", false, "overlay", true));
        assertFalse(DisplayMode.switchOnNewIntent("", false, "overlay", false));
        assertFalse(DisplayMode.switchOnNewIntent("", false, "inAppOnly", true));
        // Otomatik: izin varsa katman tercihi gibi.
        assertTrue(DisplayMode.switchOnNewIntent("", false, "auto", true));
        assertFalse(DisplayMode.switchOnNewIntent("", false, "auto", false));
        assertFalse(DisplayMode.switchOnNewIntent("", true, "auto", true));
    }
}
