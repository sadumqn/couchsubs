// SPDX-License-Identifier: AGPL-3.0-only
// Perde denetimleri, Android karşılığı (iPhone DSComponents.swift + PerdePhone.swift; aynı ölçüler): üç sekmeli cam sekme
// çubuğu, anahtar (amber, satırın başında), kaydırıcı (çubuk kartın iç genişliğini tam kaplar), alt reklam şeridi ve
// Ayarlar'ın en üstündeki hesap kartları.
package com.couchsubs.mobile.ui

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R
import kotlinx.coroutines.delay
import org.json.JSONObject
import kotlin.math.roundToInt

// MARK: Sekmeler

/** Uygulamanın üç ana sekmesi (iPhone PhoneTab; Mac'teki üst sekmelerle aynı sıra ve ad). */
enum class PhoneTab(val title: Int) {
    HOME(R.string.tab_home), HISTORY(R.string.history), SETTINGS(R.string.settings);

    val icon: ImageVector
        get() = when (this) {
            HOME -> CouchIcons.Home
            HISTORY -> CouchIcons.Clock
            SETTINGS -> CouchIcons.Sliders
        }
}

/** Sekme düğmesine eklenecek değiştirici (kullanım turu Ayarlar sekmesinin yerini buradan ölçer). */
val LocalTabMarker = androidx.compose.runtime.compositionLocalOf<(PhoneTab) -> Modifier> { { Modifier } }

/**
 * Yüzen cam sekme çubuğu: seçili sekmede amber yumuşak hap (sekmeler arasında kayar), amber simge ve yazı. Sekme
 * değişince seçim titreşimi. Hareket azaltılmışken hap kaymaz, yalnız solar. En büyük yazı boylarında çubuk taşmaz.
 */
@Composable
fun PerdeTabBar(active: PhoneTab, select: (PhoneTab) -> Unit) {
    val view = LocalView.current
    val gate = motionGate()
    val haze = LocalHaze.current
    val shape = CircleShape
    val density = LocalDensity.current
    // Sekme yazıları sistemin en büyük yazı boyunda da çubuğu taşırmasın (iPhone: ...xxLarge sınırı).
    val capped = androidx.compose.ui.unit.Density(density.density, density.fontScale.coerceAtMost(1.3f))
    androidx.compose.runtime.CompositionLocalProvider(LocalDensity provides capped) {
        BoxWithConstraints(
            Modifier.fillMaxWidth()
                .shadow(18.dp, shape, ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.18f))
                .glass(shape, haze)
                .padding(6.dp)
                .selectableGroup(),
        ) {
            val count = PhoneTab.entries.size
            val slot = maxWidth / count
            val target = slot * active.ordinal
            val x by animateDpAsState(target, if (gate.reduced) tween(0) else tween(Tokens.Motion.medium, easing = PerdeEasing.spring), label = "pill")
            Box(Modifier.offset { IntOffset(with(this) { x.roundToPx() }, 0) }.width(slot).height(52.dp).background(Tokens.Color.accentSoft, shape))
            val marker = LocalTabMarker.current
            Row(Modifier.fillMaxWidth()) {
                PhoneTab.entries.forEach { tab ->
                    val on = tab == active
                    val color by animateColorAsState(if (on) Tokens.Color.accentText else Tokens.Color.secondary, tween(Tokens.Motion.short), label = "tab")
                    Column(
                        Modifier.weight(1f).then(marker(tab)).heightIn(min = 52.dp).clip(shape)
                            .selectable(on, role = Role.Tab) {
                                if (!on) Haptics.selection(view)
                                select(tab)
                            },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(tab.icon, null, tint = color, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.height(3.dp))
                        Text(stringResource(tab.title), style = Tokens.Type.small.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                            color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

// MARK: Anahtar

/** Anahtar: 51 × 31, açıkken amber + hafif amber ışıma (yeşil değil), beyaz gölgeli düğmecik; 250 ms kayar. */
@Composable
fun PerdeSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val gate = motionGate()
    val view = LocalView.current
    val width = DesignTokens.Size.switchWidthIOS.dp
    val height = DesignTokens.Size.switchHeightIOS.dp
    val knob = height - 4.dp
    val travel by animateDpAsState(if (checked) width - knob - 4.dp else 0.dp, perdeTween(Tokens.Motion.medium, gate), label = "knob")
    val fill by animateColorAsState(if (checked) Tokens.Color.accent else Tokens.Color.switchOff, perdeTween(Tokens.Motion.medium, gate), label = "track")
    val toggle = onCheckedChange?.let { change -> Modifier.toggleable(checked, enabled = enabled, role = Role.Switch) {
        Haptics.selection(view)
        change(it)
    } } ?: Modifier
    Box(
        modifier.size(width, height).alpha(if (enabled) 1f else 0.5f)
            .then(if (checked && enabled) Modifier.shadow(7.dp, CircleShape, ambientColor = Tokens.Color.accentGlow, spotColor = Tokens.Color.accentGlow) else Modifier)
            .background(fill, CircleShape).then(toggle).padding(2.dp),
    ) {
        Box(Modifier.offset(x = travel).size(knob).shadow(3.dp, CircleShape).background(Color.White, CircleShape))
    }
}

/**
 * Anahtar satırı (bir ayar birimi; iPhone DSSwitchRow): solda anahtar, sağında başlık ve altında açıklama; satırın tamamı
 * dokunulabilir ve ekran okuyucuda tek anahtar olarak okunur.
 */
@Composable
fun SwitchRow(title: String, note: String? = null, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val view = LocalView.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp)
            .toggleable(checked, enabled = enabled, role = Role.Switch) {
                Haptics.selection(view)
                onChange(it)
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.cards),
    ) {
        PerdeSwitch(checked, null, enabled = enabled)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DesignTokens.Space.unitHint.dp)) {
            Text(title, style = Tokens.Type.headline, color = Tokens.Color.text)
            note?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary) }
        }
    }
}

// MARK: Kaydırıcı

/** Kaydırıcının düğmeciği (beyaz, gölgeli). */
private val KNOB = 24.dp
private val TRACK = 4.dp

/**
 * Kaydırıcı: 4 dp ince iz (alan rengi), dolu kısmı amber + ışıma, 24 dp beyaz düğmecik; nokta (tick) yok. Çubuk kartın iç
 * genişliğini TAM kaplar: sol ucu başlığın ve en küçük değer etiketinin sol kenarında, sağ ucu değer yazısının ve en büyük
 * değer etiketinin sağ kenarında. Düğmeciğin merkezi çubuğun içinde kalır. Sürükleme, dokunma ve ekran okuyucunun
 * artır/azalt eylemi; adımlıysa her adımda seçim titreşimi.
 */
@Composable
fun PerdeSlider(
    value: Float, onValueChange: (Float) -> Unit, modifier: Modifier = Modifier,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f, steps: Int = 0, onValueChangeFinished: (() -> Unit)? = null,
    enabled: Boolean = true, label: String? = null,
) {
    val view = LocalView.current
    val gate = motionGate()
    val density = LocalDensity.current
    var width by remember { mutableFloatStateOf(1f) }
    var dragging by remember { mutableStateOf(false) }
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onValueChange)
    val finished by rememberUpdatedState(onValueChangeFinished)
    val span = valueRange.endInclusive - valueRange.start
    fun snap(raw: Float): Float {
        val clamped = raw.coerceIn(valueRange.start, valueRange.endInclusive)
        if (steps <= 0 || span <= 0f) return clamped
        val step = span / (steps + 1)
        return (valueRange.start + ((clamped - valueRange.start) / step).roundToInt() * step).coerceIn(valueRange.start, valueRange.endInclusive)
    }
    fun set(x: Float) {
        val fraction = (x / width.coerceAtLeast(1f)).coerceIn(0f, 1f)
        val next = snap(valueRange.start + fraction * span)
        if (next != current) {
            if (steps > 0) Haptics.selection(view)
            change(next)
        }
    }
    val fraction = if (span > 0f) ((value - valueRange.start) / span).coerceIn(0f, 1f) else 0f
    val knobScale by animateFloatAsState(if (dragging && !gate.reduced) 1.08f else 1f, tween(Tokens.Motion.short), label = "knob")
    val amber = Tokens.Color.accent
    val glow = Tokens.Color.accentGlow
    val field = Tokens.Color.field
    val border = Tokens.Color.border
    Box(
        modifier.fillMaxWidth().height(32.dp).alpha(if (enabled) 1f else 0.5f)
            .onSizeChanged { width = it.width.toFloat() }
            .then(if (!enabled) Modifier else Modifier
                .pointerInput(valueRange, steps) {
                    detectTapGestures(onTap = { set(it.x); finished?.invoke() })
                }
                .pointerInput(valueRange, steps) {
                    detectHorizontalDragGestures(
                        onDragStart = { dragging = true; set(it.x) },
                        onDragEnd = { dragging = false; finished?.invoke() },
                        onDragCancel = { dragging = false; finished?.invoke() },
                    ) { change, _ -> change.consume(); set(change.position.x) }
                })
            .semantics {
                label?.let { contentDescription = it }
                progressBarRangeInfo = ProgressBarRangeInfo(value, valueRange, steps)
                if (enabled) setProgress { target ->
                    val next = snap(target)
                    if (next != current) change(next)
                    finished?.invoke()
                    true
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val knob = KNOB.toPx()
            val track = TRACK.toPx()
            val y = size.height / 2
            val center = size.width * fraction
            val radius = CornerRadius(track / 2)
            // İz: kartın iç genişliğinin tamamı (0 … genişlik).
            drawRoundRect(field, Offset(0f, y - track / 2), Size(size.width, track), radius)
            drawRoundRect(border, Offset(0f, y - track / 2), Size(size.width, track), radius,
                style = androidx.compose.ui.graphics.drawscope.Stroke(0.5.dp.toPx()))
            if (enabled) drawRoundRect(glow, Offset(0f, y - track), Size(center, track * 2), CornerRadius(track))
            drawRoundRect(amber, Offset(0f, y - track / 2), Size(center, track), radius)
        }
        // Düğmecik yerleşimde konumlanır (ölçülen genişlik durumu beklenmez; ilk karede de doğru yerde).
        Box(Modifier.align(Alignment.CenterStart)
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
                // Merkez iz üzerinde (0 … genişlik): uçlarda düğmecik yarıçapı kadar dışarı taşar (iPhone DSSlider).
                layout(constraints.maxWidth, placeable.height) {
                    placeable.place((constraints.maxWidth * fraction - placeable.width / 2f).roundToInt(), 0)
                }
            }
            .size(KNOB).scale(knobScale)
            .shadow(4.dp, CircleShape).background(Color.White, CircleShape).border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape))
    }
}

/**
 * Kaydırıcı satırı (iPhone DSSliderRow): başlık solda, değer sağda (mono, amber); altında tam genişlikte kaydırıcı,
 * altında isteğe bağlı en küçük / en büyük değer etiketleri (çubuğun gerçek uçlarıyla hizalı) ve açıklama.
 */
@Composable
fun SliderRow(
    title: String, valueText: String, value: Float, onValueChange: (Float) -> Unit, valueRange: ClosedFloatingPointRange<Float>,
    steps: Int = 0, note: String? = null, ends: Pair<String, String>? = null, onValueChangeFinished: (() -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
        SliderHeader(title, valueText)
        Column {
            PerdeSlider(value, onValueChange, valueRange = valueRange, steps = steps, onValueChangeFinished = onValueChangeFinished, label = title)
            ends?.let { (low, high) ->
                Row(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
                    Text(low, style = Tokens.Type.small.copy(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"), color = Tokens.Color.secondary)
                    Spacer(Modifier.weight(1f))
                    Text(high, style = Tokens.Type.small.copy(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"), color = Tokens.Color.secondary,
                        textAlign = TextAlign.End)
                }
            }
        }
        note?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary) }
    }
}

// MARK: Reklam şeridi

/** Enmera'nın kendi uygulamasının reklamı (Mac, Windows ve iPhone ile aynı liste: design/yeni-arayuz/reklamlar.json). */
data class AdItem(val id: String, val title: String, val text: String, val icon: ImageBitmap?, val googlePlay: String?)

object AdCatalog {
    /** Dile göre önbellek (dil değişince yeniden okunur). */
    @Volatile private var cached: Pair<String, List<AdItem>>? = null

    /**
     * Banttaki reklamlar, uygulamanın diline göre (Türkçe değilse İngilizce). Üçüncü taraf reklam ağı, izleme ya da kişisel
     * veri yok; dokununca yalnız Google Play sayfası açılır. Dosya yoksa ya da bozuksa bant görünmez.
     */
    fun band(context: Context): List<AdItem> {
        val language = if (context.resources.configuration.locales[0].language == "tr") "tr" else "en"
        cached?.takeIf { it.first == language }?.let { return it.second }
        return load(context, language).also { cached = language to it }
    }

    private fun load(context: Context, language: String): List<AdItem> = try {
        val json = JSONObject(context.assets.open("reklamlar.json").use { String(it.readBytes(), Charsets.UTF_8) })
        val ads = json.getJSONArray("ads")
        (0 until ads.length()).map { index ->
            val ad = ads.getJSONObject(index)
            val icon = runCatching {
                context.assets.open("reklam/" + ad.getString("icon")).use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
            }.getOrNull()
            fun text(key: String) = ad.optJSONObject(key)?.let { it.optString(language).ifEmpty { it.optString("en") } } ?: ""
            AdItem(ad.getString("id"), text("title").ifEmpty { ad.getString("id") }, text("text"), icon,
                ad.optString("googlePlay").takeIf { !ad.isNull("googlePlay") && it.startsWith("https://") })
        }
    } catch (error: Exception) {
        emptyList()
    }
}

/**
 * Uygulama ve ayar sayfalarının altında sabit ince reklam şeridi (56): solda uygulama simgesi, ortada başlık + tek satır
 * açıklama, sağda Google Play düğmesi (bağlantı yoksa pasif "Yakında"), sağ üstte küçük REKLAM etiketi. Reklamlar 6 sn
 * arayla yukarı kayarak değişir. Kurulum, açılış, çeviri ve oyun görüntüsü ekranlarında yok.
 */
@Composable
fun AdBand() {
    val context = LocalContext.current
    val items = remember { AdCatalog.band(context) }
    if (items.isEmpty()) return
    val gate = motionGate()
    var index by remember { mutableIntStateOf(0) }
    if (items.size > 1 && Tokens.foreground) LaunchedEffect(items.size) {
        while (true) {
            delay(DesignTokens.Motion.adRotate.toLong())
            index = (index + 1) % items.size
        }
    }
    val shape = RoundedCornerShape(Tokens.Radius.tileSmall + 2.dp)
    val adLabel = stringResource(R.string.ad_label)
    Box(Modifier.fillMaxWidth().heightIn(min = Tokens.Control.adBand).perdeCard(shape).clip(shape)
        .semantics(mergeDescendants = false) { contentDescription = adLabel }) {
        AnimatedContent(items[index.coerceIn(0, items.lastIndex)], transitionSpec = {
            if (gate.reduced) fadeIn(tween(Tokens.Motion.reduced)) togetherWith fadeOut(tween(Tokens.Motion.reduced))
            else (fadeIn(tween(Tokens.Motion.page)) + slideInVertically(tween(Tokens.Motion.page, easing = PerdeEasing.enter)) { it / 6 }) togetherWith
                (fadeOut(tween(Tokens.Motion.page / 2)) + slideOutVertically(tween(Tokens.Motion.page / 2)) { -it / 6 })
        }, label = "ad") { ad -> AdRow(ad) }
        Text(adLabel.uppercase(java.util.Locale.forLanguageTag("tr")), style = Tokens.Type.mono.copy(fontSize = 9.sp, letterSpacing = 0.9.sp,
            fontWeight = FontWeight.SemiBold), color = Tokens.Color.tertiary,
            modifier = Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 12.dp).clearAndSetSemantics { })
    }
}

@Composable
private fun AdRow(ad: AdItem) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = Tokens.Space.gap, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        val iconShape = RoundedCornerShape(Tokens.Radius.small)
        Box(Modifier.size(40.dp).clip(iconShape).background(Tokens.Color.field).border(1.dp, Tokens.Color.border, iconShape)) {
            ad.icon?.let { Image(it, null, Modifier.fillMaxSize()) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(ad.title, style = Tokens.Type.label.copy(fontWeight = FontWeight.SemiBold), color = Tokens.Color.text, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            Text(ad.text, style = Tokens.Type.small.copy(letterSpacing = (DesignTokens.MUTED_TRACKING / 2).sp), color = Tokens.Color.secondary,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val link = ad.googlePlay
        Row(
            Modifier.padding(top = 8.dp).height(28.dp).clip(CircleShape).background(Tokens.Color.raised, CircleShape)
                .border(1.dp, Tokens.Color.border, CircleShape)
                .clickable(enabled = link != null, role = Role.Button) {
                    link?.let { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
                }
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Filled.PlayArrow, null, tint = if (link == null) Tokens.Color.tertiary else Tokens.Color.text, modifier = Modifier.size(13.dp))
            Text(if (link == null) stringResource(R.string.ad_coming_soon) else "Google Play",
                style = Tokens.Type.small.copy(fontWeight = FontWeight.SemiBold), color = if (link == null) Tokens.Color.tertiary else Tokens.Color.text,
                maxLines = 1)
        }
    }
}

// MARK: Hesap kartı (Ayarlar'ın en üstü)

/**
 * Ayarlar'ın en üstündeki hesap kartı (bento): girişliyse yükseltilmiş kart, amber halkalı rozet ve yeşil durum hapı;
 * değilse düz kart, nötr durum ve amber "+ eylem" satırı. Dokununca hesabın sayfası açılır. Dar ekranda durum hapı
 * rozetin altına iner; kart hiçbir boyda taşmaz.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun AccountTile(badge: String, icon: ImageVector, title: String, detail: String?, on: Boolean, status: String, call: String?,
                modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(Tokens.Radius.tileSmall)
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier.then(if (on) Modifier.perdeRaised(shape) else Modifier.perdeCard(shape)).clip(shape)
            .clickable(interaction, null, role = Role.Button, onClick = onClick)
            .padding(Tokens.Space.cards),
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap),
    ) {
        // Dar kartta (küçük ekran, büyük yazı) durum hapı rozetin yanına sığmazsa altına iner; kart hiçbir boyda taşmaz.
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
            verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            Box(Modifier.align(Alignment.CenterVertically)) { AccountAvatar(badge, icon, on) }
            Box(Modifier.align(Alignment.CenterVertically)) {
                StatusChip(status, if (on) ChipTone.OK else ChipTone.MUTED, dot = !on, icon = if (on) Icons.Filled.Check else null)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.micro)) {
            Text(title, style = Tokens.Type.headline, color = Tokens.Color.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, style = Tokens.Type.small, color = Tokens.Color.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            call?.let {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                    Icon(Icons.Filled.Add, null, tint = Tokens.Color.accentText, modifier = Modifier.size(13.dp))
                    Text(it, style = Tokens.Type.small.copy(fontWeight = FontWeight.SemiBold), color = Tokens.Color.accentText, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun AccountAvatar(badge: String, icon: ImageVector, on: Boolean) {
    Box(Modifier.size(44.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (on) {
            Box(Modifier.size(44.dp).border(1.5.dp, Tokens.Color.accent, CircleShape))
            Box(Modifier.size(36.dp).background(Brush.linearGradient(listOf(Color(0xFFFFCB63), Tokens.Color.peach)), CircleShape),
                contentAlignment = Alignment.Center) {
                Text(badge, style = Tokens.Type.label.copy(fontWeight = FontWeight.ExtraBold), color = Tokens.Color.onAccent)
            }
        } else Box(Modifier.size(36.dp).background(Tokens.Color.field, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Tokens.Color.secondary, modifier = Modifier.size(18.dp))
        }
    }
}

/** Kişi simgesi (hesap kartının girişsiz hâli). */
val PersonIcon: ImageVector get() = Icons.Filled.Person

/**
 * Ayarlar'ın en üstündeki iki hesap kartı (iPhone PerdeAccountCards): ikinci hesap (PSN ya da Microsoft) ve konsol.
 * Dokununca giriş ya da eşleme sayfası açılır (eski Profil'deki karolarla aynı yerler).
 */
@Composable
fun AccountCards(onPsn: () -> Unit, onConsole: () -> Unit) {
    val settings = com.couchsubs.mobile.Services.settings
    val xbox = settings.xbox
    val signedIn = if (xbox) com.couchsubs.mobile.Services.xboxAuth.signedIn else settings.accountId != null
    val consoleName = if (xbox) settings.xboxConsole?.name else settings.console?.name
    val paired = if (xbox) settings.xboxConsole != null else settings.console != null
    // iPhone gibi üstten hizalı iki kart (eşit yükseklik için iç ölçüm yok: dar kartta durum hapı alta iner, yazı kırpılmaz).
    TopAlignedColumns(
        { modifier ->
            if (xbox) AccountTile("XB", PersonIcon, "Microsoft", "Xbox (Beta)", signedIn,
                stringResource(if (signedIn) R.string.perde_signed_in else R.string.perde_not_signed_in),
                if (signedIn) null else stringResource(R.string.perde_sign_in), modifier, onPsn)
            else AccountTile("PS", PersonIcon, stringResource(R.string.profile_psn), consoleName?.ifEmpty { "PS5" }, signedIn,
                stringResource(if (signedIn) R.string.perde_signed_in else R.string.perde_not_signed_in),
                if (signedIn) null else stringResource(R.string.perde_sign_in), modifier, onPsn)
        },
        { modifier ->
            AccountTile(if (xbox) "XB" else "PS5", CouchIcons.Gamepad, consoleName?.ifEmpty { null } ?: if (xbox) "Xbox" else "PS5",
                if (xbox) settings.xboxConsole?.model else settings.console?.host, paired,
                stringResource(if (paired) R.string.perde_paired else R.string.perde_not_set_up),
                if (paired) null else stringResource(if (xbox) R.string.perde_choose_xbox else R.string.perde_pair_ps5), modifier, onConsole)
        },
    )
}

/** İki sütun, üstten hizalı (iç ölçüm yok); yazı çok büyükken (1,5+) tek sütuna düşer. */
@Composable
private fun TopAlignedColumns(left: @Composable (Modifier) -> Unit, right: @Composable (Modifier) -> Unit) {
    if (LocalDensity.current.fontScale >= 1.5f) {
        Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            left(Modifier.fillMaxWidth())
            right(Modifier.fillMaxWidth())
        }
        return
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap), verticalAlignment = Alignment.Top) {
        left(Modifier.weight(1f))
        right(Modifier.weight(1f))
    }
}

/** Ayarlar bölümünün simgesi (iPhone PhoneSettingsSection.icon). */
val SettingsSection.icon: ImageVector
    get() = when (this) {
        SettingsSection.BASICS -> CouchIcons.Sliders
        SettingsSection.APPEARANCE -> CouchIcons.TextSize
        SettingsSection.ADVANCED -> Icons.Filled.Settings
        SettingsSection.AREA -> CouchIcons.Viewfinder
        SettingsSection.PACKS -> CouchIcons.Package
        SettingsSection.DUBBING -> CouchIcons.Waveform
        SettingsSection.OUTPUTS -> CouchIcons.Tv
        SettingsSection.CONSOLE -> CouchIcons.Gamepad
    }

/** Ayarlar bölümünün rengi (iPhone PhoneSettingsSection.tint). */
fun SettingsSection.tint(): Color = when (this) {
    SettingsSection.BASICS, SettingsSection.AREA -> Tokens.Color.accent
    SettingsSection.APPEARANCE, SettingsSection.CONSOLE -> Tokens.Color.peach
    SettingsSection.ADVANCED -> Tokens.Color.live
    SettingsSection.PACKS -> Tokens.Color.olive
    SettingsSection.DUBBING -> Tokens.Color.plum
    SettingsSection.OUTPUTS -> Tokens.Color.teal
}
