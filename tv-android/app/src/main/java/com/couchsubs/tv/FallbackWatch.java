// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

/**
 * Uygulama içindeki HDMI görüntüsünü izler ve katmana kendiliğinden geçme zamanını söyler.
 *
 * Görüntü giriş açıldıktan sonra LIMIT_MS boyunca hiç gelmezse (TvView "görüntü yok", "bağlantı koptu" bildiriyor ya da
 * hiçbir şey bildirmiyor) bu TV HDMI'yı uygulamanın içinde gösteremiyor sayılır. Görüntü bir kez geldiyse TV bunu
 * yapabiliyordur; sonradan kesilmesi (PS5 uykuya geçti, kablo çıktı) katmana geçirmez. Girişte hiçbir cihaz yoksa
 * (PS5 kapalı) da geçilmez: sebep TV değil kaynaktır.
 *
 * Android'e bağlı değildir; zaman dışarıdan verilir (bkz. FallbackWatchTest).
 */
final class FallbackWatch {
    static final long LIMIT_MS = 10_000;

    /** Görüntüsüz geçen sürenin başlangıcı; -1: şu an sorun yok ya da izlenmiyor. */
    private long troubleSince = -1;
    private boolean played;

    /** Giriş açıldı ya da görüntü kayboldu (TvView bildirimi). Saat yalnız ilk sorunda başlar, yeniden denemeler sıfırlamaz. */
    void trouble(long now) {
        if (!played && troubleSince < 0) troubleSince = now;
    }

    /** Görüntü geldi: bu TV uygulama içinde gösterebiliyor. */
    void videoAvailable() {
        played = true;
        troubleSince = -1;
    }

    boolean played() { return played; }

    /** Uygulama arka plana geçti: görüntüsüz süre sayılmaz, öne gelince yeniden başlar. */
    void pause() {
        troubleSince = -1;
    }

    /**
     * @param sourceConnected girişte bir cihaz var mı (bilinmiyorsa true)
     * @param canDrawOverlays katman izni var mı
     */
    boolean shouldSwitch(long now, boolean sourceConnected, boolean canDrawOverlays) {
        return troubleFor(now) && sourceConnected && canDrawOverlays;
    }

    /** Katmana geçilmesi gerekirdi ama izin yok: kullanıcıya iznin nasıl verileceği gösterilmeli. */
    boolean needsPermission(long now, boolean sourceConnected, boolean canDrawOverlays) {
        return troubleFor(now) && sourceConnected && !canDrawOverlays;
    }

    private boolean troubleFor(long now) {
        return !played && troubleSince >= 0 && now - troubleSince >= LIMIT_MS;
    }
}
