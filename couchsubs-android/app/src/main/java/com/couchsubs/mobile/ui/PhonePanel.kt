// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.core.ScreenPhoneCard
import com.couchsubs.mobile.core.ScreenTranslation

/**
 * GTA 6 telefonunun yanındaki sohbet paneli, karedeki yerinde ([width]×[height] karenin gösterildiği alan). Yazı boyu
 * panelin satır yüksekliğinden; küçük ekranda en az [minFont] (sığmayan eski mesajlar üstten kırpılır). Mac/iPhone
 * PhonePanelView, Windows PhonePanelView.cs, TV app.js placePanel ile aynı çizim.
 */
@Composable
fun PhonePanelInFrame(panel: ScreenPhoneCard.Panel, width: Dp, height: Dp, minFont: Float = 12f) {
    val box = panel.card.box
    val font = maxOf(minFont, (height.value * panel.card.lineHeight * 0.85).toFloat())
    PhonePanelView(panel, font, maxOf(6f, (ScreenPhoneCard.PANEL_RADIUS * height.value / 1080).toFloat()).dp,
        Modifier
            .offset(x = width * box.left.toFloat(), y = height * box.top.toFloat())
            .size(width * (box.right - box.left).toFloat(), height * (box.bottom - box.top).toFloat()))
}

/**
 * Sohbet paneli: yuvarlak köşeli, yarı saydam koyu kart; üstte kişinin adı, altında mesajlar sırayla (karşı taraf solda
 * krem, oyuncu sağda amber balon, not ortada). Sığmayan en eski mesajlar üstten kırpılır, son mesajlar görünür kalır. Sağ
 * altta sade kanepe simgesi.
 */
@Composable
fun PhonePanelView(panel: ScreenPhoneCard.Panel, fontSize: Float, radius: Dp, modifier: Modifier = Modifier) {
    val font = maxOf(8f, fontSize)
    val card = panel.card.surface
    val foreground = color(card?.foreground, Color.White)
    Box(modifier.clip(RoundedCornerShape(radius))
        .background(color(card?.background, Color.Black).copy(alpha = ScreenPhoneCard.PANEL_OPACITY.toFloat()))) {
        Column(Modifier.fillMaxSize().padding(start = (font * 0.6f).dp, top = (font * 0.55f).dp, end = (font * 0.6f).dp,
            bottom = (font * 1.3f).dp)) {
            panel.title?.let { title ->
                Text(title.translation, style = TextStyle(fontSize = (font * 1.05f).sp, fontWeight = FontWeight.Bold),
                    color = color(title.surface?.foreground, foreground), textAlign = TextAlign.Center, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height((font * 0.5f).dp))
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().clipToBounds(), contentAlignment = Alignment.BottomStart) {
                val bubbleMax = maxWidth * 0.84f
                Column(Modifier.fillMaxWidth().wrapContentHeight(align = Alignment.Bottom, unbounded = true)) {
                    panel.messages.forEach { Message(it, font, bubbleMax) }
                }
            }
        }
        Canvas(Modifier.align(Alignment.BottomEnd).padding((font * 0.45f).dp).size((font * 0.9f).dp, (font * 0.6f).dp)) {
            val sx = size.width / 24f
            val sy = size.height / 16f
            for (part in ScreenPhoneCard.COUCH_GLYPH) {
                drawRoundRect(foreground.copy(alpha = 0.35f), Offset(part[0].toFloat() * sx, part[1].toFloat() * sy),
                    Size(part[2].toFloat() * sx, part[3].toFloat() * sy), CornerRadius(part[4].toFloat() * sx, part[4].toFloat() * sy))
            }
        }
    }
}

@Composable
private fun Message(item: ScreenTranslation.Item, font: Float, bubbleMax: Dp) {
    val note = item.panel == ScreenPhoneCard.PanelPart.NOTE
    val mine = item.panel == ScreenPhoneCard.PanelPart.MINE
    val text = color(item.surface?.foreground, Color.White)
    if (note) {
        Text(item.translation, style = TextStyle(fontSize = (font * 0.8f).sp, fontWeight = FontWeight.Medium), color = text,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = (font * 0.45f).dp))
        return
    }
    Row(Modifier.fillMaxWidth().padding(top = (font * 0.45f).dp),
        horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        Text(item.translation, style = TextStyle(fontSize = font.sp, lineHeight = (font * 1.2f).sp, fontWeight = FontWeight.SemiBold),
            color = text,
            modifier = Modifier.widthIn(max = bubbleMax)
                .clip(RoundedCornerShape((font * 0.75f).dp))
                .background(color(item.surface?.background, Color.Gray))
                .padding(horizontal = (font * 0.6f).dp, vertical = (font * 0.32f).dp))
    }
}

private fun color(hex: String?, fallback: Color): Color =
    hex?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() } ?: fallback
