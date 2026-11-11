// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import java.util.Locale;

/**
 * Görüntü modu: HDMI CouchSubs'ın içinde mi gösterilir, yoksa TV kendi giriş ekranında gösterir ve altyazı onun üstündeki
 * şeffaf pencerede mi durur ("katman"). Bazı TV'lerde (TCL ve diğer bazı Android TV / Google TV'ler) uygulamanın içinde
 * HDMI görüntüsü siyah kalıyor; katman modu bunu çözer. Seçim bilgisayardaki Ayarlar › TV'de bölümünden gelir
 * (style olayının displayMode alanı) ya da elle: adb shell am start -n com.couchsubs.tv/.MainActivity --es displayMode overlay
 *
 * Buradaki kararlar Android'e bağlı değildir; JVM birim testleriyle denenir (bkz. DisplayModeTest).
 */
final class DisplayMode {
    /** Uygulamanın içinde; görüntü hiç gelmezse kendiliğinden katmana geçilir (bkz. FallbackWatch). Varsayılan. */
    static final String IN_APP = "inApp";
    /** TV'nin kendi HDMI ekranının üstünde katman. */
    static final String OVERLAY = "overlay";

    /** Uygulama açılırken ne yapılacağı. */
    enum Start {
        IN_APP,
        OVERLAY,
        /** Katman isteniyor ama izin yok: uygulama içinde açılır ve iznin nasıl verileceği gösterilir. */
        IN_APP_NEEDS_PERMISSION
    }

    private DisplayMode() {}

    /** Bilinen bir mod adıysa onu, değilse null döner (büyük-küçük harf ve "in-app" gibi yazımlar kabul edilir). */
    static String normalize(String value) {
        if (value == null) return null;
        String plain = value.trim().toLowerCase(Locale.ROOT).replace("-", "").replace("_", "");
        if (plain.equals("inapp")) return IN_APP;
        if (plain.equals("overlay")) return OVERLAY;
        return null;
    }

    static Start atLaunch(String preference, boolean canDrawOverlays) {
        if (!OVERLAY.equals(normalize(preference))) return Start.IN_APP;
        return canDrawOverlays ? Start.OVERLAY : Start.IN_APP_NEEDS_PERMISSION;
    }

    /**
     * Bilgisayardan gelen mod kayıtlı olandan farklı mı? Bilgisayar her bağlantıda aynı ayarı yeniden gönderir; yalnız
     * gerçek değişiklik modu değiştirir. Yoksa kendiliğinden katmana geçmiş bir TV, bağlanınca uygulamaya geri dönerdi.
     */
    static boolean isChange(String stored, String incoming) {
        String next = normalize(incoming);
        if (next == null) return false;
        String current = normalize(stored);
        return !next.equals(current == null ? IN_APP : current);
    }
}
