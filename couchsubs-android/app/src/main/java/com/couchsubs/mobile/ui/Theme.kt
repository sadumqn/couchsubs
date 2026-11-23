// SPDX-License-Identifier: AGPL-3.0-only
// Mobil tasarım sistemi, Perde (iPhone MobileTheme.swift + DS.swift karşılığı; aynı adlar ve ölçüler). Değerler
// design/yeni-arayuz/tasarim.json v2'den derlemede üretilen DesignTokens'tan gelir (Mac, iPhone ve Windows'la tek kaynak);
// bu dosyada elle yazılı renk yoktur. Açık ve koyu görünüm (Ayarlar › Temel › Görünüm; varsayılan koyu).
package com.couchsubs.mobile.ui

import android.provider.Settings
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.ui.DesignTokens.Dark
import com.couchsubs.mobile.ui.DesignTokens.Light
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.haze
import dev.chrisbanes.haze.hazeChild

object Tokens {
    /**
     * Koyu görünüm mü (Ayarlar › Temel › Görünüm: Açık / Koyu / Sisteme Uy; Mac ve iPhone ile aynı, varsayılan koyu).
     * Renkler bu duruma göre okunur; değişince her ekran yeniden çizilir. [forceDark]: altyazı ekranı ve küçük pencere
     * siyah zeminde olduğu için hep koyu renkleri kullanır.
     */
    var appearance by mutableStateOf(com.couchsubs.mobile.settings.AppAppearance.DARK)
    var systemDark by mutableStateOf(true)
    var forceDark by mutableStateOf(false)
    val dark: Boolean
        get() = forceDark || when (appearance) {
            com.couchsubs.mobile.settings.AppAppearance.DARK -> true
            com.couchsubs.mobile.settings.AppAppearance.LIGHT -> false
            com.couchsubs.mobile.settings.AppAppearance.SYSTEM -> systemDark
        }

    /** Geçiş animasyonları (Ayarlar › Temel): kapalıyken yalnız kısa solma kullanılır; sürekli animasyon yok. */
    var transitionAnimations by mutableStateOf(true)

    /** Hareket kapısının girdileri (MainActivity günceller): çeviri sürüyor mu, uygulama önde mi. */
    var translating by mutableStateOf(false)
    var foreground by mutableStateOf(true)

    /**
     * Cam katmanların arkasındaki içerik bulanıklaşsın mı (Android 12+, RenderEffect). Ekran görüntüsü testleri kapatır:
     * Robolectric kaydedilmiş katmanlardaki yer değişikliğini çizmiyor, içerik kaymış görünüyordu.
     */
    var blur = true

    /** Yalnız ekran görüntüsü testleri: kapıyı zorla aç/kapat (iPhone DSMotionGate.forced gibi). */
    var forcedMotion: Boolean? = null

    /** tasarim.json › color (Perde v2). Adlar iPhone Mobile.Palette ile aynı; yeni Perde renkleri tasarim.json adıyla. */
    object Color {
        private fun pick(light: Long, dark: Long) = androidx.compose.ui.graphics.Color(if (Tokens.dark) dark else light)
        val bg get() = pick(Light.background, Dark.background)
        val surface get() = pick(Light.surface, Dark.surface)
        /** Alan zemini (giriş kutusu, seçici izi, kapalı öğe). */
        val surface2 get() = pick(Light.field, Dark.field)
        val field get() = surface2
        /** Yükseltilmiş yüzey (hesap kartı, ikincil düğme). */
        val raised get() = pick(Light.surfaceRaised, Dark.surfaceRaised)
        val surfaceHigh get() = pick(Light.surfaceHigh, Dark.surfaceHigh)
        /** Seçicinin seçili hapı. */
        val segPill get() = pick(Light.segPill, Dark.segPill)
        /** Kart ve satır kıl çizgisi. */
        val border get() = pick(Light.border, Dark.border)
        val tileBorder get() = pick(Light.tileBorder, Dark.tileBorder)
        /** Ayraç, kapalı çizelge çizgisi (iPhone Palette.borderStrong = switchOff). */
        val borderStrong get() = pick(Light.switchOff, Dark.switchOff)
        /** Yükseltilmiş katmanın güçlü kıl çizgisi (tasarim.json borderStrong). */
        val hairStrong get() = pick(Light.borderStrong, Dark.borderStrong)
        val switchOff get() = pick(Light.switchOff, Dark.switchOff)
        val text get() = pick(Light.text, Dark.text)
        val secondary get() = pick(Light.muted, Dark.muted)
        val tertiary get() = pick(Light.faint, Dark.faint)
        val charcoal get() = pick(Light.charcoal, Dark.charcoal)
        val onCharcoal get() = pick(Light.onCharcoal, Dark.onCharcoal)
        val logoBack get() = pick(Light.logoBack, Dark.logoBack)
        val logoSeat get() = pick(Light.logoSeat, Dark.logoSeat)
        /** Yalnız dolgu (ana düğme, anahtar, seçili şey, ilerleme); amber yazı ve simge için [accentText]. */
        val accent get() = pick(Light.amber, Dark.amber)
        val accentHi get() = pick(Light.amberHover, Dark.amberHover)
        val accentLine get() = pick(Light.amberLine, Dark.amberLine)
        val accentText get() = pick(Light.amberText, Dark.amberText)
        val onAccent get() = pick(Light.onAmber, Dark.onAmber)
        val accentSoft get() = pick(Light.amberSoft, Dark.amberSoft)
        val accentGlow get() = pick(Light.amberGlow, Dark.amberGlow)
        val accentRing get() = pick(Light.amberRing, Dark.amberRing)
        /** Oyun paketi vurgusu (iPhone'da amber yazı ve yumuşak amber zemin). */
        val pro get() = accentText
        val proSoft get() = accentSoft
        val success get() = pick(Light.success, Dark.success)
        val successText get() = pick(Light.successText, Dark.successText)
        val successSoft get() = pick(Light.successSoft, Dark.successSoft)
        val successRing get() = pick(Light.successRing, Dark.successRing)
        val warning get() = accentText
        /** Canlı / durdur / hata (kırmızı). */
        val live get() = pick(Light.live, Dark.live)
        val liveText get() = pick(Light.liveText, Dark.liveText)
        val liveSoft get() = pick(Light.liveSoft, Dark.liveSoft)
        val liveRing get() = pick(Light.liveRing, Dark.liveRing)
        val liveDot get() = pick(Light.liveDot, Dark.liveDot)
        /** Çeviriyi durduran dolu düğme: canlı zemin, beyaz yazı. */
        val stopFill get() = pick(Light.stopFill, Dark.stopFill)
        val onStop get() = pick(Light.onStop, Dark.onStop)
        val danger get() = liveText
        val dangerSoft get() = liveSoft
        val info get() = pick(Light.info, Dark.info)
        val infoSoft get() = pick(Light.infoSoft, Dark.infoSoft)
        val infoText get() = pick(Light.infoText, Dark.infoText)
        val scrim get() = pick(Light.scrim, Dark.scrim)
        val glass get() = pick(Light.glass, Dark.glass)
        val glassBorder get() = pick(Light.glassBorder, Dark.glassBorder)
        val topHighlight get() = pick(Light.topHighlight, Dark.topHighlight)
        val peach get() = pick(Light.peach, Dark.peach)
        val olive get() = pick(Light.olive, Dark.olive)
        val teal get() = pick(Light.teal, Dark.teal)
        val plum get() = pick(Light.plum, Dark.plum)
        val sky get() = pick(Light.sky, Dark.sky)
        val screenFrame get() = pick(Light.screenFrame, Dark.screenFrame)
        /** Altyazı plakası her temada aynı (koyu yarı saydam plaka, sıcak beyaz yazı). */
        val subtitlePlate get() = pick(Light.subtitlePlate, Dark.subtitlePlate)
        val subtitleText get() = pick(Light.subtitleText, Dark.subtitleText)
        val coverScrim get() = pick(Light.coverScrim, Dark.coverScrim)
    }

    /** Telefon ölçüleri (tasarim.json › space; iPhone Mobile.Space): kenar 16, kart içi 20, kartlar arası 16. */
    object Space {
        val screen = DesignTokens.Space.screenEdgeIOS.dp
        /** Kart içi boşluk. */
        val tile = DesignTokens.Space.cardPadIOS.dp
        /** Kartlar arası (ekranın dikey yığını). */
        val cards = DesignTokens.Space.m.dp
        /** Bölüm (ör. sekme kökünde ayar grupları) arası. */
        val section = DesignTokens.Space.section.dp
        /** Ayar birimleri arası. */
        val unit = DesignTokens.Space.unitGap.dp
        val gap = DesignTokens.Space.s.dp
        val inline = DesignTokens.Space.xs.dp
        val titleToBody = DesignTokens.Space.titleBody.dp
        val hair = DesignTokens.Space.xxs.dp
        val micro = DesignTokens.Space.line.dp
    }

    /** tasarim.json › radius: kart 24, denetim 12, karo 16, çip 8. */
    object Radius {
        val tile = DesignTokens.Radius.card.dp
        val tileSmall = DesignTokens.Radius.tile.dp
        val control = DesignTokens.Radius.control.dp
        val small = DesignTokens.Radius.small.dp
        val inner = DesignTokens.Radius.chip.dp
        val tag = 6.dp
        val preview = DesignTokens.Radius.preview.dp
        val cover = DesignTokens.Radius.cover.dp
    }

    object Control {
        val button = DesignTokens.Size.button.dp
        val buttonSmall = DesignTokens.Size.iconButton.dp
        /** Simge düğmesinin görünen boyu; dokunma alanı [touch]. */
        val icon = DesignTokens.Size.iconButton.dp
        /** En küçük dokunma alanı (Android erişilebilirlik kuralı). */
        val touch = 48.dp
        /** Seçicide bir sekmenin en küçük yüksekliği. */
        val segment = DesignTokens.Size.tab.dp
        val field = DesignTokens.Size.input.dp
        val row = 52.dp
        val tag = DesignTokens.Size.badge.dp
        val tileIcon = 18.dp
        val statusDot = DesignTokens.Size.statusDot.dp
        val tabBar = DesignTokens.Size.tabBarHeight.dp
        val adBand = 56.dp
    }

    /**
     * Yazı ölçeği (iPhone DS.font: telefonda sistem metin stilleri; sp olduğu için yazı boyu ayarıyla büyür): sayfa başlığı
     * 28, ara başlık 20, kart başlığı 17, satır başlığı 15 orta, gövde 15, açıklama 13, küçük 12.
     */
    object Type {
        val display = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.4).sp)
        val h3 = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Medium)
        /** Değer (karodaki "PS5-002"): 20 yarı kalın, tablo rakamlı. */
        val title = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")
        val cardTitle = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Medium)
        /** Satır/alan başlığı (bodyStrong). */
        val headline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
        /** Önceki altyazı satırları. */
        val line = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal)
        val body = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal)
        /** Gri açıklama (small): 13, satır +3, -0,5 harf aralığı yalnız açıklamada ([muted]). */
        val caption = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal)
        val muted = caption.copy(letterSpacing = (DesignTokens.MUTED_TRACKING / 2).sp)
        val label = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
        val small = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Normal)
        val button = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
        val tab = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
        val mono = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace,
            fontFeatureSettings = "tnum")
        val monoValue = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            fontFeatureSettings = "tnum")
        // Tablo rakamları: süre, sayaç ve kaydırıcı değeri değişirken rakamlar eş genişlikte kalır, satır kaymaz.
        val titleNumeric = title
        val captionNumeric = caption.copy(fontFeatureSettings = "tnum")
        /** Bilgi karosundaki ve kaydırıcının yanındaki değer: 15 orta kalın, tablo rakamlı. */
        val value = headline.copy(fontFeatureSettings = "tnum")
        /** Canlı satır (iPhone fontIOS › liveLine 22) ve yatay altyazı ekranı. */
        val subtitleCurrent = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.SemiBold)
        val subtitleLandscape = TextStyle(fontSize = 36.sp, lineHeight = 44.sp, fontWeight = FontWeight.SemiBold)
    }

    /** tasarim.json › motion (ms). */
    object Motion {
        val short = DesignTokens.Motion.short
        val medium = DesignTokens.Motion.medium
        val page = DesignTokens.Motion.page
        val reduced = DesignTokens.Motion.reduced
    }
}

/** Hareket kapısı (iPhone DSMotionGate): sürekli animasyonların ne zaman oynayacağı. */
data class MotionGate(val reduced: Boolean, val translating: Boolean, val active: Boolean) {
    /** Boşta süren efektler (ortam ışığı, arama halkası, çubuk yükleyici, ışınlar, parıltı). */
    val ambient: Boolean get() = Tokens.forcedMotion ?: (!reduced && !translating && active)
    /** Canlı nabız (çeviri sürerken de atar; ekrandaki tek sürekli animasyon). */
    val live: Boolean get() = Tokens.forcedMotion ?: (!reduced && active)
}

/**
 * Uygulamanın tek hareket kapısı: sistemde "Animasyonları kaldır" açık ya da Ayarlar › Geçiş Animasyonları kapalıysa
 * [MotionGate.reduced]; çeviri sürerken ve uygulama arka plandayken sürekli animasyonlar durur.
 */
@Composable
fun motionGate(): MotionGate = MotionGate(reducedMotion() || !Tokens.transitionAnimations, Tokens.translating, Tokens.foreground)

/** Kısa geri bildirim animasyonu: kapıya göre giriş eğrisi ya da hareket azaltılmışken 100 ms solma. */
fun <T> perdeTween(ms: Int, gate: MotionGate) = tween<T>(if (gate.reduced) Tokens.Motion.reduced else ms,
    easing = if (gate.reduced) androidx.compose.animation.core.LinearOutSlowInEasing else PerdeEasing.enter)

object PerdeEasing {
    val enter = DesignTokens.Motion.enter.let { androidx.compose.animation.core.CubicBezierEasing(it[0], it[1], it[2], it[3]) }
    val exit = DesignTokens.Motion.exit.let { androidx.compose.animation.core.CubicBezierEasing(it[0], it[1], it[2], it[3]) }
    /** Hafif aşmalı yay (başarı tiki, oturma). */
    val spring = DesignTokens.Motion.spring.let { androidx.compose.animation.core.CubicBezierEasing(it[0], it[1], it[2], it[3]) }
}

@Composable
fun CouchSubsTheme(forceDark: Boolean = false, content: @Composable () -> Unit) {
    // "Sisteme Uy" için sistemin görünümü; altyazı ekranı ve küçük pencere hep koyu.
    val system = androidx.compose.foundation.isSystemInDarkTheme()
    if (Tokens.systemDark != system) Tokens.systemDark = system
    if (Tokens.forceDark != forceDark) Tokens.forceDark = forceDark
    val c = Tokens.Color
    val base = if (Tokens.dark) darkColorScheme() else lightColorScheme()
    MaterialTheme(
        // M3'ün kendi parçaları (açılır menü, iletişim kutusu, gösterge) varsayılan mor tonlara düşmesin: her yüzey rolü
        // tasarim.json'daki bir renge bağlanır, yüzey tonlaması (surfaceTint) kapalıdır.
        colorScheme = base.copy(
            primary = c.accent, onPrimary = c.onAccent, primaryContainer = c.accentSoft, onPrimaryContainer = c.accentText,
            inversePrimary = c.accentText,
            secondary = c.accentText, onSecondary = c.onAccent, secondaryContainer = c.surface2, onSecondaryContainer = c.text,
            tertiary = c.accentText, onTertiary = c.onAccent, tertiaryContainer = c.accentSoft, onTertiaryContainer = c.accentText,
            background = c.bg, onBackground = c.text, surface = c.surface, onSurface = c.text,
            surfaceVariant = c.surface2, onSurfaceVariant = c.secondary, surfaceTint = Color.Transparent,
            inverseSurface = c.text, inverseOnSurface = c.bg,
            error = c.danger, onError = c.onAccent, errorContainer = c.dangerSoft, onErrorContainer = c.danger,
            outline = c.borderStrong, outlineVariant = c.border, scrim = Color.Black,
            surfaceBright = c.raised, surfaceDim = c.bg,
            surfaceContainerLowest = c.bg, surfaceContainerLow = c.surface, surfaceContainer = c.surface,
            surfaceContainerHigh = c.raised, surfaceContainerHighest = c.surface2,
        ),
        typography = Typography(
            displaySmall = Tokens.Type.display, titleLarge = Tokens.Type.h3, titleMedium = Tokens.Type.cardTitle,
            bodyLarge = Tokens.Type.body, bodyMedium = Tokens.Type.body, bodySmall = Tokens.Type.caption,
            labelLarge = Tokens.Type.button, labelMedium = Tokens.Type.label,
        ),
        shapes = Shapes(
            extraSmall = RoundedCornerShape(Tokens.Radius.tag), small = RoundedCornerShape(Tokens.Radius.inner),
            medium = RoundedCornerShape(Tokens.Radius.control), large = RoundedCornerShape(Tokens.Radius.tile),
            extraLarge = RoundedCornerShape(Tokens.Radius.tile),
        ),
    ) {
        // Dalga (ripple) ve renk verilmemiş simgeler açık renkte: varsayılan içerik rengi siyahtır, koyu zeminde basış görünmez.
        CompositionLocalProvider(LocalContentColor provides c.text, content = content)
    }
}

/** Bu ekranın zemininde ortam ışığı olsun mu (ana ekran, karşılama, kurulum adımları; iPhone `.perdeAmbient()`). */
val LocalAmbient = compositionLocalOf { false }

/**
 * Her ekranın zemini: `bg`; [ambient] ise üstten sızan amber projeksiyon ışığı ve çok yavaş süzülen sıcak lekeler
 * (hareket kapısı kapalıyken durağan).
 */
@Composable
fun ScreenBackground(ambient: Boolean = LocalAmbient.current, content: @Composable BoxScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Tokens.Color.bg)) {
        if (ambient) {
            AmbientGlow(intensity = 0.8f)
            ProjectorLight()
        }
        content()
    }
}

/** Kartın vurgusu (iPhone TileEmphasis): seçili (amber halka + dolgu + ışıma), uyarı (amber), tehlike/deneysel (kırmızı). */
enum class TileStyle { NORMAL, ACTIVE, WARNING, DANGER }

/** e1 · kart yükseltisi: yüzey + kıl çizgi + koyu temada üst kenar parlaması (açıkta çok hafif gölge). */
fun Modifier.perdeCard(shape: Shape, fill: Color = Tokens.Color.surface, border: Color = Tokens.Color.border): Modifier =
    this.background(fill, shape).border(1.dp, border, shape).then(topHighlight(shape))

/** e2 · yükseltilmiş: yükseltilmiş yüzey + güçlü kıl çizgi + derin gölge (hesap kartı, açılır menü). */
fun Modifier.perdeRaised(shape: Shape): Modifier =
    this.shadow(if (Tokens.dark) 14.dp else 10.dp, shape, ambientColor = Color.Black.copy(alpha = if (Tokens.dark) 0.45f else 0.16f),
        spotColor = Color.Black.copy(alpha = if (Tokens.dark) 0.45f else 0.16f))
        .background(Tokens.Color.raised, shape).border(1.dp, Tokens.Color.hairStrong, shape).then(topHighlight(shape))

/** Koyu temada yüzeyin üst kenarındaki ince ışık (inset 0 1 0 topHighlight); açık temada yok. */
fun Modifier.topHighlight(shape: Shape): Modifier {
    if (!Tokens.dark) return this
    val glow = Tokens.Color.topHighlight
    return this.border(1.dp, Brush.verticalGradient(0f to glow, 0.5f to Color.Transparent), shape)
}

/**
 * Kart (iPhone Tile): yüzey, 1 dp kıl çizgi, 24 köşe, 20 iç boşluk; dokunulan kart basılıyken %97 ölçeğe iner. Klavye
 * ya da kumanda odağında 2 dp amber halka. [toggled] verilirse kart bir anahtardır (ör. paket açık/kapalı).
 */
@Composable
fun Tile(
    modifier: Modifier = Modifier, style: TileStyle = TileStyle.NORMAL, onClick: (() -> Unit)? = null, toggled: Boolean? = null,
    spacing: Dp = Tokens.Space.inline, content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(Tokens.Radius.tile)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val focused by interaction.collectIsFocusedAsState()
    val gate = motionGate()
    val scale by animateFloatAsState(if (pressed && !gate.reduced) 0.97f else 1f, tween(Tokens.Motion.short), label = "tile")
    val tint = when (style) {
        TileStyle.NORMAL -> Color.Transparent
        TileStyle.ACTIVE -> Tokens.Color.accent.copy(alpha = 0.08f)
        TileStyle.WARNING -> Tokens.Color.accent.copy(alpha = 0.06f)
        TileStyle.DANGER -> Tokens.Color.live.copy(alpha = 0.05f)
    }
    val ring = when {
        focused -> BorderStroke(2.dp, Tokens.Color.accent)
        style == TileStyle.ACTIVE -> BorderStroke(2.dp, Tokens.Color.accent)
        style == TileStyle.WARNING -> BorderStroke(1.5.dp, Tokens.Color.accent)
        style == TileStyle.DANGER -> BorderStroke(1.5.dp, Tokens.Color.live)
        else -> null
    }
    Column(
        modifier.scale(scale)
            .then(if (style == TileStyle.ACTIVE) Modifier.shadow(12.dp, shape, ambientColor = Tokens.Color.accentGlow, spotColor = Tokens.Color.accentGlow) else Modifier)
            .perdeCard(shape, if (pressed) Tokens.Color.surfaceHigh else Tokens.Color.surface)
            .background(tint, shape)
            .then(if (ring != null) Modifier.border(ring, shape) else Modifier)
            .clip(shape)
            .let {
                when {
                    onClick == null -> it
                    toggled != null -> it.toggleable(toggled, interaction, indication = null, role = Role.Switch) { onClick() }
                    else -> it.clickable(interaction, indication = null, role = Role.Button, onClick = onClick)
                }
            }
            .padding(horizontal = Tokens.Space.tile, vertical = if (spacing == 0.dp) Tokens.Space.hair else Tokens.Space.tile),
        verticalArrangement = Arrangement.spacedBy(spacing),
        content = content,
    )
}

/** Karo başlığı (13 orta, ikincil renk). */
@Composable
fun TileLabel(text: String, color: Color = Tokens.Color.secondary) = Text(text, style = Tokens.Type.label, color = color)

/** Kart içindeki bölüm başlığı (cümle düzeni, 17 orta); altındaki içerikle arası kartın aralığına ek 4. */
@Composable
fun SectionTitle(text: String) = Text(text, style = Tokens.Type.cardTitle, color = Tokens.Color.text,
    modifier = Modifier.padding(bottom = Tokens.Space.hair).semantics { heading() })

/** Düğme türleri (iPhone DSButtonStyle): ana, ikincil, hayalet, durdur (kırmızı tonlu, kare), canlı (kırmızı tonlu, nabız). */
/**
 * Düğme türleri (iPhone DSButtonStyle): ana, ikincil, hayalet; durdur (dolu canlı zemin, beyaz yazı, kare) ve canlı (dolu,
 * beyaz nabız): çeviri sürerken birincil eylem; tehlikeli (Sil, Kaldır, Temizle) soluk kırmızı kalır.
 */
enum class ButtonKind { PRIMARY, SECONDARY, GHOST, STOP, LIVE, DANGER }

/**
 * Düğme gövdesi: tam yuvarlak, en az 48. Ana düğme amber degrade + üst kenar parlaması + amber ışıma (ekranda tek);
 * pasifken alan zemini ve soluk yazı. İkincil yükseltilmiş yüzey + kıl çizgi; durdur/canlı kırmızı yumuşak zemin.
 * Basılıyken %97 (hareket azaltılmışken yok). [busy]: işlem sürerken çubuk yükleyici, düğme basılmaz.
 */
@Composable
fun PerdeButton(
    text: String, kind: ButtonKind, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false,
    fullWidth: Boolean = true, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val gate = motionGate()
    val view = LocalView.current
    val shape = CircleShape
    val active = enabled && !busy
    val scale by animateFloatAsState(if (pressed && !gate.reduced) 0.97f else 1f, tween(Tokens.Motion.short), label = "button")
    val c = Tokens.Color
    val foreground = when {
        busy -> c.secondary
        kind == ButtonKind.PRIMARY && !enabled -> c.tertiary
        kind == ButtonKind.PRIMARY -> c.onAccent
        kind == ButtonKind.SECONDARY -> c.text
        kind == ButtonKind.GHOST -> c.accentText
        kind == ButtonKind.DANGER -> c.liveText
        else -> c.onStop
    }
    val background: Modifier = when {
        kind == ButtonKind.PRIMARY && !enabled && !busy -> Modifier.background(c.field, shape)
        kind == ButtonKind.PRIMARY -> Modifier
            .shadow(if (active) 10.dp else 0.dp, shape, ambientColor = c.accentGlow, spotColor = c.accentGlow)
            .background(Brush.verticalGradient(listOf(if (pressed) c.accent else c.accentHi, c.accent)), shape)
            .border(1.dp, Brush.verticalGradient(0f to Color.White.copy(alpha = 0.45f), 0.5f to c.accentLine.copy(alpha = 0.6f)), shape)
        kind == ButtonKind.SECONDARY -> Modifier.background(if (pressed) c.surfaceHigh else c.raised, shape).border(1.dp, c.border, shape)
        kind == ButtonKind.GHOST -> Modifier.background(if (pressed) c.field else Color.Transparent, shape)
        kind == ButtonKind.DANGER -> Modifier.background(c.surface, shape)
            .background(if (pressed) c.live.copy(alpha = 0.22f) else c.liveSoft, shape).border(1.dp, c.liveRing, shape)
        else -> Modifier.background(c.stopFill, shape).background(Color.Black.copy(alpha = if (pressed) 0.16f else 0f), shape)
    }
    Row(
        modifier.let { if (fullWidth && kind != ButtonKind.GHOST) it.fillMaxWidth() else it }
            .heightIn(min = if (kind == ButtonKind.GHOST) Tokens.Control.buttonSmall else Tokens.Control.button)
            .scale(scale)
            .then(background)
            .clip(shape)
            .clickable(interaction, indication = null, enabled = active, role = Role.Button) {
                if (kind == ButtonKind.PRIMARY) Haptics.primary(view)
                onClick()
            }
            .alpha(if (busy) 0.85f else if (enabled || kind == ButtonKind.PRIMARY) 1f else 0.55f)
            .padding(horizontal = if (kind == ButtonKind.GHOST) Tokens.Space.gap else Tokens.Space.unit, vertical = Tokens.Space.inline),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (kind == ButtonKind.STOP || kind == ButtonKind.LIVE) 10.dp else Tokens.Space.inline, Alignment.CenterHorizontally),
    ) {
        when {
            busy -> BarsLoader(color = if (kind == ButtonKind.PRIMARY) c.onAccent else c.accent)
            kind == ButtonKind.STOP -> Box(Modifier.size(10.dp).background(c.onStop, RoundedCornerShape(2.dp)))
            kind == ButtonKind.LIVE -> PulseDot(c.onStop, 8.dp)
            leading != null -> leading()
        }
        ButtonLabel(text, foreground, if (kind == ButtonKind.SECONDARY || kind == ButtonKind.GHOST) Tokens.Type.button.copy(fontWeight = FontWeight.Medium) else Tokens.Type.button)
    }
}

/** Ana düğme (ekranda bir tane): amber degrade + ışıma. */
@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, onClick: () -> Unit) =
    PerdeButton(text, ButtonKind.PRIMARY, modifier, enabled, busy, onClick = onClick)

@Composable
fun SecondaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, onClick: () -> Unit) =
    PerdeButton(text, ButtonKind.SECONDARY, modifier, enabled, busy, onClick = onClick)

@Composable
fun GhostButton(text: String, modifier: Modifier = Modifier, color: Color = Tokens.Color.accentText, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier.heightIn(min = Tokens.Control.buttonSmall).clip(CircleShape)
            .background(if (pressed) Tokens.Color.field else Color.Transparent, CircleShape)
            .clickable(interaction, indication = null, role = Role.Button, onClick = onClick)
            .padding(horizontal = Tokens.Space.gap, vertical = Tokens.Space.inline),
        contentAlignment = Alignment.Center,
    ) { ButtonLabel(text, color, Tokens.Type.button.copy(fontWeight = FontWeight.Medium)) }
}

/**
 * Düğme yazısı tek satırda kalır (iki satıra bölünmez): sığmazsa %80'e kadar küçülür (iPhone'daki minimumScaleFactor gibi).
 * Sistem yazı boyu büyükken (1,3 ve üstü) küçültülmez, satıra bölünebilir.
 */
@Composable
private fun ButtonLabel(text: String, color: Color, style: TextStyle) {
    val large = LocalDensity.current.fontScale >= 1.3f
    var scale by remember(text) { mutableFloatStateOf(1f) }
    Text(text, style = style.copy(fontSize = style.fontSize * scale), color = color, textAlign = TextAlign.Center,
        maxLines = if (large) 3 else 1, softWrap = large, overflow = if (large) TextOverflow.Ellipsis else TextOverflow.Clip,
        onTextLayout = { if (!large && it.didOverflowWidth && scale > 0.8f) scale = (scale - 0.05f).coerceAtLeast(0.8f) })
}

/** Tehlikeli (Sil, Kaldır, Temizle): soluk kırmızı zemin, kırmızı yazı, kırmızı ince halka. */
@Composable
fun DestructiveButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) =
    PerdeButton(text, ButtonKind.DANGER, modifier, onClick = onClick)

/** Durdur (ör. Deneme Modundan Çık): dolu canlı zemin, beyaz yazı, solda küçük kare. */
@Composable
fun StopButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) =
    PerdeButton(text, ButtonKind.STOP, modifier, onClick = onClick)

/** "Çeviriyi Durdur": dolu canlı zemin + beyaz atan nokta (çeviri sürerken birincil eylem). */
@Composable
fun LiveButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) =
    PerdeButton(text, ButtonKind.LIVE, modifier, onClick = onClick)

/**
 * Simge düğmesi: 44 dp yuvarlak cam (dokunma alanı 48). Ekran okuyucu [label]'ı düğme olarak okur; içindeki simgenin
 * açıklaması olmamalı (null), yoksa ad iki kez okunur.
 */
@Composable
fun IconSquare(label: String, modifier: Modifier = Modifier, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier.minimumInteractiveComponentSize().size(Tokens.Control.icon).clip(CircleShape)
            .glass(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** Etiket: 24 yükseklik, tam yuvarlak; nötr (alan zemini + ikincil yazı) ya da paket için amber ([pro]). */
@Composable
fun Pill(text: String, modifier: Modifier = Modifier, pro: Boolean = false) {
    Box(
        modifier.heightIn(min = Tokens.Control.tag)
            .background(if (pro) Tokens.Color.accentSoft else Tokens.Color.field, CircleShape)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = Tokens.Type.small.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
            color = if (pro) Tokens.Color.accentText else Tokens.Color.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Sistemde "Animasyonları kaldır" (azaltılmış hareket) açık mı. */
@Composable
fun reducedMotion(): Boolean {
    val context = LocalContext.current
    return remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * Durum noktası (8 dp). Yalnız [live] (çeviri canlı) iken Perde nabzı atar (hareket kapısı açıkken); "Bağlı", "Hazır"
 * gibi durumlarda ve azaltılmış harekette sabit.
 */
@Composable
fun LiveDot(color: Color = Tokens.Color.success, live: Boolean = false) {
    Box(Modifier.size(Tokens.Control.statusDot * 2), contentAlignment = Alignment.Center) {
        if (live) PulseDot(color, Tokens.Control.statusDot)
        else Box(Modifier.size(Tokens.Control.statusDot).background(color, CircleShape))
    }
}

/**
 * Durum: nokta + kelime, zeminsiz ("Bağlı", "Çeviri sürüyor · 4:10"). Süre taşıyan durum [Tokens.Type.captionNumeric]
 * ile yazılır (tablo rakamları).
 */
@Composable
fun StatusLabel(text: String, ok: Boolean = true, live: Boolean = false, style: TextStyle = Tokens.Type.caption) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        LiveDot(if (live) Tokens.Color.liveDot else if (ok) Tokens.Color.success else Tokens.Color.secondary, live = live)
        Text(text, style = style, color = Tokens.Color.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Giriş kutusu (iPhone DSFieldChrome): üstte etiket (13 orta), altında tam yuvarlak 48'lik kutu, alan zemini, ince
 * halka; odakta amber halka ve dışında yumuşak amber hale. [trailing] kutunun içinde sağda (kopyala, kaldır).
 */
@Composable
fun Field(
    value: String, onChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    secret: Boolean = false, keyboard: androidx.compose.foundation.text.KeyboardOptions = androidx.compose.foundation.text.KeyboardOptions.Default,
    // Çok satırlı alan (ör. ek talimat): en az bu kadar satır; 1 ise tek satır.
    lines: Int = 1, placeholder: String? = null, mono: Boolean = false, trailing: (@Composable () -> Unit)? = null,
) {
    var focused by remember { mutableStateOf(false) }
    val ring by animateColorAsState(if (focused) Tokens.Color.accent else Tokens.Color.border, tween(Tokens.Motion.short), label = "ring")
    val shape = if (lines == 1) CircleShape else RoundedCornerShape(Tokens.Radius.tileSmall)
    val style = (if (mono) Tokens.Type.mono.copy(fontSize = 13.sp) else Tokens.Type.body).copy(color = Tokens.Color.text)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Text(label, style = Tokens.Type.label, color = Tokens.Color.text)
        BasicTextField(
            value, onChange,
            modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }
                .semantics { contentDescription = label },
            singleLine = lines == 1, minLines = lines, maxLines = if (lines == 1) 1 else lines * 2,
            textStyle = style, keyboardOptions = keyboard, cursorBrush = SolidColor(Tokens.Color.accentText),
            visualTransformation = if (secret) androidx.compose.ui.text.input.PasswordVisualTransformation() else VisualTransformation.None,
            decorationBox = { inner ->
                Row(
                    Modifier.fillMaxWidth()
                        .drawBehind {
                            if (focused) drawRoundRect(Tokens.Color.accentSoft, topLeft = Offset(-4.dp.toPx(), -4.dp.toPx()),
                                size = androidx.compose.ui.geometry.Size(size.width + 8.dp.toPx(), size.height + 8.dp.toPx()),
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(if (lines == 1) size.height else 20.dp.toPx()))
                        }
                        .heightIn(min = Tokens.Control.field)
                        .background(Tokens.Color.field, shape)
                        .border(if (focused) 1.5.dp else 1.dp, ring, shape)
                        .padding(start = 20.dp, end = if (trailing != null) Tokens.Space.hair else 20.dp,
                            top = if (lines == 1) 0.dp else Tokens.Space.gap, bottom = if (lines == 1) 0.dp else Tokens.Space.gap),
                    verticalAlignment = if (lines == 1) Alignment.CenterVertically else Alignment.Top,
                ) {
                    Box(Modifier.weight(1f)) {
                        if (value.isEmpty() && placeholder != null)
                            Text(placeholder, style = style, color = Tokens.Color.tertiary, maxLines = lines, overflow = TextOverflow.Ellipsis)
                        inner()
                    }
                    trailing?.invoke()
                }
            },
        )
    }
}

/** Sekme çubuğunun durumu: hangi sekme seçili ve seçince ne olur (MainActivity verir). */
data class TabBarState(val active: PhoneTab, val select: (PhoneTab) -> Unit)

/** null: bu ekranda sekme çubuğu yok (kurulum adımları, açılış, oyun görüntüsü). */
val LocalTabBar = compositionLocalOf<TabBarState?> { null }

/** Sayfanın altında reklam şeridi: yalnız uygulama ve ayar sayfalarında; çeviri, deneme, kurulum ve açılışta yok. */
val LocalAdBand = compositionLocalOf { false }

/** Ekranın cam katmanlarının (sekme çubuğu, kenar çubukları) bulanıklaştırdığı içerik. */
val LocalHaze = compositionLocalOf<HazeState?> { null }

/**
 * Ekran iskeleti (iPhone MobileScreen): içerik ekranın en üstüne ve en altına kadar kayar (kenardan kenara; sistem
 * çubukları için iç boşluk). Başlık satırı ve alttaki bölge (düğmeler, reklam şeridi, cam sekme çubuğu) içeriğin üstünde
 * yüzer; içerik onların altından kayar. Kenarlarda sert kesim yok: zemin, ekranın kenarından çubuğun iç tarafına doğru
 * saydamlaşır. Son öğe çubukların altında kalmaz: çubukların ölçülen yüksekliği kaydırmanın iç boşluğuna eklenir. Klavye
 * açılınca alt bölge klavyenin üstüne çıkar ve sekme çubuğu gizlenir.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ScreenScaffold(
    top: (@Composable () -> Unit)? = null,
    bottom: (@Composable ColumnScope.() -> Unit)? = null,
    scroll: Boolean = true,
    ambient: Boolean = LocalAmbient.current,
    content: @Composable ColumnScope.() -> Unit,
) {
    val density = LocalDensity.current
    val sides = WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)
    // Arkadaki içeriğin bulanıklığı (cam): yalnız Android 12+ ve [Tokens.blur] açıkken; değilse cam yarı saydam yedekle çizilir.
    val haze = remember { HazeState() }.takeIf { Tokens.blur && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S }
    // Klavye açıkken (alt kenarda klavye payı varken) sekme çubuğu gizlenir.
    val tabBar = LocalTabBar.current?.takeIf { WindowInsets.ime.getBottom(density) == 0 }
    val adBand = LocalAdBand.current && AdCatalog.band(LocalContext.current).isNotEmpty()
    val hasBottom = bottom != null || adBand || tabBar != null
    CompositionLocalProvider(LocalHaze provides haze, LocalAmbient provides ambient) {
        ScreenBackground(ambient) {
            val state = rememberScrollState()
            // Çubuklar önce ölçülür, içerik onların yüksekliğini iç boşluk olarak alır (Scaffold gibi): ilk karede de içerik
            // başlığın altında başlar, sonradan kaymaz. Çizim sırası içerik, sonra çubuklar (içerik altlarından kayar).
            SubcomposeLayout(Modifier.fillMaxSize()) { constraints ->
                val width = constraints.maxWidth
                val height = constraints.maxHeight
                val bar = constraints.copy(minWidth = width, maxWidth = width, minHeight = 0)
                val topBar = subcompose("top") {
                    Column(
                        Modifier.fillMaxWidth().edgeFade(atTop = true)
                            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                            .padding(start = Tokens.Space.screen, end = Tokens.Space.screen, top = Tokens.Space.inline, bottom = Tokens.Space.hair),
                    ) { top?.invoke() }
                }.map { it.measure(bar) }
                val bottomBar = subcompose("bottom") {
                    if (hasBottom) Column(
                        Modifier.fillMaxWidth().then(if (tabBar != null || adBand) Modifier.bottomGlass(haze) else Modifier.edgeFade(atTop = false))
                            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
                            .padding(start = Tokens.Space.screen, end = Tokens.Space.screen, top = Tokens.Space.gap,
                                bottom = when {
                                    tabBar != null -> Tokens.Space.hair
                                    adBand -> Tokens.Space.inline
                                    else -> Tokens.Space.screen
                                }),
                        verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap), horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        bottom?.invoke(this)
                        if (adBand) AdBand()
                        tabBar?.let { PerdeTabBar(it.active, it.select) }
                    }
                    // Alt çubuk yoksa da içerik sistem gezinme çubuğunun altında kalmasın.
                    else Spacer(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)))
                }.map { it.measure(bar) }
                val topHeight = topBar.maxOfOrNull { it.height } ?: 0
                val bottomHeight = bottomBar.maxOfOrNull { it.height } ?: 0
                val body = subcompose("content") {
                    Column(
                        Modifier.fillMaxSize().let { if (haze != null) it.haze(haze) else it }.let { if (scroll) it.verticalScroll(state) else it }
                            .windowInsetsPadding(sides)
                            .padding(start = Tokens.Space.screen, end = Tokens.Space.screen, top = topHeight.toDp() + Tokens.Space.gap,
                                bottom = bottomHeight.toDp() + Tokens.Space.screen),
                        verticalArrangement = Arrangement.spacedBy(Tokens.Space.cards),
                        content = content,
                    )
                }.map { it.measure(constraints.copy(minWidth = width, minHeight = height)) }
                layout(width, height) {
                    body.forEach { it.place(0, 0) }
                    topBar.forEach { it.place(0, 0) }
                    bottomBar.forEach { it.place(0, height - it.height) }
                }
            }
        }
    }
}

/**
 * Alt cam bölge (iPhone BottomGlass; ana eylem + reklam şeridi + sekme çubuğu): ekranın altına kadar tek yüzey, üst kenarda
 * kıl çizgi. Android 12+'da arkadaki içerik bulanıklaşır; zemin rengi (%82) arkadaki yazıyı okunur gürültü olmaktan
 * çıkarır. İçerik arkasından kaymaya devam eder; düğme hiçbir kartın yazısını yarım bırakacak biçimde yüzmez.
 */
private fun Modifier.bottomGlass(haze: HazeState?): Modifier {
    val bg = Tokens.Color.bg
    val line = Tokens.Color.border
    val base = if (haze != null) this.hazeChild(haze, dev.chrisbanes.haze.HazeStyle(backgroundColor = bg,
        tint = dev.chrisbanes.haze.HazeTint(bg.copy(alpha = 0.82f)), blurRadius = 24.dp, noiseFactor = 0f))
    else this.background(bg.copy(alpha = 0.94f))
    return base.drawBehind { drawRect(line, size = Size(size.width, 0.5.dp.toPx())) }
}

/**
 * Kaydırmanın üstünde yüzen kenar çubuğunun zemini. Ekranın kenarında neredeyse opak (yarı saydam düğmeler okunur kalsın),
 * çubuğun iç kenarına doğru saydamlaşır; kayan içerik çubuğun altına yumuşakça girer, düz şerit ve sert çizgi oluşmaz.
 */
private fun Modifier.edgeFade(atTop: Boolean): Modifier = this.drawBehind {
    val bg = Tokens.Color.bg
    val stops = arrayOf(0f to bg.copy(alpha = 0.97f), 0.72f to bg.copy(alpha = 0.92f), 1f to bg.copy(alpha = 0f))
    drawRect(if (atTop) Brush.verticalGradient(*stops, startY = 0f, endY = size.height)
        else Brush.verticalGradient(*stops, startY = size.height, endY = 0f))
}

@Composable
fun BodyText(text: String, color: Color = Tokens.Color.secondary, align: TextAlign? = null) =
    Text(text, style = Tokens.Type.body, color = color, textAlign = align)

/** Geniş kartın içindeki 52 yükseklikli satır (ayarlar, profil); bir yere götüren satırın sonunda `›` durur. */
@Composable
fun RowItem(title: String, value: String? = null, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Tokens.Control.row)
            .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it }
            .padding(vertical = Tokens.Space.inline),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.micro)) {
            Text(title, style = Tokens.Type.headline, color = Tokens.Color.text)
            value?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary) }
        }
        trailing?.invoke()
        if (onClick != null) Chevron()
    }
}
