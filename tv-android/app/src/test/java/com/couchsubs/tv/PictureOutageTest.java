// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PictureOutageTest {
    @Test
    public void kisaKesintideHicbirSeyYapilmaz() {
        PictureOutage outage = new PictureOutage();
        outage.lost(1_000);
        // PS5 çözünürlük değiştiriyor: birkaç saniye sonra görüntü geri gelir.
        assertFalse(outage.shouldRetune(1_000 + PictureOutage.RETUNE_MS - 1, true));
        outage.available();
        assertFalse(outage.active());
        assertFalse(outage.shouldRetune(60_000, true));
        assertFalse(outage.shouldTell(60_000, true));
        assertEquals(0, outage.retunes());
    }

    @Test
    public void surenKesintideGirisBirKezYenidenAcilirSonraSoylenir() {
        PictureOutage outage = new PictureOutage();
        outage.lost(0);
        assertFalse(outage.shouldTell(PictureOutage.TELL_MS, true));
        assertTrue(outage.shouldRetune(PictureOutage.RETUNE_MS, true));
        // Yeniden açma TvView'den yeni "görüntü yok" bildirimi getirir: saat baştan başlamaz, ikinci kez açılmaz.
        outage.lost(PictureOutage.RETUNE_MS + 100);
        assertFalse(outage.shouldRetune(PictureOutage.RETUNE_MS * 3, true));
        assertFalse(outage.shouldTell(PictureOutage.TELL_MS - 1, true));
        assertTrue(outage.pending());
        assertTrue(outage.shouldTell(PictureOutage.TELL_MS, true));
        assertFalse(outage.shouldTell(PictureOutage.TELL_MS * 10, true));
        assertFalse(outage.shouldRetune(PictureOutage.TELL_MS * 10, true));
        assertFalse(outage.pending());
        assertEquals(1, outage.retunes());
    }

    @Test
    public void giristeCihazYoksaDokunulmaz() {
        PictureOutage outage = new PictureOutage();
        outage.lost(0);
        // PS5 kapandı: sebep TV değil, giriş yeniden açılmaz ve kutu gösterilmez.
        assertFalse(outage.shouldRetune(PictureOutage.RETUNE_MS * 5, false));
        assertFalse(outage.shouldTell(PictureOutage.TELL_MS * 5, false));
        assertEquals(0, outage.retunes());
    }

    @Test
    public void yeniKesintideYenidenDenenir() {
        PictureOutage outage = new PictureOutage();
        outage.lost(0);
        assertTrue(outage.shouldRetune(PictureOutage.RETUNE_MS, true));
        outage.available();
        outage.lost(100_000);
        assertFalse(outage.shouldRetune(100_000 + PictureOutage.RETUNE_MS - 1, true));
        assertTrue(outage.shouldRetune(100_000 + PictureOutage.RETUNE_MS, true));
        assertEquals(2, outage.retunes());
    }

    @Test
    public void arkaPlandaKesintiSayilmaz() {
        PictureOutage outage = new PictureOutage();
        outage.lost(0);
        outage.reset();
        assertFalse(outage.active());
        assertFalse(outage.shouldRetune(PictureOutage.RETUNE_MS * 2, true));
    }
}
