// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import java.util.Locale;

/**
 * Görüntü modu: HDMI CouchSubs'ın içinde mi gösterilir, yoksa TV kendi giriş ekranında gösterir ve altyazı onun üstündeki
 * şeffaf pencerede mi durur ("katman"). Bazı TV'lerde (TCL, Philips ve diğer bazı Android TV / Google TV'ler) uygulamanın
 * içinde HDMI görüntüsü siyah kalıyor; katman modu bunu çözer. Seçim bilgisayardaki/telefondaki Ayarlar › TV'de bölümünden
 * gelir (style olayının displayMode alanı) ya da elle: adb shell am start -n com.couchsubs.tv/.MainActivity --es displayMode overlay
 *
 * Üç tercih var: Otomatik (varsayılan), Uygulama içinde, Katman. Otomatik, izin varsa (bilgisayarın/telefonun kurduğu APK)
 * katmanda açar, yoksa (Play paketi, izin verilmemiş) uygulama içinde. Eskiden varsayılan uygulama içiydi: Philips
 * 55PUS8609 gibi TV'lerde TvView "görüntü geldi" deyip siyah kalıyor, kendiliğinden katmana geçiş (FallbackWatch) bunu
 * göremiyordu; kullanıcı çeviri başlayınca yalnız siyah ekran görüyordu, altyazı yalnız Katman seçilince geliyordu.
 *
 * Kablodaki adlar: "inApp" eski uygulamaların varsayılanıdır ve Otomatik sayılır (kullanıcı seçmediyse de bunu
 * gönderiyorlardı, ayrılamaz); bilerek seçilen uygulama içi "inAppOnly"dir. Eski TV uygulaması "inAppOnly"yi tanımaz,
 * kendi kaydında kalır.
 *
 * Buradaki kararlar Android'e bağlı değildir; JVM birim testleriyle denenir (bkz. DisplayModeTest).
 */
final class DisplayMode {
    /** Varsayılan: katman izni varsa katman, yoksa uygulama içinde. Eski "inApp" de budur. */
    static final String AUTO = "auto";
    /**
     * Bilerek seçilmiş uygulama içi; hiçbir durumda kendiliğinden katmana geçilmez (bkz. mayAutoSwitch). Katmanı yalnız
     * kullanıcı seçer (seçicideki "Katman'a geç" ya da Görüntü modu).
     */
    static final String IN_APP = "inAppOnly";
    /** TV'nin kendi HDMI ekranının üstünde katman. */
    static final String OVERLAY = "overlay";

    /** Uygulama açılırken ne yapılacağı. */
    enum Start {
        IN_APP,
        OVERLAY,
        /** Katman isteniyor ama izin yok: uygulama içinde açılır ve iznin nasıl verileceği gösterilir. */
        IN_APP_NEEDS_PERMISSION,
        /** Katman az önce açılamadı (TV pencereye ya da ön plan servisine izin vermedi): uygulama içinde, nedeniyle. */
        IN_APP_OVERLAY_FAILED
    }

    /** Katman çalışırken CouchSubs yeniden açıldı: ne yapılacağı. */
    enum Relaunch {
        /** Bilgisayar ya da telefon yeni adresle açtı: katman sürer, adres ona iletilir, ekran açılmaz. */
        FORWARD_TO_OVERLAY,
        /** Kullanıcı kumandadan açtı: katman kapanır ve CouchSubs ekranı (panel) açılır. */
        OPEN_APP
    }

    /**
     * Eskiden kumandadan açılınca katman kapanıp uygulama da kapanıyordu: kullanıcı ekranı hiç göremiyor, "uygulamaya
     * giremiyorum, PlayStation ekranına atıyor" diyordu. Artık kullanıcı açtıysa CouchSubs ekranı gelir.
     */
    static Relaunch whileOverlay(String launchParams) {
        return launchParams == null || launchParams.isEmpty() ? Relaunch.OPEN_APP : Relaunch.FORWARD_TO_OVERLAY;
    }

    /**
     * Kullanıcı katmanı kapatıp uygulamayı açtıysa bu açılışta kayıtlı tercih katman olsa da uygulama içinde kalınır;
     * yoksa ekran açılır açılmaz yeniden katmana geçerdi.
     */
    static Start atLaunch(String preference, boolean canDrawOverlays, String overlayFailure, boolean leftOverlay) {
        Start start = atLaunch(preference, canDrawOverlays, overlayFailure);
        return leftOverlay && start == Start.OVERLAY ? Start.IN_APP : start;
    }

    /**
     * CouchSubs ekranı açıkken yeniden açıldı (onNewIntent): kayıtlı tercih katmansa katmana geçilsin mi.
     *
     * Bilgisayarın ya da telefonun adresiyle gelen açılış (launchParams dolu) ekranı hiç değiştirmez, yalnız adres sayfaya
     * iletilir. X'te bildirildi (Android TV 8, 0.9.54, Mac beta.74): Mac TV uygulamasını bağlı görmediği birkaç saniyede
     * adresiyle yeniden açıyordu; kullanıcı katmanı kapatıp CouchSubs'ı kumandadan açmışken bu açılış onu yeniden katmana
     * atıyor, ekran kapanıyordu ("çevirili ekran gelip hemen başka bir ekrana geçiyor, HDMI seçemiyorum"). Kullanıcı
     * katmandan çıktıysa (leftOverlay) kumandadan yeniden açılış da katmana atmaz.
     */
    static boolean switchOnNewIntent(String launchParams, boolean leftOverlay, String preference, boolean canDrawOverlays) {
        if (launchParams != null && !launchParams.isEmpty()) return false;
        if (leftOverlay) return false;
        return wantsOverlay(preference, canDrawOverlays);
    }

    /** Bu tercihle, bu izinle katmana geçilir mi (izin yoksa Otomatik uygulama içinde kalır, Katman izin ister). */
    static boolean wantsOverlay(String preference, boolean canDrawOverlays) {
        String mode = orAuto(preference);
        return canDrawOverlays && (OVERLAY.equals(mode) || AUTO.equals(mode));
    }

    /**
     * Uygulama içindeyken kendiliğinden katmana geçilebilir mi: görüntü 10 sn gelmedi (FallbackWatch), TV HDMI'yı
     * açılıştan hemen sonra kendi oynatıcısına aldı ya da ekranı geri alma hakkı doldu (ScreenReclaim.GIVE_UP).
     *
     * X'te bildirildi (Samsung S25 Ultra ile, TV ekranı aç-kapa yapıyor): kullanıcı katman penceresinde çöken TV'de
     * (EGL_BAD_ALLOC, #1074) bilerek Uygulama içinde seçmişti; görüntü gelmeyince ya da TV HDMI'yı kendine alınca uygulama
     * yine katmana geçiyor, katman çöküyor, uygulama yeniden açılıyordu. Bilerek seçilen uygulama içi artık hiçbir otomatik
     * durumda katmana geçmez; uygulama içinde kalır ve durumu söyler. Otomatik ve Katman eskisi gibi.
     */
    static boolean mayAutoSwitch(String preference, boolean canDrawOverlays) {
        return canDrawOverlays && !IN_APP.equals(orAuto(preference));
    }

    /**
     * Katmana geçilebilecek bir anda (izin var) uygulama içinde yalnız kullanıcının seçimi yüzünden mi kalındı: o zaman
     * durum ekranda söylenir (seçici, geri alma notu).
     */
    static boolean keptInApp(String preference, boolean canDrawOverlays) {
        return canDrawOverlays && IN_APP.equals(orAuto(preference));
    }

    /** Tanınmayan ya da kayıtsız tercih Otomatik'tir. */
    static String orAuto(String preference) {
        String mode = normalize(preference);
        return mode == null ? AUTO : mode;
    }

    /** Katman servisinin uygulamayı geri açarken bildirdiği neden (bkz. OverlayService). */
    static final String FAILED_PERMISSION = "permission";
    static final String FAILED_WINDOW = "window";
    static final String FAILED_FOREGROUND = "foreground";

    private DisplayMode() {}

    /** Bilinen bir mod adıysa onu, değilse null döner (büyük-küçük harf ve "in-app" gibi yazımlar kabul edilir). */
    static String normalize(String value) {
        if (value == null) return null;
        String plain = value.trim().toLowerCase(Locale.ROOT).replace("-", "").replace("_", "");
        if (plain.equals("auto") || plain.equals("inapp")) return AUTO;
        if (plain.equals("inapponly")) return IN_APP;
        if (plain.equals("overlay")) return OVERLAY;
        return null;
    }

    static Start atLaunch(String preference, boolean canDrawOverlays) {
        return atLaunch(preference, canDrawOverlays, null);
    }

    /**
     * overlayFailure: katman servisi uygulamayı "açılamadım" diye geri açtıysa nedeni (FAILED_*), yoksa null. O zaman
     * yeniden katmana geçilmez; yoksa kayıtlı tercih katmansa uygulama ile servis birbirini sonsuza dek açıp kapatırdı ve
     * kullanıcı yalnız uygulamanın kapandığını görürdü (#275).
     */
    static Start atLaunch(String preference, boolean canDrawOverlays, String overlayFailure) {
        if (FAILED_PERMISSION.equals(overlayFailure)) return Start.IN_APP_NEEDS_PERMISSION;
        if (overlayFailure != null) return Start.IN_APP_OVERLAY_FAILED;
        String mode = orAuto(preference);
        if (IN_APP.equals(mode)) return Start.IN_APP;
        // Otomatik: izin yoksa (Play paketi, izin verilmemiş) sessizce uygulama içinde; izin istenmez.
        if (AUTO.equals(mode)) return canDrawOverlays ? Start.OVERLAY : Start.IN_APP;
        return canDrawOverlays ? Start.OVERLAY : Start.IN_APP_NEEDS_PERMISSION;
    }

    /**
     * Bilgisayardan gelen mod kayıtlı olandan farklı mı? Bilgisayar her bağlantıda aynı ayarı yeniden gönderir; yalnız
     * gerçek değişiklik modu değiştirir. Yoksa kendiliğinden katmana geçmiş bir TV, bağlanınca uygulamaya geri dönerdi.
     */
    static boolean isChange(String stored, String incoming) {
        String next = normalize(incoming);
        if (next == null) return false;
        return !next.equals(orAuto(stored));
    }
}
