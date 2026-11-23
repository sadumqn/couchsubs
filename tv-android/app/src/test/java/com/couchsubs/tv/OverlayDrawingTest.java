// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** #1074: katman penceresi donanımla çizilirken süreç çökerse (EGL_BAD_ALLOC) sonraki açılış yazılımla çizer. */
public class OverlayDrawingTest {
    /** SharedPreferences yerine; süreç ölünce de kalan disk. */
    private static final class Disk implements OverlayDrawing.Store {
        final Map<String, Boolean> values = new HashMap<>();

        @Override
        public boolean get(String key) { return Boolean.TRUE.equals(values.get(key)); }

        @Override
        public void put(String key, boolean value) { values.put(key, value); }
    }

    @Test
    public void firstWindowDrawsWithHardware() {
        OverlayDrawing drawing = new OverlayDrawing(new Disk());
        assertFalse(drawing.software());
        assertEquals("draw hw", drawing.diagnostics());
    }

    @Test
    public void crashWhileDrawingWithHardwareSwitchesToSoftwareForGood() {
        Disk disk = new Disk();
        OverlayDrawing first = new OverlayDrawing(disk);
        first.windowShown(1_000);
        first.inputOpened(1_500);
        // Philips 55PUS7503: HDMI açıkken ilk çizimde süreç ölür; survived/closed hiç çağrılmaz.
        assertTrue(first.proves(4_000));

        OverlayDrawing next = new OverlayDrawing(disk);
        assertTrue(next.software());
        assertEquals("draw software (crash)", next.diagnostics());
        next.windowShown(50_000);
        assertFalse("yazılımlı pencere deneme sayılmaz", next.proves(80_000));
        next.closed();

        OverlayDrawing later = new OverlayDrawing(disk);
        assertTrue("bu TV için saklandı", later.software());
        assertEquals("draw software (saved)", later.diagnostics());
    }

    @Test
    public void hardwareThatSurvivesWithHdmiOpenStaysHardware() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        assertEquals("draw hw checking", drawing.diagnostics());
        // HDMI açılmadan önceki çizim kanıt değil.
        assertFalse(drawing.proves(1_200));
        drawing.inputOpened(2_000);
        assertFalse("giriş yeni açıldı", drawing.proves(3_000));
        assertTrue(drawing.proves(2_000 + OverlayDrawing.INPUT_SETTLE_MS));
        drawing.survived();
        assertFalse(drawing.proves(60_000));
        assertEquals("draw hw", drawing.diagnostics());

        // Süreç sonra başka nedenle ölse de (TV kapandı) yazılıma geçilmez.
        assertFalse(new OverlayDrawing(disk).software());
    }

    @Test
    public void withoutKnownInputADrawAfterTheSettleTimeProves() {
        OverlayDrawing drawing = new OverlayDrawing(new Disk());
        drawing.windowShown(1_000);
        assertFalse(drawing.proves(1_000 + OverlayDrawing.SETTLE_MS - 1));
        assertTrue(drawing.proves(1_000 + OverlayDrawing.SETTLE_MS));
    }

    @Test
    public void cleanCloseBeforeProofDoesNotCountAsCrash() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        drawing.closed();
        assertFalse(new OverlayDrawing(disk).software());
    }

    @Test
    public void rendererCrashWithHardwareMakesTheNextWindowSoftware() {
        Disk disk = new Disk();
        OverlayDrawing drawing = new OverlayDrawing(disk);
        drawing.windowShown(1_000);
        assertTrue(drawing.rendererCrashed());
        assertTrue(drawing.software());
        assertEquals("draw software (renderer)", drawing.diagnostics());
        // Yazılımla da çökerse yapılacak başka bir şey yok (PageRestarts sınırlar).
        drawing.windowShown(5_000);
        assertFalse(drawing.rendererCrashed());
        assertTrue(new OverlayDrawing(disk).software());
    }
}
