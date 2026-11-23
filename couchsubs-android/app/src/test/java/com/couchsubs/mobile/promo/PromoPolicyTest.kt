// SPDX-License-Identifier: AGPL-3.0-only
// iPhone'daki PromoPolicyTests ile aynı durumlar.
package com.couchsubs.mobile.promo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PromoPolicyTest {
    private val hour = 60L * 60 * 1000
    private val now = 1_800_000_000_000L
    private val idle = PromoMoment(onHome = true, sessionActive = false, demo = false, onboarding = false, tour = false, inAppMs = 10_000L)
    private val never = PromoRecord(null, 0L)

    private val json = """
        {"version":1,"popup":{"id":"enmera-commerce-1","active":true,
          "image":"https://couchsubs.enmeraapps.com/promo/popup.webp",
          "imageWide":"https://couchsubs.enmeraapps.com/promo/popup-wide.webp",
          "link":"https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs&utm_medium=app&utm_campaign=popup","alt":"Enmera Commerce","everyHours":24,
          "targets":["site","ios","android"]},
         "sitePopup":{"id":"site-1","active":true,"image":"https://x/site.webp","link":"https://x","targets":["site"]},
         "sponsors":[{"name":"Enmera","logo":"https://x/logo.png","url":"https://enmera.com.tr"}]}
    """.trimIndent()

    private fun popup(change: (PromoPopup) -> PromoPopup = { it }) = change(PromoPolicy.parse(json)!!)

    @Test
    fun parsesSiteFormat() {
        val popup = popup()
        assertEquals("enmera-commerce-1", popup.id)
        assertTrue(popup.active)
        assertEquals("https://couchsubs.enmeraapps.com/promo/popup.webp", popup.image)
        assertEquals("https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs&utm_medium=app&utm_campaign=popup", popup.link)
        assertEquals(24, popup.everyHours)
        assertEquals(setOf("site", "ios", "android"), popup.targets)
    }

    @Test
    fun brokenOrMissingPopupIsNull() {
        assertNull(PromoPolicy.parse("not json"))
        assertNull(PromoPolicy.parse("""{"version":1,"sponsors":[]}"""))
        // everyHours yoksa 24.
        assertEquals(24, PromoPolicy.parse("""{"popup":{"id":"a","active":true}}""")!!.everyHours)
    }

    @Test
    fun showsWhenActiveTargetedAndNeverShown() {
        assertTrue(PromoPolicy.shouldShow(popup(), never, now, idle))
    }

    @Test
    fun inactiveIsNeverShown() {
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(active = false) }, never, now, idle))
        assertFalse(PromoPolicy.shouldShow(null, never, now, idle))
    }

    @Test
    fun platformMustBeTargeted() {
        val siteOnly = popup { it.copy(targets = setOf("site", "ios")) }
        assertFalse(PromoPolicy.shouldShow(siteOnly, never, now, idle))
        assertTrue(PromoPolicy.shouldShow(siteOnly, never, now, idle, platform = "ios"))
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(targets = emptySet()) }, never, now, idle))
    }

    @Test
    fun waitsEveryHoursPerPopupId() {
        val popup = popup()
        val shown = PromoRecord("enmera-commerce-1", now - 23 * hour)
        assertFalse(PromoPolicy.shouldShow(popup, shown, now, idle))
        assertTrue(PromoPolicy.shouldShow(popup, shown.copy(shownAtMs = now - 24 * hour), now, idle))
        // Yeni kampanya (başka kimlik) beklemeden gösterilir.
        assertTrue(PromoPolicy.shouldShow(popup.copy(id = "enmera-commerce-2"), shown, now, idle))
        // everyHours 72: bir gün sonra henüz değil.
        assertFalse(PromoPolicy.shouldShow(popup.copy(everyHours = 72), shown.copy(shownAtMs = now - 30 * hour), now, idle))
        // Geçersiz everyHours 24 sayılır.
        assertFalse(PromoPolicy.shouldShow(popup.copy(everyHours = 0), shown, now, idle))
        // Saat geri alındıysa susmaz.
        assertTrue(PromoPolicy.shouldShow(popup, shown.copy(shownAtMs = now + hour), now, idle))
    }

    @Test
    fun neverDuringSessionDemoOnboardingTourOrOtherScreens() {
        val popup = popup()
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(sessionActive = true)))
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(demo = true)))
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(onboarding = true)))
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(tour = true)))
        // Uygulamaya girdikten 10 saniye geçmeden açılmaz.
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(inAppMs = 9_999L)))
        // Eşleme, TV kurulumu, Ayarlar gibi ekranlar ana ekranın üstündeyken.
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(onHome = false)))
    }

    @Test
    fun onlyWebLinksAndHttpsImages() {
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(image = "http://couchsubs.enmeraapps.com/p.webp") }, never, now, idle))
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(link = "intent://evil#Intent;end") }, never, now, idle))
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(link = "") }, never, now, idle))
        assertFalse(PromoPolicy.shouldShow(popup { it.copy(id = "") }, never, now, idle))
    }

    private val bundledJson = """
        {"popups":[{"id":"enmera-commerce-demo-1","image":"popup-enmera.jpg",
          "link":"https://enmera.com.tr/urunler/enmera-commerce?utm_source=couchsubs&utm_medium=app&utm_campaign=popup",
          "alt":"Enmera Commerce: Ücretsiz demo"}],"ads":[]}
    """.trimIndent()

    /** promo.json indirilemezse uygulamayla gelen reklam (reklamlar.json › popups[0]): aynı kurallar (iPhone ile aynı). */
    @Test
    fun bundledPopupFollowsTheSameRules() {
        val popup = PromoPolicy.parseBundled(bundledJson)!!
        assertTrue(popup.bundled)
        assertEquals("popup-enmera.jpg", popup.image)
        assertEquals(setOf("android"), popup.targets)
        // Görsel adres değil; paketteki ad yeter.
        assertTrue(PromoPolicy.shouldShow(popup, never, now, idle))
        // Günde en çok bir kez.
        val shown = PromoRecord(popup.id, now - 2 * hour)
        assertFalse(PromoPolicy.shouldShow(popup, shown, now, idle))
        assertTrue(PromoPolicy.shouldShow(popup, shown.copy(shownAtMs = now - 24 * hour), now, idle))
        // Çeviri sürerken ya da kurulumda açılmaz.
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(sessionActive = true)))
        assertFalse(PromoPolicy.shouldShow(popup, never, now, idle.copy(onboarding = true)))
    }

    @Test
    fun brokenBundledPopupIsNull() {
        assertNull(PromoPolicy.parseBundled("bozuk"))
        assertNull(PromoPolicy.parseBundled("""{"popups":[]}"""))
        assertNull(PromoPolicy.parseBundled(bundledJson.replace("popup-enmera.jpg", "")))
        assertNull(PromoPolicy.parseBundled(bundledJson.replace("popup-enmera.jpg", "../popup-enmera.jpg")))
        assertNull(PromoPolicy.parseBundled(bundledJson.replace("https://enmera", "http://enmera")))
        assertNull(PromoPolicy.parseBundled(bundledJson.replace("enmera-commerce-demo-1", "")))
    }
}
