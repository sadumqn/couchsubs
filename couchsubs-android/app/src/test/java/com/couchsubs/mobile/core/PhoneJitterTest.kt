// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * X (22 Kas, GTA 6 telefonu): "yazılar sürekli oynuyor okumak çok zor, balonların içinde de aynı hata var". Aynı balon küçük
 * oynamada yerinde kalır ([PhoneSteady.steadyPositions]), panel el titremesiyle kaymaz ([PhoneSteady.steadyPose]), aynı
 * görünen gönderi yinelenmez ([PhoneSteady.samePicture]); gerçek kaydırmada hepsi birlikte bir kerede geçer (Mac
 * PhoneJitterTests.swift, Windows PhoneJitterTests.cs ile aynı vektörler).
 */
class PhoneJitterTest {
    private fun item(text: String, box: TextBox, line: Double = 0.03) =
        ScreenTranslation.Item(text, "Çevrildi: $text", box, line)

    @Test
    fun smallJitterKeepsEachBubbleWhereItWasDrawn() {
        val before = listOf(item("Thx amigo! U find", TextBox(0.62, 0.65, 0.75, 0.69)),
            item("New message", TextBox(0.64, 0.59, 0.75, 0.62)))
        val jiggled = listOf(before[0].copy(source = "Thx amigo! U flnd", box = TextBox(0.623, 0.655, 0.753, 0.695)),
            before[1].copy(box = TextBox(0.638, 0.586, 0.748, 0.616)))
        val still = PhoneSteady.steadyPositions(jiggled, before, 16.0 / 9)
        assertEquals(0.62, still[0].box.left, 1e-9)
        assertEquals(0.65, still[0].box.top, 1e-9)
        assertEquals(0.59, still[1].box.top, 1e-9)
        assertEquals(0.03, still[1].box.bottom - still[1].box.top, 1e-9)

        val scrolled = before.map { it.copy(box = it.box.copy(top = it.box.top - 0.02, bottom = it.box.bottom - 0.02)) }
        assertEquals(scrolled, PhoneSteady.steadyPositions(scrolled, before, 16.0 / 9))

        val one = listOf(jiggled[0].copy(box = jiggled[0].box.copy(top = 0.665, bottom = 0.705)), jiggled[1])
        val mixed = PhoneSteady.steadyPositions(one, before, 16.0 / 9)
        assertEquals(0.665, mixed[0].box.top, 1e-9)
        assertEquals(0.59, mixed[1].box.top, 1e-9)

        val other = listOf(jiggled[0], jiggled[1].copy(translation = "Başka"))
        assertEquals(other[1].box, PhoneSteady.steadyPositions(other, before, 16.0 / 9)[1].box)
    }

    @Test
    fun panelAnchorIgnoresHandShakeAndFollowsARealMove() {
        val pose = GamePhoneGeometry.Pose(0.70, 0.19, 0.70, 0.87)
        val shaken = GamePhoneGeometry.Pose(0.704, 0.186, 0.703, 0.874)
        assertEquals(pose, PhoneSteady.steadyPose(shaken, pose))
        val moved = GamePhoneGeometry.Pose(0.66, 0.19, 0.66, 0.87)
        assertEquals(moved, PhoneSteady.steadyPose(moved, pose))
        assertEquals(shaken, PhoneSteady.steadyPose(shaken, null))
    }

    @Test
    fun panelMessagesAreComparedByOrderAndTextNotByTheirFlowBoxes() {
        val card = item("", TextBox(0.2, 0.2, 0.5, 0.8)).copy(translation = ScreenPhoneCard.BACKDROP_TEXT,
            panel = ScreenPhoneCard.PanelPart.CARD)
        val message = item("Hi", TextBox(0.22, 0.3, 0.4, 0.34)).copy(panel = ScreenPhoneCard.PanelPart.THEIRS)
        val nudged = message.copy(box = message.box.copy(top = 0.304))
        assertTrue(PhoneSteady.samePicture(listOf(card, message), listOf(card, nudged)))
        assertFalse(PhoneSteady.samePicture(listOf(card, message), listOf(card, message.copy(translation = "Selam"))))
        assertFalse(PhoneSteady.samePicture(listOf(card, message), listOf(card.copy(box = card.box.copy(left = 0.21)), message)))
        assertFalse(PhoneSteady.samePicture(listOf(item("Hi", message.box)), listOf(item("Hi", nudged.box))))
    }

    @Test
    fun inkOnTheSameSideOfTheBubbleKeepsItsColor() {
        assertTrue(PhoneSteady.sameInk("#000000", "#584048", "#C8B0B8"))
        assertFalse(PhoneSteady.sameInk("#000000", "#FFFFFF", "#C8B0B8"))
        val before = item("Casa De Donnie", TextBox(0.65, 0.36, 0.77, 0.38)).copy(surface = TextSurface("#C8B0B8", "#000000"))
        val grey = before.copy(surface = TextSurface("#C8B0B8", "#584048"))
        assertEquals(before.surface, PhoneRegionSession.steady(listOf(grey), listOf(before))[0].surface)
    }

    @Test
    fun sideOfABubbleStaysWithItsIdentity() {
        val spot = TextBox(0.2, 0.2, 0.8, 0.3)
        val before = item("Casa De Donnie", TextBox(0.65, 0.36, 0.77, 0.38))
            .copy(phone = ScreenPhoneCard.Placement(ScreenPhoneCard.Role.INCOMING, spot))
        val flipped = before.copy(phone = ScreenPhoneCard.Placement(ScreenPhoneCard.Role.OUTGOING, spot))
        assertEquals(ScreenPhoneCard.Role.INCOMING, PhoneRegionSession.steady(listOf(flipped), listOf(before))[0].phone?.role)
    }

    @Test
    fun shortMessageWithPunctuationNoiseKeepsItsTranslation() {
        val known = mapOf("Ok." to "Tamam.", "Comprendo?" to "Anladın mı?")
        assertEquals("Tamam.", PhoneSteady.translation("ok", known))
        assertEquals("Anladın mı?", PhoneSteady.translation("Comprendo ?", known))
        assertNull(PhoneSteady.translation("Ok?", known))
        assertNull(PhoneSteady.translation("On", known))
        assertEquals("Yeni", PhoneSteady.translation("New rnessage", mapOf("New message" to "Yeni")))
    }
}
