// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

/**
 * Uygulama içinde görüntü bir kez geldikten sonra kesilirse ne yapılacağı (#643: Philips'te oyun sırasında HDMI siyah
 * kalıyor).
 *
 * FallbackWatch yalnız görüntünün hiç gelmediği durumu izler; görüntü geldikten sonra kesilince eskiden hiçbir şey
 * yapılmıyor, ekran siyah kalıyordu. Artık kesinti RETUNE_MS sürerse ve girişte cihaz görünüyorsa giriş bir kez bırakılıp
 * yeniden açılır; yine gelmezse TELL_MS'te kullanıcıya giriş seçici ve Katman önerisi gösterilir. Her kesintide en çok
 * bir yeniden açma ve bir bildirim olur: döngüye girilmez. Girişte cihaz yoksa (PS5 kapandı) hiçbir şey yapılmaz.
 * Çözünürlük ya da HDR değişirken gelen birkaç saniyelik "ayarlanıyor" kesintisi RETUNE_MS'ten kısadır.
 *
 * Android'e bağlı değildir; zaman dışarıdan verilir (bkz. PictureOutageTest).
 */
final class PictureOutage {
    static final long RETUNE_MS = 8_000;
    static final long TELL_MS = 20_000;

    /** Kesintinin başlangıcı; -1: kesinti yok. */
    private long since = -1;
    private boolean retuned;
    private boolean told;
    /** Uygulama açıldığından beri yeniden açma sayısı (bilgi paneli için). */
    private int retunes;

    /** Görüntü kesildi (TvView "görüntü yok" ya da "bağlantı koptu" bildirdi). Süren kesintide saat yeniden başlamaz. */
    void lost(long now) {
        if (since < 0) {
            since = now;
            retuned = false;
            told = false;
        }
    }

    /** Görüntü geldi: kesinti bitti. */
    void available() {
        since = -1;
    }

    /** Ekran arka plana geçti ya da başka giriş seçildi: kesinti sayılmaz, öne gelince baştan başlar. */
    void reset() {
        since = -1;
    }

    boolean active() { return since >= 0; }

    /** Giriş şimdi bırakılıp yeniden açılsın mı; her kesintide en çok bir kez true döner. */
    boolean shouldRetune(long now, boolean sourceConnected) {
        if (since < 0 || retuned || !sourceConnected || now - since < RETUNE_MS) return false;
        retuned = true;
        retunes++;
        return true;
    }

    /** Yeniden açma da işe yaramadı: kullanıcıya söylensin mi; her kesintide en çok bir kez true döner. */
    boolean shouldTell(long now, boolean sourceConnected) {
        if (since < 0 || told || !retuned || !sourceConnected || now - since < TELL_MS) return false;
        told = true;
        return true;
    }

    /** İzlemeye gerek kaldı mı: kesinti sürüyor ve yapılacak bir şey var. */
    boolean pending() { return since >= 0 && !told; }

    int retunes() { return retunes; }
}
