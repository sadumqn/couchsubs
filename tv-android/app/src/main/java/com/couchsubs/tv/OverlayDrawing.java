// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

/**
 * Katman penceresi donanımla (GPU) mı, yazılımla (Canvas) mı çizilsin (#1074).
 *
 * Philips 55PUS7503 (Android TV 8.0, TPM171E) HDMI görüntüsü açıkken bindirme penceresi için GPU yüzeyi ayıramıyor:
 * pencerenin ilk çiziminde uygulamanın kendi çizim iş parçacığı "EGL_BAD_ALLOC during rendering" ile duruyor (libhwui,
 * swapBuffers). Bu yerel bir çökmedir, yakalanamaz; uygulamanın tamamı kapanır. Katman yazılımla çizilince çalışıyor.
 * Katmanı her TV'de yazılımla çizmek gereksiz yavaş olur; bu yüzden önce donanımla açılır, çökerse bir sonraki açılışta
 * yazılıma geçilir ve bu TV için saklanır:
 * - Donanımlı pencere açılırken diske "donanım denemesi sürüyor" yazılır.
 * - Pencere HDMI açıkken (giriş açıldıktan INPUT_SETTLE_MS sonra; giriş bilinmiyorsa pencere açıldıktan SETTLE_MS sonra)
 *   bir kez çizilip SURVIVE_MS ayakta kalırsa donanım bu TV'de çalışıyordur, işaret silinir.
 * - Katman düzgün kapanırsa (servis durdu) işaret silinir; yalnız süreç çizim sırasında ölürse kalır.
 * - Açılışta işaret duruyorsa önceki donanım denemesi çökmüştür: yazılıma geçilir ve saklanır.
 * - Sayfanın WebView işlemi donanımlı pencerede çökerse de (aynı kökten olabilir) sonraki pencere yazılımla kurulur.
 * Yanlış pozitif (süreç denemenin ilk saniyelerinde başka nedenle öldü) yalnız yazılım çizimi demektir, çökme değil.
 *
 * Android'e bağlı değildir; saklama ve zaman dışarıdan verilir (bkz. OverlayDrawingTest).
 */
final class OverlayDrawing {
    /** Kalıcı küçük ayar deposu (SharedPreferences). put diske hemen yazmalı: ardından süreç ölebilir. */
    interface Store {
        boolean get(String key);

        void put(String key, boolean value);
    }

    static final String KEY_SOFTWARE = "overlaySoftware";
    static final String KEY_HARDWARE_TRYING = "overlayHardwareTrying";
    static final long SETTLE_MS = 15_000;
    static final long INPUT_SETTLE_MS = 2_000;
    static final long SURVIVE_MS = 3_000;

    private final Store store;
    private boolean software;
    private String why = "";
    private boolean trying;
    private long shownAt;
    private long inputAt;

    OverlayDrawing(Store store) {
        this.store = store;
        software = store.get(KEY_SOFTWARE);
        if (software) why = "saved";
        if (store.get(KEY_HARDWARE_TRYING)) {
            store.put(KEY_HARDWARE_TRYING, false);
            if (!software) useSoftware("crash");
        }
    }

    /** Pencere yazılımla çizilmeli mi. */
    boolean software() { return software; }

    /** Pencere şimdi ekleniyor. Donanımlıysa deneme diske yazılır. */
    void windowShown(long now) {
        shownAt = now;
        inputAt = 0;
        if (software) return;
        trying = true;
        store.put(KEY_HARDWARE_TRYING, true);
    }

    /** TV konsolun HDMI girişine geçirildi. */
    void inputOpened(long now) { inputAt = now; }

    /** Pencere şimdi çiziliyor: bu çizim, donanımın HDMI açıkken çalıştığını gösterebilir mi (SURVIVE_MS sonra survived). */
    boolean proves(long now) {
        if (!trying) return false;
        return inputAt != 0 ? now - inputAt >= INPUT_SETTLE_MS : now - shownAt >= SETTLE_MS;
    }

    /** Kanıt sayılan çizimden SURVIVE_MS sonra süreç ayakta: donanım bu TV'de çalışıyor. */
    void survived() { stopTrying(); }

    /** Katman düzgün kapandı (servis durdu, pencere kaldırıldı). */
    void closed() { stopTrying(); }

    /** Sayfanın WebView işlemi çöktü. Donanımla çiziliyorduysa true: sonraki pencere yazılımla kurulur. */
    boolean rendererCrashed() {
        stopTrying();
        if (software) return false;
        useSoftware("renderer");
        return true;
    }

    /** Bilgi panelinin tanı satırı için. */
    String diagnostics() {
        if (software) return "draw software (" + why + ")";
        return trying ? "draw hw checking" : "draw hw";
    }

    private void useSoftware(String reason) {
        software = true;
        why = reason;
        store.put(KEY_SOFTWARE, true);
    }

    private void stopTrying() {
        if (!trying) return;
        trying = false;
        store.put(KEY_HARDWARE_TRYING, false);
    }
}
