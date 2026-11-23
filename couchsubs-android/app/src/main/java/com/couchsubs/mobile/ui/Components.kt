// SPDX-License-Identifier: AGPL-3.0-only
// Tekrar eden parçalar (Perde; iPhone MobileTheme.swift ile aynı adlar ve ölçüler): başlık satırı, değer kartı, seçici,
// kod haneleri, satır listesi, bilgi kartı, not kutusu.
package com.couchsubs.mobile.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.R

/**
 * Üst satır (iPhone HomeHeader / BackHeader): geri düğmesi (yuvarlak cam) + sayfa adı (20 orta); geri yoksa ve başlık
 * varsa sekme kökündeki büyük sayfa başlığı (28); başlık da yoksa logo + "CouchSubs". Sağda simge düğmeleri.
 */
@Composable
fun TopBar(title: String? = null, onBack: (() -> Unit)? = null, onClose: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().heightIn(min = Tokens.Control.icon), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        when {
            onBack != null -> {
                IconAction(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), onBack)
                if (title != null) Text(title, style = Tokens.Type.h3, color = Tokens.Color.text, modifier = Modifier.weight(1f)
                    .semantics { heading() }, maxLines = 1, overflow = TextOverflow.Ellipsis)
                else Spacer(Modifier.weight(1f))
            }
            title != null -> LargeTitle(title, Modifier.weight(1f))
            else -> {
                Brand()
                Spacer(Modifier.weight(1f))
            }
        }
        actions()
        if (onClose != null) IconAction(Icons.Filled.Close, stringResource(R.string.close), onClose)
    }
}

/** Simge düğmesi (yuvarlak cam); ad [IconSquare]'dan okunur, simgenin kendi açıklaması yoktur. */
@Composable
fun IconAction(icon: ImageVector, label: String, onClick: () -> Unit) =
    IconSquare(label, onClick = onClick) { Icon(icon, null, tint = Tokens.Color.text, modifier = Modifier.size(20.dp)) }

/** Bir ayara ya da ekrana götüren satırın ve karonun sonundaki `›` (soluk renk). */
@Composable
fun Chevron() = Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Tokens.Color.tertiary, modifier = Modifier.size(20.dp))

@Composable
fun SettingsAction(onClick: () -> Unit) = IconAction(Icons.Filled.Settings, stringResource(R.string.settings), onClick)

/** Profil (cihazlar ve tercihler) simge düğmesi. */
@Composable
fun ProfileAction(onClick: () -> Unit) = IconAction(Icons.Filled.Person, stringResource(R.string.profile), onClick)

/** Sayfa başlığı (iPhone ScreenTitle): üstte isteğe bağlı adım etiketi, 28 başlık, 4 altında gri açıklama. */
@Composable
fun Heading(title: String, body: String? = null, step: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        step?.let { Text(it, style = Tokens.Type.label, color = Tokens.Color.secondary, modifier = Modifier.padding(bottom = Tokens.Space.hair)) }
        Text(title, style = Tokens.Type.display, color = Tokens.Color.text, modifier = Modifier.semantics { heading() })
        body?.let {
            Text(it, style = Tokens.Type.body.copy(letterSpacing = (DesignTokens.MUTED_TRACKING / 2).sp, lineHeight = 23.sp),
                color = Tokens.Color.secondary)
        }
    }
}

/** Kutusuz karo simgesi (18 dp, ikincil renk; oyun paketi simgesi amber). */
@Composable
fun TileIcon(icon: ImageVector, tint: Color = Tokens.Color.secondary) =
    Icon(icon, null, tint = tint, modifier = Modifier.size(Tokens.Control.tileIcon))

/** Soldurulmuş (kapalı) içerik: %60; %40'ta ikincil yazı 4,5:1'in altına düşüyordu. */
private const val DIM_ALPHA = 0.6f

/**
 * Değer kartı (iPhone StatTile): üstte etiket satırı (renkli simge karesi, 13 orta ad, sağda isteğe bağlı köşe ve `›`),
 * altında 20'lik değer, altında isteğe bağlı durum hapı ([status]: "Eşleşti", "Hazır"; [statusOk] yeşil, değilse gri).
 */
@Composable
fun StatusTile(
    icon: ImageVector?, label: String, value: String, modifier: Modifier = Modifier,
    style: TileStyle = TileStyle.NORMAL, dim: Boolean = false, corner: (@Composable () -> Unit)? = null,
    note: String? = null, chevron: Boolean = false, status: String? = null, statusOk: Boolean = true,
    iconTone: IconTone = IconTone.GRAY, onClick: (() -> Unit)? = null,
) {
    Tile(modifier.alpha(if (dim) DIM_ALPHA else 1f), style = style, onClick = onClick, spacing = Tokens.Space.gap) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            if (icon != null) IconTile(icon, iconTone, 26.dp)
            Text(label, style = Tokens.Type.label, color = Tokens.Color.secondary, modifier = Modifier.weight(1f), maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            corner?.invoke()
            if (chevron) Chevron()
        }
        Text(value, style = Tokens.Type.title, color = Tokens.Color.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
        status?.let { StatusChip(it, if (statusOk) ChipTone.OK else ChipTone.MUTED) }
        note?.let { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary) }
    }
}

/** Seçili karonun sağ üstündeki işaret: 20 dp amber daire içinde onay. */
@Composable
fun SelectedCheck() {
    Box(Modifier.size(20.dp).background(Tokens.Color.accent, CircleShape), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Check, stringResource(R.string.selected), tint = Tokens.Color.onAccent, modifier = Modifier.size(14.dp))
    }
}

/** İki sütunlu satır (bento); iki karo aynı yükseklikte. Yazı çok büyükken (1,5+) tek sütuna düşer (iPhone ile aynı). */
@Composable
fun TwoColumns(left: @Composable (Modifier) -> Unit, right: @Composable (Modifier) -> Unit) {
    if (LocalDensity.current.fontScale >= 1.5f) {
        Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            left(Modifier.fillMaxWidth())
            right(Modifier.fillMaxWidth())
        }
        return
    }
    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        left(Modifier.weight(1f).fillMaxHeight())
        right(Modifier.weight(1f).fillMaxHeight())
    }
}

/**
 * Tek seçimli seçici (her yerde aynı; iPhone DSTabs): bej iz (alan rengi, kapsül, kıl çizgi), seçili sekme yükselmiş hap
 * (açıkta beyaz, koyuda #3A3C44) + gölge + güçlü kıl çizgi; hap 250 ms kayar, seçimde seçim titreşimi. Sekmeler genişliği
 * eşit paylaşır; sığmayan ad küçülür. Erişilebilirlikte sekme grubu olarak okunur. [selected] -1 ise hiçbiri seçili değil.
 */
@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val view = LocalView.current
    val gate = motionGate()
    val shape = CircleShape
    // Seçili hap çizimde yerleşir (ölçüm durumu yok, BoxWithConstraints yok): ilk karede de doğru yerde, iki sütunlu kartta
    // da kullanılabilir (iç ölçüm). Hap seçimle 250 ms kayar.
    val position by animateFloatAsState(selected.toFloat(), perdeTween(Tokens.Motion.medium, gate), label = "seg")
    val pill = Tokens.Color.segPill
    val ring = Tokens.Color.hairStrong
    val gap = Tokens.Space.hair
    Box(Modifier.fillMaxWidth().background(Tokens.Color.field, shape).border(1.dp, Tokens.Color.border, shape)
        .padding(Tokens.Space.hair).selectableGroup()
        .drawBehind {
            if (selected !in options.indices) return@drawBehind
            val gapPx = gap.toPx()
            val slot = (size.width - gapPx * (options.size - 1)) / options.size
            val x = (slot + gapPx) * position
            val corner = androidx.compose.ui.geometry.CornerRadius(size.height / 2)
            // Hafif gölge, hap, güçlü kıl çizgi.
            drawRoundRect(Color.Black.copy(alpha = 0.18f), Offset(x, 1.dp.toPx()), Size(slot, size.height), corner)
            drawRoundRect(pill, Offset(x, 0f), Size(slot, size.height), corner)
            drawRoundRect(ring, Offset(x + 0.5f, 0.5f), Size(slot - 1f, size.height - 1f), corner,
                style = androidx.compose.ui.graphics.drawscope.Stroke(1.dp.toPx()))
        }) {
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            options.forEachIndexed { index, option ->
                val on = index == selected
                Box(
                    Modifier.weight(1f).heightIn(min = Tokens.Control.segment).clip(shape)
                        .selectable(selected = on, role = Role.Tab) {
                            if (!on) Haptics.selection(view)
                            onSelect(index)
                        }
                        .padding(horizontal = Tokens.Space.inline, vertical = Tokens.Space.hair),
                    contentAlignment = Alignment.Center,
                ) {
                    ShrinkText(option, Tokens.Type.tab, if (on) Tokens.Color.text else Tokens.Color.secondary)
                }
            }
        }
    }
}

/** Tek satır yazı; sığmazsa %70'e kadar küçülür (iPhone minimumScaleFactor), büyük yazı boyunda iki satıra iner. */
@Composable
private fun ShrinkText(text: String, style: TextStyle, color: Color) {
    val large = LocalDensity.current.fontScale >= 1.3f
    var scale by remember(text) { mutableFloatStateOf(1f) }
    Text(text, style = style.copy(fontSize = style.fontSize * scale), color = color, textAlign = TextAlign.Center,
        maxLines = if (large) 2 else 1, softWrap = large, overflow = TextOverflow.Ellipsis,
        onTextLayout = { if (!large && it.didOverflowWidth && scale > 0.7f) scale = (scale - 0.05f).coerceAtLeast(0.7f) })
}

/** Sekiz haneli eşleme kodu kutuları; yazılan rakamlar kutulara dağılır, sıradaki kutu amber çerçeveli. */
@Composable
fun CodeCells(code: String, length: Int = 8) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        repeat(length) { index ->
            val char = code.getOrNull(index)?.toString() ?: ""
            val shape = RoundedCornerShape(Tokens.Radius.control)
            val next = index == code.length
            Box(
                Modifier.weight(1f).heightIn(min = 52.dp).background(Tokens.Color.field, shape)
                    .border(if (next) 1.5.dp else 1.dp, if (next) Tokens.Color.accent else Tokens.Color.border, shape),
                contentAlignment = Alignment.Center,
            ) { Text(char, style = Tokens.Type.monoValue, color = Tokens.Color.text) }
        }
    }
}

/** Geniş kartın içindeki satırlar, aralarında 1 dp ayraç (iPhone Tile(spacing: 0) + RowDivider). */
@Composable
fun RowList(rows: List<@Composable () -> Unit>) {
    val shape = RoundedCornerShape(Tokens.Radius.tile)
    Column(Modifier.fillMaxWidth().perdeCard(shape).padding(horizontal = Tokens.Space.tile, vertical = Tokens.Space.hair)) {
        rows.forEachIndexed { index, row ->
            if (index > 0) HorizontalDivider(color = Tokens.Color.border)
            row()
        }
    }
}

/** Bilgi kartı (iPhone InfoCard): durum değil ayar bilgisi gösteren düz kart; satırlar ([InfoRow]) arasında 1 dp ayraç. */
@Composable
fun InfoCard(rows: List<@Composable () -> Unit>, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(Tokens.Radius.tile)
    Column(modifier.fillMaxWidth().perdeCard(shape).padding(horizontal = Tokens.Space.tile, vertical = Tokens.Space.hair)) {
        rows.forEachIndexed { index, row ->
            if (index > 0) HorizontalDivider(color = Tokens.Color.border)
            row()
        }
    }
}

/**
 * Bilgi kartının satırı (iPhone MobileInfoRow): solda ad (gövde, ikincil), sağda değer (15 orta, tablo rakamlı) ve `›`.
 * En az 52 yükseklik.
 */
@Composable
fun InfoRow(label: String, value: String, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Tokens.Control.row)
            .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it }
            .padding(vertical = Tokens.Space.hair),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline),
    ) {
        Text(label, style = Tokens.Type.body, color = Tokens.Color.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(value, style = Tokens.Type.value, color = Tokens.Color.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.End, modifier = Modifier.weight(1f))
        if (onClick != null) Chevron()
    }
}

/** Kaydırıcının üstündeki satır: solda ad (15 orta), sağda değer (mono, amber); bütün kaydırıcılarda aynı biçim. */
@Composable
fun SliderHeader(title: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Text(title, style = Tokens.Type.headline, color = Tokens.Color.text, modifier = Modifier.weight(1f))
        Text(value, style = Tokens.Type.label.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"), color = Tokens.Color.accentText,
            textAlign = TextAlign.End)
    }
}

/** "ya da e-posta ile" gibi ortası yazılı ayraç. */
@Composable
fun DividerText(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        HorizontalDivider(Modifier.weight(1f), color = Tokens.Color.border)
        Text(text, style = Tokens.Type.caption, color = Tokens.Color.secondary)
        HorizontalDivider(Modifier.weight(1f), color = Tokens.Color.border)
    }
}

/**
 * Bilgi ya da uyarı kutusu (iPhone MobileNote / DSNoticeBox): varsayılan uyarı (amber tonlu kutu); ikincil renk verilirse
 * bilgi kutusu, tehlike renginde hata kutusu, başarı renginde başarı kutusu.
 */
@Composable
fun NoteTile(text: String, color: Color = Tokens.Color.warning) {
    val tone = when (color) {
        Tokens.Color.secondary -> NoticeTone.INFO
        Tokens.Color.danger -> NoticeTone.ERROR
        Tokens.Color.success, Tokens.Color.successText -> NoticeTone.SUCCESS
        else -> NoticeTone.WARNING
    }
    NoticeBox(text, tone)
}

/**
 * Gelip giden not karosu (hata, uyarı): açılırken ve kapanırken solarak yer açar ya da kapatır. Kapanırken son metin
 * görünmeye devam eder; boş karo kaymaz.
 */
@Composable
fun AnimatedNote(text: String?, color: Color = Tokens.Color.warning) {
    val last = remember { arrayOfNulls<String>(1) }
    if (text != null) last[0] = text
    AnimatedVisibility(text != null, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
        (text ?: last[0])?.let { NoteTile(it, color) }
    }
}
