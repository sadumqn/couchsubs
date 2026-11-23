// SPDX-License-Identifier: AGPL-3.0-only
// Perde tasarım dili, Android karşılığı (iPhone: mac/CouchSubs/UI/Yeni/Perde.swift + couchsubs-ios/.../PerdePhone.swift;
// aynı adlar ve ölçüler). İçerik: dokunsal geri bildirim, cam (e3), canlı nabız, durum hapı, bilgi/uyarı/hata kutusu,
// çubuk yükleyici, arama halkası, ilerleme çubuğu, adım çizelgesi, başarı anı, altyazı plakası, perde önizlemesi,
// tipografik oyun kapağı + raf + kapak yığını, simge karesi, TV kartı, ortam ışığı ve projeksiyon ışığı.
// Sürekli animasyonlar hareket kapısına (motionGate) bağlıdır: çeviri sürerken, uygulama arka plandayken, sistemde
// "Animasyonları kaldır" açıkken ve Ayarlar › Geçiş Animasyonları kapalıyken durağan tek kare çizilir.
package com.couchsubs.mobile.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeChild
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// MARK: Dokunsal geri bildirim

/**
 * Üç dokunsal geri bildirim (iPhone Haptics): seçim (sekme, seçici, anahtar), başarı (Eşleşti, Paket Kuruldu, Kurulum
 * Tamam), hata; ana düğmede hafif dokunuş. Android 11+'da sistemin onay/ret titreşimleri, öncesinde en yakın karşılığı.
 */
object Haptics {
    fun selection(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK)
    }

    fun success(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
    }

    fun error(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    }

    fun primary(view: View) {
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 27) HapticFeedbackConstants.KEYBOARD_TAP else HapticFeedbackConstants.VIRTUAL_KEY)
    }
}

// MARK: Cam (e3)

/** Cam katmanın bulanıklığı: tasarim.json › elevation.e3 (blur 24). */
private val GLASS_BLUR = 24.dp

/**
 * e3 · cam: yalnız katmanlar (sekme çubuğu, üst çubuk düğmeleri, perde hapları, sheet). Android 12+'da arkadaki içerik
 * RenderEffect ile bulanıklaşır ([haze]); öncesinde (ya da bulanıklaştırılacak içerik yokken) yarı saydam cam rengi ve
 * altında koyu degrade yedeği. Kıl çizgi + koyu temada üst kenar parlaması.
 */
fun Modifier.glass(shape: Shape, haze: HazeState? = null): Modifier {
    val glass = Tokens.Color.glass
    val dark = Tokens.dark
    val base = if (haze != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        this.clip(shape).hazeChild(haze, HazeStyle(backgroundColor = Tokens.Color.bg, tint = HazeTint(glass), blurRadius = GLASS_BLUR,
            noiseFactor = 0f))
    } else {
        // Yedek: cam rengi biraz daha opak + alttan koyulaşan degrade (bulanıklık olmadan da okunur).
        this.clip(shape).background(Tokens.Color.bg.copy(alpha = if (dark) 0.78f else 0.82f), shape)
            .background(Brush.verticalGradient(listOf(glass, Tokens.Color.bg.copy(alpha = 0.92f))), shape)
    }
    return base.border(1.dp, Tokens.Color.glassBorder, shape).topHighlight(shape)
}

// MARK: Canlı nokta

/** Canlı/çalışıyor noktası: 1,6 sn'de bir dışa yayılıp sönen halka (nabız). Hareket kapısı kapalıyken sabit nokta. */
@Composable
fun PulseDot(color: Color = Tokens.Color.liveDot, size: Dp = 8.dp) {
    val gate = motionGate()
    Box(Modifier.size(size).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (gate.live) {
            val transition = rememberInfiniteTransition(label = "pulse")
            val phase by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(DesignTokens.Motion.livePulse, easing = LinearEasing),
                RepeatMode.Restart), label = "phase")
            val ring = 6.dp
            Canvas(Modifier.size(size)) {
                // 1,6 sn'nin ilk %70'inde halka büyür ve söner, kalanında durur.
                val p = (phase / 0.7f).coerceAtMost(1f)
                val eased = 1 - (1 - p) * (1 - p)
                val radius = this.size.minDimension / 2 + ring.toPx() * eased
                drawCircle(color.copy(alpha = 0.55f * (1 - eased)), radius = radius)
                drawCircle(color)
            }
        } else Box(Modifier.size(size).background(color, CircleShape))
    }
}

// MARK: Durum hapı

enum class ChipTone { OK, LIVE, AMBER, INFO, MUTED, GLASS }

/** Durum hapı: renk + nokta/simge + yazı birlikte (durum rengi tek başına anlam taşımaz). Canlı tonunda nokta nabız atar. */
@Composable
fun StatusChip(text: String, tone: ChipTone = ChipTone.MUTED, dot: Boolean = true, icon: ImageVector? = null, modifier: Modifier = Modifier) {
    val c = Tokens.Color
    val foreground = when (tone) {
        ChipTone.OK -> c.successText
        ChipTone.LIVE -> c.liveText
        ChipTone.AMBER -> c.accentText
        ChipTone.INFO -> c.infoText
        ChipTone.MUTED -> c.secondary
        ChipTone.GLASS -> Color(0xFFF3EEE4)
    }
    val fill = when (tone) {
        ChipTone.OK -> c.successSoft
        ChipTone.LIVE -> c.liveSoft
        ChipTone.AMBER -> c.accentSoft
        ChipTone.INFO -> c.infoSoft
        ChipTone.MUTED -> c.field
        ChipTone.GLASS -> Color.Black.copy(alpha = 0.55f)
    }
    Row(
        modifier.heightIn(min = 26.dp).background(fill, CircleShape)
            .then(if (tone == ChipTone.GLASS) Modifier.border(1.dp, Color.White.copy(alpha = 0.10f), CircleShape) else Modifier)
            .padding(horizontal = 10.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) { },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DesignTokens.Space.unitHint.dp),
    ) {
        when {
            icon != null -> Icon(icon, null, tint = foreground, modifier = Modifier.size(12.dp))
            dot && tone == ChipTone.LIVE -> PulseDot(c.liveDot, 7.dp)
            dot -> Box(Modifier.size(7.dp).background(foreground, CircleShape))
        }
        Text(text, style = Tokens.Type.small.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"), color = foreground,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: Bilgi / uyarı / hata kutusu

enum class NoticeTone { INFO, WARNING, ERROR, SUCCESS }

/**
 * Bilgi, uyarı, hata ya da başarı kutusu: tonlu yumuşak zemin, kutuyu köşe yarıçapıyla komple saran ince (1 dp) renkli
 * kenarlık, solda simge; isteğe bağlı kalın başlık, metin ve altta düğmeler.
 */
@Composable
fun NoticeBox(text: String, tone: NoticeTone = NoticeTone.WARNING, title: String? = null, modifier: Modifier = Modifier,
              actions: (@Composable RowScope.() -> Unit)? = null) {
    val c = Tokens.Color
    val shape = RoundedCornerShape(Tokens.Radius.tileSmall)
    val tint = when (tone) {
        NoticeTone.INFO -> c.infoText
        NoticeTone.WARNING -> c.accentText
        NoticeTone.ERROR -> c.liveText
        NoticeTone.SUCCESS -> c.successText
    }
    val soft = when (tone) {
        NoticeTone.INFO -> c.infoSoft
        NoticeTone.WARNING -> c.accentSoft
        NoticeTone.ERROR -> c.liveSoft
        NoticeTone.SUCCESS -> c.successSoft
    }
    val ring = when (tone) {
        NoticeTone.INFO -> c.info.copy(alpha = 0.45f)
        NoticeTone.WARNING -> c.accentRing
        NoticeTone.ERROR -> c.liveRing
        NoticeTone.SUCCESS -> c.successRing
    }
    val icon = when (tone) {
        NoticeTone.INFO -> Icons.Filled.Info
        NoticeTone.WARNING -> Icons.Filled.Warning
        NoticeTone.ERROR -> Icons.Filled.Warning
        NoticeTone.SUCCESS -> Icons.Filled.CheckCircle
    }
    Row(
        modifier.fillMaxWidth().background(soft, shape).border(1.dp, ring, shape)
            .padding(horizontal = Tokens.Space.cards, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.padding(top = 1.dp).size(16.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.titleToBody)) {
            title?.let { Text(it, style = Tokens.Type.headline, color = if (tone == NoticeTone.ERROR) c.liveText else c.text) }
            Text(text, style = Tokens.Type.caption, color = if (title == null) c.text else c.secondary)
            if (actions != null) Row(Modifier.padding(top = Tokens.Space.hair), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline),
                verticalAlignment = Alignment.CenterVertically, content = actions)
        }
    }
}

// MARK: Yükleyiciler

/** Çubuk yükleyici: logodaki iki amber altyazı çubuğu sırayla daralıp genişler (1,2 sn). Kapı kapalıyken durağan. */
@Composable
fun BarsLoader(scale: Float = 1f, color: Color = Tokens.Color.accent) {
    val gate = motionGate()
    val period = 1200
    val squeeze: (Int) -> Float = if (gate.ambient) {
        val transition = rememberInfiniteTransition(label = "bars")
        val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(period, easing = LinearEasing)), label = "t");
        { index ->
            val local = ((t + if (index == 0) 0f else 0.85f) % 1f)
            val wave = (1 - cos(local * 2 * PI).toFloat()) / 2
            1f - 0.55f * wave
        }
    } else { _ -> 1f }
    Column(Modifier.width((18 * scale).dp).height((11 * scale).dp).clearAndSetSemantics { },
        verticalArrangement = Arrangement.spacedBy((3 * scale).dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.width((18 * scale).dp).height((4 * scale).dp).graphicsLayer { scaleX = squeeze(0) }.background(color, CircleShape))
        Box(Modifier.width((12 * scale).dp).height((4 * scale).dp).graphicsLayer { scaleX = squeeze(1) }.background(color, CircleShape))
    }
}

/**
 * Arama halkası dalgası: merkezdeki ışımalı amber noktadan üç halka 0,8 sn arayla dışa yayılır (2,4 sn). Kapı
 * kapalıyken tek durağan halka.
 */
@Composable
fun SearchRings(size: Dp = 56.dp) {
    val gate = motionGate()
    val amber = Tokens.Color.accent
    val glow = Tokens.Color.accentGlow
    Box(Modifier.size(size).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (gate.ambient) {
            val transition = rememberInfiniteTransition(label = "rings")
            val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(2400, easing = LinearEasing)), label = "t")
            Canvas(Modifier.size(size)) {
                for (index in 0 until 3) {
                    val local = (t + index / 3f) % 1f
                    val eased = PerdeEasing.enter.transform(local)
                    val scale = 0.3f + 0.95f * eased
                    drawCircle(amber.copy(alpha = 0.9f * (1 - eased)), radius = this.size.minDimension / 2 * scale, style = Stroke(2.dp.toPx()))
                }
            }
        } else Canvas(Modifier.size(size)) {
            drawCircle(amber.copy(alpha = 0.5f), radius = this.size.minDimension / 2 * 0.82f - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
        }
        val dot = max(size.value - 36f, 6f).dp
        Box(Modifier.size(dot).shadow(6.dp, CircleShape, ambientColor = glow, spotColor = glow).background(amber, CircleShape))
    }
}

// MARK: İlerleme çubuğu

/** İlerleme çubuğu: 8 dp iz, amber degrade dolgu + ışıma; sürerken dolgunun üstünden 1,8 sn'de bir ışık geçer. */
@Composable
fun ProgressBar(value: Float, running: Boolean = true, modifier: Modifier = Modifier) {
    val gate = motionGate()
    val c = Tokens.Color
    val fraction = value.coerceIn(0f, 1f)
    val sheen = if (running && gate.ambient) {
        val transition = rememberInfiniteTransition(label = "sheen")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1800, easing = LinearEasing)), label = "x").value
    } else null
    Canvas(modifier.fillMaxWidth().height(8.dp).semantics { contentDescription = "%${(fraction * 100).toInt()}" }) {
        val radius = androidx.compose.ui.geometry.CornerRadius(size.height / 2)
        drawRoundRect(c.field, cornerRadius = radius)
        val width = size.width * fraction
        if (width > 0) {
            drawRoundRect(Brush.horizontalGradient(listOf(c.accent, c.accentHi), endX = width), size = Size(width, size.height), cornerRadius = radius)
            if (sheen != null) {
                val band = max(width * 0.6f, 24.dp.toPx())
                val x = (sheen * 2 - 1) * width
                drawRoundRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.55f), Color.Transparent),
                    startX = x, endX = x + band), topLeft = Offset(0f, 0f), size = Size(width, size.height), cornerRadius = radius)
            }
        }
    }
}

// MARK: Adım çizelgesi

enum class StepPhase { DONE, CURRENT, TODO }

data class TimelineStep(val title: String, val phase: StepPhase, val detail: String? = null)

/**
 * Adım çizelgesi: biten adım amber dolu + tik (çizgisi amber), şimdiki adım yükseltilmiş + amber halka ve ışıma (içinde
 * çubuk yükleyici), sıradaki soluk. Tıklanmaz; seçenek gibi görünmez.
 */
@Composable
fun StepTimeline(steps: List<TimelineStep>, modifier: Modifier = Modifier) {
    val c = Tokens.Color
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) { }) {
        steps.forEachIndexed { index, step ->
            val last = index == steps.lastIndex
            Row(
                Modifier.fillMaxWidth().drawBehind {
                    if (!last) drawLine(if (step.phase == StepPhase.DONE) c.accent else c.borderStrong,
                        Offset(11.dp.toPx(), 26.dp.toPx()), Offset(11.dp.toPx(), size.height - 2.dp.toPx()), strokeWidth = 2.dp.toPx())
                }.padding(bottom = if (last) 0.dp else Tokens.Space.cards),
                horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
            ) {
                Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
                    when (step.phase) {
                        StepPhase.DONE -> {
                            Box(Modifier.size(22.dp).background(c.accent, CircleShape))
                            Icon(Icons.Filled.Check, null, tint = c.onAccent, modifier = Modifier.size(13.dp))
                        }
                        StepPhase.CURRENT -> {
                            Box(Modifier.size(22.dp).shadow(6.dp, CircleShape, ambientColor = c.accentGlow, spotColor = c.accentGlow)
                                .background(c.raised, CircleShape).border(2.dp, c.accent, CircleShape))
                            BarsLoader(0.6f)
                        }
                        StepPhase.TODO -> Box(Modifier.size(22.dp).background(c.field, CircleShape))
                    }
                }
                Column(Modifier.weight(1f).padding(top = Tokens.Space.micro), verticalArrangement = Arrangement.spacedBy(Tokens.Space.micro)) {
                    Text(step.title, style = if (step.phase == StepPhase.CURRENT) Tokens.Type.headline else Tokens.Type.body,
                        color = if (step.phase == StepPhase.TODO) c.tertiary else c.text)
                    step.detail?.let { Text(it, style = Tokens.Type.muted, color = c.secondary) }
                }
            }
        }
    }
}

// MARK: Başarı anı

/** Başarı anı süresi (ms; tasarim.json › motion.celebrate 600 + söne). */
const val CELEBRATION_MS = 1000L

/**
 * Başarı anı (Eşleşti, Paket Kuruldu, Kurulum Tamam): arkada amber ışınlar bir kez döner ve söner, ortadaki amber
 * yuvarlakta tik yayla oturur; başarı titreşimi. Hepsi en çok 1 sn. Hareket azaltılmışken (ya da çeviri sürerken)
 * yalnız tik. Yeniden oynatmak için çağıran `key(...)` değiştirir.
 */
@Composable
fun Celebration(size: Dp = 64.dp) {
    val gate = motionGate()
    val view = LocalView.current
    val seat = remember { Animatable(if (gate.reduced) 1f else 0f) }
    var elapsed by remember { mutableLongStateOf(0L) }
    val rays = gate.ambient
    LaunchedEffect(Unit) {
        Haptics.success(view)
        if (!gate.reduced) seat.animateTo(1f, tween(DesignTokens.Motion.celebrate, easing = PerdeEasing.spring))
    }
    if (rays) LaunchedEffect(Unit) {
        val start = withFrameMillis { it }
        while (elapsed < CELEBRATION_MS) {
            // En çok 30 kare/sn.
            withFrameMillis { elapsed = it - start }
            delay(33)
        }
    }
    val amber = Tokens.Color.accent
    val soft = Tokens.Color.accentSoft
    val onAmber = Tokens.Color.onAccent
    Box(Modifier.size(size * 1.6f).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (rays && elapsed < CELEBRATION_MS) Canvas(Modifier.size(size * 3.2f)) {
            val t = elapsed / 1000f
            val rotate = t / 12f * 2 * PI.toFloat()
            val fadeIn = min(t / 0.2f, 1f)
            val fadeOut = if (t > 0.7f) max(0f, (1f - t) / 0.3f) else 1f
            val alpha = 0.22f * fadeIn * fadeOut
            if (alpha > 0f) {
                val center = Offset(this.size.width / 2, this.size.height / 2)
                val radius = this.size.minDimension / 2
                val path = Path()
                for (index in 0 until 15) {
                    val a = rotate + index * 24f * PI.toFloat() / 180f
                    val b = a + 8f * PI.toFloat() / 180f
                    path.moveTo(center.x, center.y)
                    path.lineTo(center.x + radius * cos(a), center.y + radius * sin(a))
                    path.lineTo(center.x + radius * cos(b), center.y + radius * sin(b))
                    path.close()
                }
                drawPath(path, Brush.radialGradient(0.25f to amber.copy(alpha = alpha), 1f to amber.copy(alpha = 0f), center = center, radius = radius))
            }
        }
        Box(Modifier.size(size + 16.dp).background(soft, CircleShape))
        Box(Modifier.size(size).background(Brush.linearGradient(listOf(Color(0xFFFFD27A), Color(0xFFF0A92C))), CircleShape),
            contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Check, null, tint = onAmber, modifier = Modifier.size(size * 0.5f).graphicsLayer {
                scaleX = 0.3f + 0.7f * seat.value
                scaleY = 0.3f + 0.7f * seat.value
                alpha = seat.value.coerceIn(0f, 1f)
            })
        }
    }
}

/** Başarı anı kartı: başarı anı + başlık + kısa özet. */
@Composable
fun SuccessMoment(title: String, message: String? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) { }, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Celebration()
        Text(title, style = Tokens.Type.h3, color = Tokens.Color.text, textAlign = TextAlign.Center)
        message?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary, textAlign = TextAlign.Center) }
    }
}

/** Ekranın üstünde kısa başarı anı (cam kartta): Eşleşti, Paket Kuruldu. Çağıran gösterir ve süre dolunca kaldırır. */
@Composable
fun SuccessOverlay(title: String, message: String? = null) {
    Box(Modifier.fillMaxSize().background(Tokens.Color.scrim.copy(alpha = Tokens.Color.scrim.alpha * 0.5f))
        .clickable(enabled = false) { }, contentAlignment = Alignment.Center) {
        val shape = RoundedCornerShape(Tokens.Radius.tile)
        Column(Modifier.widthIn(max = 300.dp).padding(Tokens.Space.screen).glass(shape).padding(Tokens.Space.unit),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            Celebration(72.dp)
            Text(title, style = Tokens.Type.h3, color = Tokens.Color.text, textAlign = TextAlign.Center)
            message?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary, textAlign = TextAlign.Center) }
        }
    }
}

// MARK: Altyazı plakası ve perde önizlemesi

/** Altyazı plakası: her temada aynı koyu yarı saydam plaka, sıcak beyaz yarı kalın yazı, konuşan adı renkli. */
@Composable
fun SubtitlePlate(line: String, speaker: String? = null, speakerColor: Color = Tokens.Color.accent, size: Float = 17f,
                  modifier: Modifier = Modifier) {
    Text(
        buildAnnotatedString {
            speaker?.let { withStyle(SpanStyle(color = speakerColor, fontWeight = FontWeight.Bold)) { append("$it ") } }
            withStyle(SpanStyle(color = Tokens.Color.subtitleText)) { append(line) }
        },
        style = Tokens.Type.body.copy(fontSize = size.sp, lineHeight = (size + 5).sp, fontWeight = FontWeight.SemiBold),
        textAlign = TextAlign.Center,
        modifier = modifier.shadow(9.dp, RoundedCornerShape(Tokens.Radius.small), ambientColor = Color.Black.copy(alpha = 0.35f))
            .background(Tokens.Color.subtitlePlate, RoundedCornerShape(Tokens.Radius.small))
            .padding(horizontal = Tokens.Space.gap, vertical = DesignTokens.Space.unitHint.dp),
    )
}

/**
 * Perde (oyun görüntüsü/TV önizlemesi): 16:9, 20 köşe, sahne (görüntü yoksa sıcak sahne degradesi), isteğe bağlı kesikli
 * amber "Okunan Alan", altta altyazı plakası. [overlay] sağ üst haplar için.
 */
@Composable
fun PerdePreview(
    modifier: Modifier = Modifier, image: ImageBitmap? = null, line: String? = null, speaker: String? = null,
    speakerColor: Color = Tokens.Color.accent, textSize: Float = 15f, areaLabel: String? = null,
    overlay: (@Composable () -> Unit)? = null,
) {
    val shape = RoundedCornerShape(Tokens.Radius.preview)
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(Color(0xFF0B0B0D))) {
        if (image != null) Image(image, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        else PerdeScene()
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.35f))))
        val h = maxHeight
        val amber = Tokens.Color.accent
        if (areaLabel != null) {
            val areaHeight = max(h.value * 0.2f, 40f).dp
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = h * 0.05f).fillMaxWidth(0.76f).height(areaHeight)
                .drawBehind {
                    drawRoundRect(amber.copy(alpha = 0.7f), style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(Tokens.Radius.control.toPx()))
                }) {
                Text(areaLabel, style = Tokens.Type.small.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold), color = Tokens.Color.onAccent,
                    modifier = Modifier.offset(x = 10.dp, y = (-11).dp).background(amber, CircleShape).padding(horizontal = 9.dp, vertical = 3.dp))
            }
        }
        line?.let {
            SubtitlePlate(it, speaker, speakerColor, textSize, Modifier.align(Alignment.BottomCenter)
                .padding(horizontal = Tokens.Space.cards).padding(bottom = max(h.value * 0.05f, 8f).dp))
        }
        overlay?.let { Box(Modifier.align(Alignment.TopEnd).padding(Tokens.Space.gap)) { it() } }
        Box(Modifier.fillMaxSize().border(1.dp, Color.White.copy(alpha = 0.06f), shape))
    }
}

/**
 * Görüntü gelmeden önceki sahne (iPhone DSPerdeScene): özgün, soyut sinematik manzara (telifli görsel yok, tamamıyla
 * çizim). Alacakaranlık göğü, ufukta batan güneş ve göğe vuran ışık hüzmeleri, katman katman tepeler, ufka koşan yol ve
 * ince amber ufuk çizgisi. Durağan (hareket kapısına yük getirmez).
 */
@Composable
fun PerdeScene() {
    val amber = Tokens.Color.accent
    Canvas(Modifier.fillMaxSize().clipToBounds()) {
        val w = size.width
        val h = size.height
        val horizon = h * 0.6f
        val sunX = w * 0.66f
        // Gök: üstte gece mavisi, ufka doğru kızıl-amber.
        drawRect(Brush.verticalGradient(0f to Color(0xFF11141F), 0.36f to Color(0xFF302630), 0.52f to Color(0xFF9E543B),
            0.62f to Color(0xFFEF9C4A), 1f to Color(0xFFEF9C4A)))
        // Işık hüzmeleri: güneşten göğe yelpaze.
        val beams = Path()
        for ((from, to) in listOf(-0.8f to -0.66f, -0.44f to -0.33f, -0.1f to 0f, 0.2f to 0.28f, 0.52f to 0.66f)) {
            beams.moveTo(sunX, horizon)
            beams.lineTo(sunX + w * from, 0f)
            beams.lineTo(sunX + w * to, 0f)
            beams.close()
        }
        drawPath(beams, Brush.verticalGradient(listOf(Color.Transparent, Color(0xFFFFD999).copy(alpha = 0.2f)), startY = 0f, endY = horizon))
        // Güneş ve hâlesi.
        drawRect(Brush.radialGradient(0f to Color(0xFFFFC778).copy(alpha = 0.8f), 0.5f to Color(0xFFF28040).copy(alpha = 0.22f),
            1f to Color.Transparent, center = Offset(sunX, horizon), radius = max(w, h) * 0.42f))
        drawCircle(Color(0xFFFFE6B8), radius = h * 0.08f, center = Offset(sunX, horizon))
        // Uzak ve yakın tepeler (güneşin altını örter).
        fun ridge(base: Float, amplitude: Float, phase: Float, waves: Float): Path = Path().apply {
            moveTo(0f, h)
            for (index in 0..48) {
                val t = index / 48f
                val wave = 0.6f * sin(t * PI.toFloat() * waves + phase) + 0.4f * sin(t * PI.toFloat() * waves * 2.7f + phase * 1.7f)
                lineTo(w * t, base - amplitude * wave - amplitude * 0.3f)
            }
            lineTo(w, h)
            close()
        }
        drawPath(ridge(horizon, h * 0.07f, 0.2f, 2.3f), Color(0xFF3B2730).copy(alpha = 0.92f))
        drawPath(ridge(horizon + h * 0.035f, h * 0.05f, 1.4f, 3.1f), Color(0xFF1F171E))
        val ground = horizon + h * 0.05f
        drawRect(Brush.verticalGradient(listOf(Color(0xFF1F171E), Color(0xFF09090B)), startY = ground, endY = h), Offset(0f, ground),
            Size(w, h - ground))
        // Ufka koşan yol (perspektif) ve ince amber ufuk çizgisi.
        val road = Path().apply {
            moveTo(sunX - 1.5f, ground)
            lineTo(sunX + 1.5f, ground)
            lineTo(sunX + w * 0.2f, h)
            lineTo(sunX - w * 0.34f, h)
            close()
        }
        drawPath(road, Brush.verticalGradient(listOf(amber.copy(alpha = 0.3f), amber.copy(alpha = 0.04f)), startY = ground, endY = h))
        drawRect(Brush.horizontalGradient(listOf(Color.Transparent, amber.copy(alpha = 0.75f), Color.Transparent)), Offset(0f, ground),
            Size(w, 1.dp.toPx()))
    }
}

// MARK: Oyun kapağı (tipografik)

/** Kapak paletleri (iPhone DSCoverArt.palettes ile aynı sıra): üst, alt, ışık, yazı. Son palet (gri) kapak yığınında kullanılmaz. */
private val coverPalettes = listOf(
    listOf(0xFFF49944, 0xFF992828, 0xFFFFD999, 0xFFFFF4E2),
    listOf(0xFFE03E65, 0xFF3F123F, 0xFFFF9DB0, 0xFFFFECEF),
    listOf(0xFF346ED9, 0xFF0F1948, 0xFF97CAFF, 0xFFE6F2FF),
    listOf(0xFF23AEA6, 0xFF092F3B, 0xFF96F7E4, 0xFFE3FFF9),
    listOf(0xFF8955E8, 0xFF1F134A, 0xFFCAB0FF, 0xFFF4EFFF),
    listOf(0xFFF5BF3D, 0xFFB54F13, 0xFFFFF0B0, 0xFF2A1609),
    listOf(0xFFEF664A, 0xFF511868, 0xFFFFBF96, 0xFFFFEFE8),
    listOf(0xFF6B7482, 0xFF1C1F26, 0xFFCCD1DB, 0xFFEFF1F4),
).map { palette -> palette.map { Color(it) } }

/** Kararlı karma (iPhone DSCoverArt.paletteIndex ile aynı: 7 tohum, ×31 + karakter kodu, 32 bit taşma). */
fun coverPaletteIndex(seed: String): Int {
    var sum = 7L
    seed.codePoints().forEach { sum = (sum * 31 + it) and 0xFFFFFFFFL }
    return (sum % coverPalettes.size).toInt()
}

private val monogramSkip = setOf("the", "of", "a", "an", "and", "to", "in", "on", "for")

/** Kesme işaretli ekler ("Assassin's" → "s") sözcük sayılmaz. */
private fun coverWords(title: String): List<String> =
    title.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        .filter { it.length > 1 || it.first().isUpperCase() || it.first().isDigit() }

private fun isRoman(word: String) = word.isNotEmpty() && word.length <= 4 && word.all { it in "IVX" }
private fun isNumeral(word: String) = word.all { it.isDigit() } || isRoman(word)

/**
 * Oyunun kısaltması (iPhone DSCoverArt.monogram; yalnız harf, en çok 3): baştaki büyük harf kısaltma (GTA V → GTA), yoksa
 * en çok üç anlamlı sözcüğün baş harfi (Red Dead Redemption 2 → RDR); tek sözcük → ilk iki harf (Mafia → Ma).
 */
fun monogram(title: String): String {
    val words = coverWords(title)
    val first = words.firstOrNull() ?: return "?"
    val english = java.util.Locale.US
    if (first.length in 2..4 && first == first.uppercase(english) && first.all { it.isLetter() } && !isRoman(first)) return first.take(3)
    val significant = words.filter { it.lowercase(english) !in monogramSkip && !isNumeral(it) }
    if (significant.size >= 2) return significant.take(3).joinToString("") { it.take(1).uppercase(english) }
    val word = significant.firstOrNull() ?: first
    return word.take(1).uppercase(english) + word.drop(1).take(1).lowercase(english)
}

/** Adın sonundaki sayı ya da Roma rakamı (Red Dead Redemption 2 → 2, Grand Theft Auto VI → VI); yoksa null. */
fun coverNumeral(title: String): String? {
    val words = coverWords(title)
    val last = words.lastOrNull() ?: return null
    return last.takeIf { words.size > 1 && isNumeral(it) && it.length <= 4 }
}

/**
 * Tipografik oyun kapağı (iPhone DSCoverArt/DSTypeCover): gerçek kapak görseli ya da logo yok (telif ve mağaza riski).
 * Oyuna özgü kararlı degrade, köşe ışığı, çapraz ışık bandı ve oyunun kısaltması iri, ağır yazıyla; sıra numarası
 * (V, VI, 2) yanında küçük. Küçük boyda (kapak yığını) yalnız kısaltma ortada.
 */
@Composable
fun CoverArt(seed: String, modifier: Modifier = Modifier) {
    val (top, bottom, light, ink) = coverPalettes[coverPaletteIndex(seed)]
    val mark = monogram(seed)
    BoxWithConstraints(modifier.clipToBounds().drawBehind {
        val span = max(size.width, size.height)
        drawRect(Brush.linearGradient(listOf(top, bottom), start = Offset(size.width * 0.15f, 0f), end = Offset(size.width * 0.85f, size.height)))
        drawRect(Brush.radialGradient(listOf(light.copy(alpha = 0.7f), Color.Transparent), center = Offset(size.width * 0.9f, size.height * 0.05f),
            radius = span * 0.7f))
        // Çapraz ışık bandı (28°).
        rotate(28f, Offset(size.width * 0.64f, size.height * 0.4f)) {
            val band = span * 0.3f
            drawRect(Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = 0.16f), Color.White.copy(alpha = 0f)),
                startX = size.width * 0.64f - band / 2, endX = size.width * 0.64f + band / 2),
                Offset(size.width * 0.64f - band / 2, size.height * 0.4f - span * 1.1f), Size(band, span * 2.2f))
        }
    }.clearAndSetSemantics { }) {
        val w = maxWidth
        val h = maxHeight
        val density = LocalDensity.current
        if (min(w.value, h.value) < 72f) {
            Text(mark, style = TextStyle(fontSize = with(density) { (min(w.value, h.value).dp * (if (mark.length > 2) 0.34f else 0.44f)).toSp() },
                fontWeight = FontWeight.ExtraBold), color = ink, maxLines = 1, softWrap = false,
                modifier = Modifier.align(Alignment.Center))
        } else {
            // İri kısaltma üst bölgede; altında kısa çizgi ve sıra numarası. Başlık (GameCover) alttaki scrim'in üstünde kalır.
            // Kısaltma kapağa sığmazsa küçülür (iPhone minimumScaleFactor 0,5): ağır büyük harf genişliği yazı boyunun ~0,72 katı.
            val font = (w * if (mark.length > 2) 0.42f else 0.56f).coerceAtMost(w * 0.85f / (mark.length * 0.72f)).coerceAtLeast(w * 0.21f)
            Column(Modifier.padding(start = w * 0.09f, end = w * 0.06f, top = h * 0.1f), verticalArrangement = Arrangement.spacedBy(font * 0.1f)) {
                Text(mark, style = TextStyle(fontSize = with(density) { font.toSp() }, lineHeight = with(density) { (font * 1.05f).toSp() },
                    fontWeight = FontWeight.Black, letterSpacing = with(density) { (-font * 0.03f).toSp() },
                    shadow = androidx.compose.ui.graphics.Shadow(bottom.copy(alpha = 0.5f), Offset(0f, with(density) { (w * 0.015f).toPx() }),
                        with(density) { (w * 0.03f).toPx() })), color = ink.copy(alpha = 0.94f), maxLines = 1, softWrap = false)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(w * 0.04f)) {
                    Box(Modifier.size(w * 0.2f, max(2f, w.value * 0.02f).dp).background(ink.copy(alpha = 0.75f), CircleShape))
                    coverNumeral(seed)?.let {
                        Text(it, style = TextStyle(fontSize = with(density) { (w * 0.13f).toSp() }, fontWeight = FontWeight.ExtraBold),
                            color = ink.copy(alpha = 0.9f), maxLines = 1)
                    }
                }
            }
        }
    }
}

/**
 * Oyun kapağı kartı: 3:4 kapak, alttan scrim üstünde kalın beyaz başlık, sol üstte isteğe bağlı cam durum hapı. Seçili
 * (oynanan) kapakta amber halka ve arkasında kapağın renginden durağan ışıma.
 */
@Composable
fun GameCover(title: String, status: String? = null, selected: Boolean = false,
              width: Dp = DesignTokens.Size.coverWidthRail.dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(Tokens.Radius.cover)
    val height = width / DesignTokens.Size.coverAspect
    val glow = coverPalettes[coverPaletteIndex(title)][0]
    Box(modifier.size(width, height)) {
        if (selected) Box(Modifier.size(width, height).padding(horizontal = width * 0.08f).offset(y = height * 0.11f)
            .shadow(24.dp, RoundedCornerShape(30.dp), ambientColor = glow, spotColor = glow))
        Box(Modifier.size(width, height).clip(shape)) {
            CoverArt(title, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Tokens.Color.coverScrim)))
            Text(title, style = Tokens.Type.label.copy(fontSize = if (width < 110.dp) 12.sp else 14.sp, fontWeight = FontWeight.Bold,
                lineHeight = if (width < 110.dp) 14.sp else 16.sp), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.BottomStart).padding(start = 10.dp, end = 10.dp, bottom = 9.dp))
            status?.let { StatusChip(it, ChipTone.GLASS, dot = false, modifier = Modifier.padding(6.dp).scale(0.85f)) }
        }
        if (selected) Box(Modifier.size(width, height).border(2.dp, Tokens.Color.accent, shape))
    }
}

/** Kapak rafı: başlık (cümle düzeni) + sağda isteğe bağlı "Tümü", altında yatay kayan kapaklar (12 aralık). */
@Composable
fun CoverShelf(title: String, allLabel: String? = null, onAll: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = Tokens.Type.cardTitle, color = Tokens.Color.text, modifier = Modifier.weight(1f)
                .semantics { heading() })
            if (allLabel != null && onAll != null) GhostButton(allLabel, onClick = onAll)
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = Tokens.Space.gap, horizontal = Tokens.Space.hair),
            horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap), verticalAlignment = Alignment.Bottom, content = content)
    }
}

/** Paket satırındaki üç eğik küçük kapak (oyun enerjisi kapaklarda, krom nötr); üçü de farklı renkte. */
@Composable
fun CoverStack(titles: List<String>) {
    // Üç kapak birbirinden farklı renkte olsun: aynı palete düşen ad, farklı palet bulunana dek uzatılır (gri kullanılmaz).
    val used = mutableListOf(coverPalettes.size - 1)
    val shown = titles.take(3).map { title ->
        var seed = title
        repeat(12) { if (coverPaletteIndex(seed) in used) seed += " " }
        used += coverPaletteIndex(seed)
        seed
    }
    val surface = Tokens.Color.surface
    Box(Modifier.size(60.dp, 44.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        shown.forEachIndexed { index, seed ->
            val shape = RoundedCornerShape(7.dp)
            Box(Modifier.offset(x = ((index - 1) * 12).dp).rotate((index - 1) * 8f)
                .shadow(3.dp, shape).size(28.dp, 38.dp).clip(shape).border(1.5.dp, surface, shape)) {
                CoverArt(seed, Modifier.fillMaxSize())
            }
        }
    }
}

// MARK: Simge karesi, TV kartı

enum class IconTone { PEACH, OLIVE, TEAL, PLUM, SKY, AMBER, GRAY, LIVE }

/** Renkli simge karesi (ayar menüsü, liste satırı, TV kartı): degrade tonlu yuvarlak kare, beyaz simge (amberde koyu). */
@Composable
fun IconTile(icon: ImageVector, tone: IconTone = IconTone.GRAY, size: Dp = 32.dp) {
    val (top, bottom) = when (tone) {
        IconTone.PEACH -> Color(0xFFF4A27A) to Color(0xFFE07B4A)
        IconTone.OLIVE -> Color(0xFFB4BE6A) to Color(0xFF8E9A45)
        IconTone.TEAL -> Color(0xFF5CC2B7) to Color(0xFF3A9E94)
        IconTone.PLUM -> Color(0xFFB892DC) to Color(0xFF9C6CC4)
        IconTone.SKY -> Color(0xFF78AEE2) to Color(0xFF4F8FCB)
        IconTone.AMBER -> Color(0xFFFFCB63) to Color(0xFFE9A52A)
        IconTone.GRAY -> Color(0xFF8A8D96) to Color(0xFF5A5D66)
        IconTone.LIVE -> Color(0xFFF28B6B) to Color(0xFFD9542F)
    }
    Box(Modifier.size(size).background(Brush.linearGradient(listOf(top, bottom)), RoundedCornerShape(size * 0.3f)).clearAndSetSemantics { },
        contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = if (tone == IconTone.AMBER) Color(0xFF1D1E22) else Color.White, modifier = Modifier.size(size * 0.55f))
    }
}

/** Ayar menüsündeki yumuşak simge karesi (iPhone SettingsSectionRow): rengin %16'sı zemin, simge o renkte. */
@Composable
fun SoftIconTile(icon: ImageVector, color: Color, size: Dp = 32.dp) {
    Box(Modifier.size(size).background(color.copy(alpha = 0.16f), RoundedCornerShape(Tokens.Radius.inner)).clearAndSetSemantics { },
        contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color, modifier = Modifier.size(17.dp))
    }
}

/**
 * TV kartı (seçenek): simge karesi, ad + mono ayrıntı (marka · adres), sağda durum hapı. Her zaman kıl çizgi; seçiliyken
 * 2 dp amber kenar + amber yumuşak dolgu + ışıma, simge amber. Seçilince seçim titreşimi.
 */
@Composable
fun TvCard(name: String, detail: String, selected: Boolean, modifier: Modifier = Modifier, icon: ImageVector = CouchIcons.Tv,
           status: (@Composable () -> Unit)? = null, onClick: (() -> Unit)?) {
    val view = LocalView.current
    LaunchedEffect(selected) { if (selected) Haptics.selection(view) }
    Tile(modifier.fillMaxWidth(), style = if (selected) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = onClick, spacing = Tokens.Space.inline) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            IconTile(icon, if (selected) IconTone.AMBER else IconTone.GRAY, 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                Text(name, style = Tokens.Type.headline, color = Tokens.Color.text)
                Text(detail, style = Tokens.Type.mono, color = Tokens.Color.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                status?.invoke()
            }
        }
    }
}

// MARK: Ortam ışığı

/** Projeksiyon ışığı: üst kenardan düşen geniş, yumuşak amber ışık (radyal; koyuda %16, açıkta %22). Durağandır. */
@Composable
fun ProjectorLight() {
    val alpha = if (Tokens.dark) 0.16f else 0.22f
    val amber = Tokens.Color.accent
    Canvas(Modifier.fillMaxSize()) {
        // radial 120% x 70% at 50% -10%: genişliği yüksekliğinden büyük elips (ölçekle).
        val center = Offset(size.width / 2, -size.height * 0.1f)
        val rx = size.width * 1.2f * 0.6f
        val ry = size.height * 0.7f * 0.6f
        scale(1f, ry / rx, center) {
            drawCircle(Brush.radialGradient(listOf(amber.copy(alpha = alpha), amber.copy(alpha = 0f)), center = center, radius = rx), radius = rx, center = center)
        }
    }
}

/** Ortam ışığı lekeleri (iPhone DSAmbientLayers.blobs): renk, x, y, ölçek, saydamlık, kayma x, kayma y. */
private val ambientBlobs = listOf(
    AmbientBlob(0, 0.25f, 0.2f, 0.42f, 0.18f, 0.04f, 0.03f),
    AmbientBlob(1, 0.8f, 0.1f, 0.36f, 0.12f, -0.04f, 0.03f),
    AmbientBlob(2, 0.7f, 0.9f, 0.42f, 0.06f, 0.04f, -0.03f),
)

private data class AmbientBlob(val color: Int, val x: Float, val y: Float, val scale: Float, val alpha: Float, val dx: Float, val dy: Float)

/**
 * Ortam ışığı: amber, şeftali ve gök mavisi üç yumuşak leke 24 sn'lik döngüde çok yavaş süzülür (en çok 15 kare/sn);
 * kapı kapalıyken (çeviri, hareketi azalt, arka plan) durağan. Bulanıklık süzgeci yok, radyal degrade.
 */
@Composable
fun AmbientGlow(intensity: Float = 1f) {
    val gate = motionGate()
    val colors = listOf(Tokens.Color.accent, Tokens.Color.peach, Tokens.Color.sky)
    var phase by remember { mutableStateOf(0f) }
    if (gate.ambient) LaunchedEffect(Unit) {
        val start = withFrameMillis { it } - (phase * DesignTokens.Motion.ambient).toLong()
        while (true) {
            withFrameMillis { now -> phase = ((now - start) % DesignTokens.Motion.ambient) / DesignTokens.Motion.ambient.toFloat() }
            delay(1000L / 15)
        }
    }
    Canvas(Modifier.fillMaxSize()) {
        val span = max(size.width, size.height)
        // Gidiş-dönüş (autoreverse) ve yumuşak geçiş; her leke biraz farklı evrede.
        ambientBlobs.forEachIndexed { index, blob ->
            val local = (phase + index * 0.33f) % 1f
            val wave = (1 - cos(local * 2 * PI).toFloat()) / 2
            val center = Offset(size.width * (blob.x + blob.dx * wave), size.height * (blob.y + blob.dy * wave))
            val color = colors[blob.color]
            drawCircle(Brush.radialGradient(listOf(color.copy(alpha = blob.alpha * intensity), color.copy(alpha = 0f)), center = center,
                radius = span * blob.scale), radius = span * blob.scale, center = center)
        }
    }
}

// MARK: Bölüm başlığı, marka

/** Sekme kökündeki büyük sayfa başlığı (Ayarlar, Geçmiş): 28 yarı kalın, sola yaslı. */
@Composable
fun LargeTitle(title: String, modifier: Modifier = Modifier) {
    Text(title, style = Tokens.Type.display, color = Tokens.Color.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
        modifier = modifier.semantics { heading() })
}

/**
 * CouchSubs logosu, arka plansız: yalnız kanepe ve iki amber altyazı çubuğu (design/logo.svg ile aynı geometri, 640 × 464;
 * iPhone DSLogoMark).
 */
@Composable
fun LogoMark(height: Dp = 24.dp) {
    val back = Tokens.Color.logoBack
    val seat = Tokens.Color.logoSeat
    val amber = Tokens.Color.accent
    Canvas(Modifier.size(height * (640f / 464f), height).clearAndSetSemantics { }) {
        val s = size.height / 464f
        fun rect(x: Float, y: Float, w: Float, h: Float, r: Float, color: Color) = drawRoundRect(color,
            topLeft = Offset((x - 192) * s, (y - 280) * s), size = Size(w * s, h * s), cornerRadius = androidx.compose.ui.geometry.CornerRadius(r * s))
        rect(282f, 290f, 460f, 320f, 52f, back)
        rect(367f, 362f, 290f, 50f, 25f, amber)
        rect(414f, 436f, 196f, 50f, 25f, amber)
        rect(262f, 690f, 40f, 44f, 12f, seat)
        rect(722f, 690f, 40f, 44f, 12f, seat)
        rect(202f, 446f, 112f, 254f, 56f, seat)
        rect(710f, 446f, 112f, 254f, 56f, seat)
        rect(202f, 574f, 620f, 126f, 56f, seat)
    }
}

/** Logo + "CouchSubs" (ana ekranın üst satırı). */
@Composable
fun Brand() {
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "CouchSubs" }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        LogoMark(24.dp)
        Text("CouchSubs", style = Tokens.Type.headline.copy(fontWeight = FontWeight.Bold), color = Tokens.Color.text)
    }
}
