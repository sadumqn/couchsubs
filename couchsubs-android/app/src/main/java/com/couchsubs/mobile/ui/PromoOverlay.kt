// SPDX-License-Identifier: AGPL-3.0-only
// Tanıtım popup'ı (iPhone'daki PromoOverlay ile aynı): %75 siyah karartma (altındaki ana ekran Android 12+'da bulanık),
// üstte ortada "Sponsorlu" rozeti, ortada dikey görsel (9:16; kırpılmaz, oranı korunarak sığar, köşeler yuvarlak),
// sağ üst köşeye çaprazlama oturan açık renkli yuvarlak kapat (X). Görsele dokununca bağlantı sistem tarayıcısında açılır.
package com.couchsubs.mobile.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.min
import com.couchsubs.mobile.R
import com.couchsubs.mobile.promo.PromoController
import com.couchsubs.mobile.promo.PromoPolicy

/** Karartma: %75 siyah. */
private val PROMO_SCRIM = Color(0xBF000000)
private val PROMO_RADIUS = 24.dp
/** Kapat düğmesi: görünen daire 36 dp, dokunma alanı 48 dp; merkezi görselin sağ üst köşe noktasında. */
private val PROMO_CLOSE_TOUCH = 48.dp
private val PROMO_CLOSE_DOT = 36.dp
/** "Sponsorlu" rozetinin yeri; görselle arasını kapat düğmesinin taşma payı (24 dp) açar. */
private val PROMO_BADGE = 28.dp

@Composable
fun PromoOverlay(ready: PromoController.Ready, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val popup = ready.popup
    val image = ready.image
    val ratio = (image.width.toFloat() / image.height.coerceAtLeast(1)).coerceIn(0.2f, 5f)
    val bitmap = remember(image) { image.asImageBitmap() }
    BackHandler(onBack = onDismiss)
    Box(
        Modifier.fillMaxSize().background(PROMO_SCRIM)
            // Karartmaya dokunmak alttaki ana ekrana geçmez (popup yalnız X, geri ya da görselle kapanır).
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = {}),
        contentAlignment = Alignment.Center,
    ) {
        BoxWithConstraints(Modifier.safeDrawingPadding().padding(Tokens.Space.screen), contentAlignment = Alignment.Center) {
            // Görsel kırpılmadan sığar: rozet ve köşeden taşan kapat düğmesi için yer ayrılınca oranı korunur.
            val overhang = PROMO_CLOSE_TOUCH / 2
            val maxImageHeight = maxHeight - PROMO_BADGE - overhang
            val width = min(maxWidth - overhang * 2, maxImageHeight * ratio)
            val height = width / ratio
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.height(PROMO_BADGE), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.promo_label), style = Tokens.Type.mono.copy(fontSize = 9.sp, letterSpacing = 1.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = Color.White.copy(alpha = 0.85f), maxLines = 1,
                        modifier = Modifier.glass(CircleShape).padding(horizontal = 14.dp, vertical = 4.dp))
                }
                // Kapat düğmesi görselin dışına taşar; Compose dokunuşu kabın dışına iletmediği için kap, görselin çevresinde
                // yarım düğme payı bırakır (dokunma alanı eksiksiz kalır).
                Box(Modifier.padding(start = overhang, top = overhang, end = overhang)) {
                    Image(
                        bitmap,
                        contentDescription = popup.alt.ifEmpty { stringResource(R.string.promo_open) },
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(width, height)
                            .clip(RoundedCornerShape(PROMO_RADIUS))
                            .clickable(role = Role.Button) {
                                if (PromoPolicy.isWebLink(popup.link)) try {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(popup.link))
                                        .addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                } catch (error: ActivityNotFoundException) {
                                    // Tarayıcı yoksa popup yine kapanır.
                                }
                                onDismiss()
                            },
                    )
                    // Kapat (X) köşeye çaprazlama oturur: yarısı görselin içinde, yarısı dışında.
                    val closeLabel = stringResource(R.string.close)
                    Box(
                        Modifier.align(Alignment.TopEnd).offset(x = overhang, y = -overhang).size(PROMO_CLOSE_TOUCH)
                            .clip(CircleShape)
                            .clickable(role = Role.Button, onClick = onDismiss)
                            .semantics { contentDescription = closeLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.size(PROMO_CLOSE_DOT).glass(CircleShape), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Close, contentDescription = null, tint = Tokens.Color.text, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
        }
    }
}
