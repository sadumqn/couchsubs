// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

public class HdmiInputsTest {
    @Test
    public void cecNamesOfTheConsolesAreRecognised() {
        assertTrue(HdmiInputs.looksLikeConsole("PS5"));
        assertTrue(HdmiInputs.looksLikeConsole("PlayStation 5"));
        assertTrue(HdmiInputs.looksLikeConsole("SONY PS 5"));
        assertTrue(HdmiInputs.looksLikeConsole("Xbox Series X"));
        assertFalse(HdmiInputs.looksLikeConsole("Soundbar"));
        assertFalse(HdmiInputs.looksLikeConsole(null));
    }

    @Test
    public void inputsAreOrderedByTheirNumber() {
        assertEquals(2, HdmiInputs.lastNumber("com.mediatek.tvinput/.hdmi.HDMIInputService/HW2"));
        assertEquals(10, HdmiInputs.lastNumber("…/HW10"));
        assertEquals(Long.MAX_VALUE, HdmiInputs.lastNumber("hdmi"));
    }

    // --- Açılışta giriş seçimi (#367) ---

    private static HdmiInputs.Choice input(int port, String device, boolean connected, boolean disconnected) {
        return new HdmiInputs.Choice(port, "HW" + port, device, connected, disconnected);
    }

    /** #367: CEC kapalı, birden çok giriş bağlı görünüyor, kayıt yok. Eskiden HDMI 1 açılıyordu; artık seçici. */
    @Test
    public void unknownConsoleInputDoesNotFallBackToHdmi1() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(
                input(1, null, true, false), input(2, null, false, true), input(3, null, true, false));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 0, 0);
        assertEquals(0, pick.port);
        assertNull(pick.reason);
    }

    @Test
    public void noConnectedInputAndNothingSavedAsksTheUser() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(input(1, null, false, false), input(2, null, false, false));
        assertEquals(0, HdmiInputs.pick(inputs, 0, 0).port);
    }

    @Test
    public void cecConsoleNameWinsOverEverything() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(
                input(1, "Soundbar", true, false), input(2, null, true, false), input(3, "PlayStation 5", true, false));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 1, 2);
        assertEquals(3, pick.port);
        assertEquals(HdmiInputs.Pick.CONSOLE, pick.reason);
    }

    @Test
    public void xboxIsFoundByItsCecName() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(input(1, null, true, false), input(4, "Xbox", true, false));
        assertEquals(4, HdmiInputs.pick(inputs, 0, 0).port);
    }

    @Test
    public void savedChoiceComesBeforeTheLastAndTheActiveInput() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(
                input(1, null, true, false), input(2, null, false, false), input(3, null, false, false));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 3, 2);
        assertEquals(3, pick.port);
        assertEquals(HdmiInputs.Pick.SAVED, pick.reason);
    }

    @Test
    public void lastInputIsUsedWhenNothingIsSaved() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(
                input(1, null, true, false), input(2, null, true, false), input(3, null, false, false));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 0, 3);
        assertEquals(3, pick.port);
        assertEquals(HdmiInputs.Pick.LAST, pick.reason);
    }

    @Test
    public void lastInputIsSkippedWhenTheTvSaysItIsEmpty() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(input(1, null, true, false), input(3, null, false, true));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 0, 3);
        assertEquals(1, pick.port);
        assertEquals(HdmiInputs.Pick.ACTIVE, pick.reason);
    }

    @Test
    public void singleConnectedInputIsTheConsole() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(
                input(1, null, false, true), input(2, null, false, true), input(3, null, true, false));
        HdmiInputs.Pick pick = HdmiInputs.pick(inputs, 0, 0);
        assertEquals(3, pick.port);
        assertEquals(HdmiInputs.Pick.ACTIVE, pick.reason);
    }

    @Test
    public void numbersMissingOnThisTvAreIgnored() {
        List<HdmiInputs.Choice> inputs = Arrays.asList(input(1, null, true, false), input(2, null, true, false));
        assertEquals(0, HdmiInputs.pick(inputs, 4, 7).port);
    }

    @Test
    public void tvWithoutHdmiInputsForAppsAsksTheUser() {
        assertEquals(0, HdmiInputs.pick(Collections.<HdmiInputs.Choice>emptyList(), 3, 0).port);
    }
}
