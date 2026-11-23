// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.SecondScreen
import com.couchsubs.mobile.service.TranslationService

/**
 * "Başka bir cihazda göster": QR kod, adres ve Kopyala (Mac, Windows ve iPhone'da aynı ad ve sıra). Ayarlar'da ve altyazı
 * hedefi seçiminde gösterilir; ikinci ekran her zaman ek bir alıcıdır, hedef seçimini değiştirmez. [version] erişim anahtarı
 * yenilenince artar, adres ve kod yeniden üretilir.
 */
@Composable
fun SecondScreenTile(modifier: Modifier = Modifier, version: Int = 0) {
    val context = LocalContext.current
    val address = remember(version) { TranslationService.secondScreenAddress() }
    val code = remember(address) { address?.let { runCatching { qrBitmap(it) }.getOrNull() } }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            kotlinx.coroutines.delay(1500)
            copied = false
        }
    }
    Tile(modifier.fillMaxWidth()) {
        SectionTitle(stringResource(R.string.second_screen_title))
        if (address == null) {
            Text(stringResource(R.string.second_screen_offline), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            return@Tile
        }
        code?.let { bitmap ->
            // Koyu temada da okunsun diye kod beyaz zeminde.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Image(bitmap.asImageBitmap(), contentDescription = stringResource(R.string.second_screen_title),
                    filterQuality = FilterQuality.None,
                    modifier = Modifier.size(200.dp).background(Color.White, RoundedCornerShape(Tokens.Radius.control)).padding(8.dp))
            }
        }
        SelectionContainer {
            Text(address, style = Tokens.Type.caption.copy(fontFamily = FontFamily.Monospace), color = Tokens.Color.text)
        }
        SecondaryButton(stringResource(if (copied) R.string.history_copied else R.string.history_copy)) {
            context.getSystemService(android.content.ClipboardManager::class.java)?.setPrimaryClip(android.content.ClipData.newPlainText("CouchSubs", address))
            copied = true
        }
        Text(stringResource(R.string.second_screen_caption), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

/** QR modülleri birer piksel; görüntü büyütülürken yumuşatılmaz (FilterQuality.None). */
private fun qrBitmap(text: String): Bitmap {
    val modules = SecondScreen.qrModules(text)
    val size = modules.size
    val pixels = IntArray(size * size) { index -> if (modules[index / size][index % size]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt() }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}
