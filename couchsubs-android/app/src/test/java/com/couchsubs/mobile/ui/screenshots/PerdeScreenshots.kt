// SPDX-License-Identifier: AGPL-3.0-only
// Perde ekran görüntüleri (Robolectric yerel grafik + Roborazzi): Android ekranları koyu ve açık görünümde, küçük ve büyük
// telefonda ve büyük yazı boyunda çizilir; iPhone karşılıklarıyla (Masaüstü/CouchSubs-test/perde/iphone-*.png) yan yana
// göz kontrolü içindir. Yalnız `-Pcouchsubs.screenshots=true` ile çalışır (bkz. app/build.gradle); CI'daki JVM
// testlerinde atlanır. Çıktı: app/build/outputs/roborazzi/android-<ekran>-<boy>-<görünüm>.png.
package com.couchsubs.mobile.ui.screenshots

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.test.core.app.ApplicationProvider
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.ShownPair
import com.couchsubs.mobile.service.LiveStatus
import com.couchsubs.mobile.settings.AppAppearance
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.tv.TvBrand
import com.couchsubs.mobile.ui.AdCatalog
import com.couchsubs.mobile.ui.CouchSubsTheme
import com.couchsubs.mobile.ui.HistoryScreen
import com.couchsubs.mobile.ui.LocalAdBand
import com.couchsubs.mobile.ui.LocalTabBar
import com.couchsubs.mobile.ui.MainScreen
import com.couchsubs.mobile.ui.PacksScreen
import com.couchsubs.mobile.ui.PhoneTab
import com.couchsubs.mobile.ui.SettingsPage
import com.couchsubs.mobile.ui.SettingsScreen
import com.couchsubs.mobile.ui.SettingsSection
import com.couchsubs.mobile.ui.SuccessOverlay
import com.couchsubs.mobile.ui.TabBarState
import com.couchsubs.mobile.ui.Tokens
import com.couchsubs.mobile.ui.TvInstallScreen
import com.couchsubs.mobile.ui.WelcomeScreen
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], application = Application::class)
class PerdeScreenshots {
    private val out = File(System.getProperty("couchsubs.screenshotDir") ?: "build/outputs/roborazzi")

    @Before
    fun setUp() {
        FakeAndroidKeyStore.install()
        val app = ApplicationProvider.getApplicationContext<Application>()
        // Services.init ağ, Firebase ve Meta'yı da kurar; ekran görüntüsü için yalnız ayarlar ve klasörler yeter.
        setField("settings", AppSettings(app))
        setField("importedPacksDirectory", File(app.filesDir, "packs-imported"))
        setField("application", app)
        runCatching {
            val server = Services::class.java.getDeclaredMethod("getPackServer").apply { isAccessible = true }.invoke(Services)
            setField("packStore", com.couchsubs.mobile.packs.PackStore(File(app.filesDir, "packs-remote"),
                server as com.couchsubs.mobile.packs.PackServer, bundledHashes = { emptyMap() }))
        }
        val settings = Services.settings
        settings.tourShown = true
        settings.welcomeSeen = true
        settings.startupSound = false
        settings.console = com.couchsubs.mobile.remoteplay.RegisteredConsole("192.168.1.103", "PS5-002", ByteArray(16), ByteArray(16))
        settings.accountId = ByteArray(8) { 1 }
        settings.tvName = "Salon TV"
        settings.tvInstallBrand = TvBrand.LG
        Tokens.forcedMotion = false
        Tokens.blur = false

    }

    private fun setField(name: String, value: Any) {
        val field = Services::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(Services, value)
    }

    private fun shoot(name: String, tab: PhoneTab? = PhoneTab.HOME, ad: Boolean = true, content: @Composable () -> Unit) {
        val sizes = listOf("kucuk" to "tr-w360dp-h740dp-xhdpi", "buyuk" to "tr-w430dp-h932dp-xxhdpi")
        for ((size, qualifiers) in sizes) for (dark in listOf(true, false)) {
            RuntimeEnvironment.setQualifiers("+$qualifiers")
            RuntimeEnvironment.setFontScale(1f)
            render(name, size, dark, tab, ad, content)
        }
        // Büyük yazı (Dinamik yazı karşılığı, %130) koyu görünümde.
        RuntimeEnvironment.setQualifiers("+tr-w430dp-h932dp-xxhdpi")
        RuntimeEnvironment.setFontScale(1.3f)
        render(name, "buyukyazi", true, tab, ad, content)
        RuntimeEnvironment.setFontScale(1f)
    }

    private fun render(name: String, size: String, dark: Boolean, tab: PhoneTab?, ad: Boolean, content: @Composable () -> Unit) {
        Tokens.appearance = if (dark) AppAppearance.DARK else AppAppearance.LIGHT
        captureRoboImage(File(out, "android-$name-$size-${if (dark) "koyu" else "acik"}.png").path) {
            CouchSubsTheme {
                CompositionLocalProvider(LocalTabBar provides tab?.let { TabBarState(it) { } }, LocalAdBand provides ad) {
                    Box(Modifier.fillMaxSize()) { content() }
                }
            }
        }
    }

    private fun home(status: LiveStatus = LiveStatus()) = @Composable {
        MainScreen(status = status, onStart = {}, onStop = {}, onPhoneView = {}, onTarget = {}, onPairing = {}, onPacks = {},
            onProfile = {}, onSettings = {}, onHome = false)
    }

    @Test fun ana() = shoot("ana") { home()() }

    @Test fun canli() = shoot("canli", ad = false) {
        val now = System.currentTimeMillis()
        home(LiveStatus(running = true, streaming = true, startedAt = now - 250_000, connectedTvs = 1, engineLabel = "Ücretsiz",
            packInUse = "GTA V", recent = listOf(
                ShownPair("You forgot a thousand things every day, pal.", "Her gün bin şeyi unutuyorsun dostum.", "paket", totalMs = 420, ocrMs = 38),
                ShownPair("Make sure this is one of 'em.", "Bunun da onlardan biri olduğundan emin ol.", "motor"),
                ShownPair("Let's go.", "Gidelim.", "paket"),
            ), packLines = 2, shownLines = 3))()
    }

    @Test fun ayarlar() = shoot("ayarlar", PhoneTab.SETTINGS) {
        SettingsScreen(onBack = null, onPacks = {}, onTarget = {}, onPairing = {})
    }

    @Test fun temel() = shoot("ayarlar-temel", PhoneTab.SETTINGS) {
        SettingsPage(SettingsSection.BASICS, onBack = {}, onOpen = {}, onPacks = {}, onTarget = {}, onPairing = {}, onTvInstall = {},
            onPlatform = {}, onDemo = {})
    }

    @Test fun altyaziGorunumu() = shoot("altyazi-gorunumu", PhoneTab.SETTINGS) {
        SettingsPage(SettingsSection.APPEARANCE, onBack = {}, onOpen = {}, onPacks = {}, onTarget = {}, onPairing = {}, onTvInstall = {},
            onPlatform = {}, onDemo = {})
    }

    @Test fun gelismis() = shoot("ayarlar-gelismis", PhoneTab.SETTINGS) {
        SettingsPage(SettingsSection.ADVANCED, onBack = {}, onOpen = {}, onPacks = {}, onTarget = {}, onPairing = {}, onTvInstall = {},
            onPlatform = {}, onDemo = {})
    }

    @Test fun gecmis() {
        Services.addToHistory("Are you listening to me?", "Dinliyor musun beni?", "paket")
        Services.addToHistory("We need to move. Now.", "Gitmemiz lazım. Hemen.", "motor")
        shoot("gecmis", PhoneTab.HISTORY) { HistoryScreen(onBack = null) }
    }

    @Test fun paketler() = shoot("paketler", PhoneTab.SETTINGS) { PacksScreen(onBack = {}, packInUse = null) }

    /** Kapak rafı (paket listesi testte zaman uyumsuz yüklenir; raf ve kapaklar burada doğrudan çizilir). */
    @Test fun paketRafi() = shoot("paket-rafi", PhoneTab.SETTINGS) {
        com.couchsubs.mobile.ui.ScreenScaffold(top = { com.couchsubs.mobile.ui.TopBar("Oyun paketleri", onBack = {}) }) {
            com.couchsubs.mobile.ui.CoverShelf("Kurulu paketler") {
                listOf("Grand Theft Auto V", "Red Dead Redemption 2", "Mafia: The Old Country", "Death Stranding 2").forEachIndexed { index, title ->
                    androidx.compose.foundation.layout.Column {
                        com.couchsubs.mobile.ui.GameCover(title, if (index == 0) "Oynanıyor" else "Kurulu", selected = index == 0)
                        androidx.compose.material3.Text("12 bin satır", color = Tokens.Color.secondary, style = Tokens.Type.captionNumeric)
                    }
                }
            }
            com.couchsubs.mobile.ui.Tile {
                com.couchsubs.mobile.ui.CoverStack(listOf("Grand Theft Auto V", "Red Dead Redemption 2", "Mafia"))
            }
            com.couchsubs.mobile.ui.SuccessMoment("Paket kuruldu", "Grand Theft Auto V · 190 bin satır")
        }
    }

    @Test fun tvKurulum() = shoot("tv-kurulum", null, ad = false) { TvInstallScreen(onBack = {}) }

    @Test fun karsilama() = shoot("karsilama", null, ad = false) { WelcomeScreen {} }

    @Test fun basari() = shoot("basari") {
        home()()
        SuccessOverlay("Eşleşti", "PS5-002")
    }
}
