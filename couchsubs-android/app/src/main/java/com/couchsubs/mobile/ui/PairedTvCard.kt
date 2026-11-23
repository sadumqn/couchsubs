// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.ManualAddress
import com.couchsubs.mobile.tv.InstalledTv
import com.couchsubs.mobile.tv.TvBrand
import com.couchsubs.mobile.tv.TvReach
import com.couchsubs.mobile.tv.TvRelocation
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Kartta TV'nin markası ve adresi ("LG · 192.168.1.156"); adres değişince yeni adres görünür. */
internal fun pairedTvDetail(tv: InstalledTv): String {
    val brand = when (tv.brand) {
        TvBrand.LG -> "LG"
        TvBrand.SAMSUNG -> "Samsung"
        TvBrand.ANDROID_TV -> "Android TV"
    }
    return "$brand · ${tv.host}"
}

/**
 * Eşli TV kartının TV'yi yeniden bulma bölümü ve eylemleri (Mac/Windows Ayarlar › Çıkış Ekranları, iPhone ile aynı):
 *  - Kart görünürken TV uygulaması bağlı değilse ~10 sn'de bir kayıtlı adres yoklanır ([TvRelocation.checkTvReachable]);
 *    TV yeni adreste bulunursa kayıt taşınır, kartta yeni adres görünür ([onChanged]).
 *  - "TV'yi Eşleştir" / "Deneme Altyazısı Gönder" TV'ye ulaşamazsa ([unreachableHost]) açık hata ve "TV'yi Yeniden Ara",
 *    "IP Adresi Gir" düğmeleri görünür.
 *  - Her zaman "TV'yi Değiştir" (keşif listesi + IP girişi) ve onaylı "Eşleşmeyi Kaldır".
 *
 * beta.89 (Mac): TV'nin adresi değişmişti; kart "TV uygulaması bekleniyor" diyor, "TV'yi Eşleştir" hiçbir hata
 * göstermiyor, IP girilemiyor ve eşli TV kaldırılamıyordu.
 */
@Composable
internal fun PairedTvActions(
    tv: InstalledTv?,
    connected: Boolean,
    unreachableHost: String?,
    onChanged: () -> Unit,
    onChangeTv: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var searching by remember { mutableStateOf(false) }
    var entering by remember { mutableStateOf(false) }
    var typed by remember { mutableStateOf("") }
    var typedError by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    var stillSilent by remember { mutableStateOf<String?>(null) }

    // Otomatik yeniden bulma: bağlı değilken ~10 sn'de bir yoklanır (ağ araması en çok 30 sn'de bir).
    LaunchedEffect(tv?.host, connected) {
        if (tv == null || connected) return@LaunchedEffect
        while (true) {
            val location = TvRelocation.checkTvReachable(context)
            if (location is TvReach.Location.Moved) onChanged()
            delay(TvRelocation.CHECK_INTERVAL_MS)
        }
    }

    val shownHost = stillSilent ?: unreachableHost
    if (tv != null && shownHost != null && !connected) {
        NoticeBox(stringResource(R.string.tv_not_responding_at, shownHost), NoticeTone.ERROR)
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            SecondaryButton(stringResource(R.string.tv_search_again), Modifier.weight(1f), enabled = !searching, busy = searching) {
                searching = true
                scope.launch {
                    val location = TvRelocation.searchTvAgain(context)
                    searching = false
                    stillSilent = if (location == TvReach.Location.Silent) Services.settings.installedTv?.host else null
                    onChanged()
                }
            }
            SecondaryButton(stringResource(R.string.tv_enter_ip), Modifier.weight(1f)) { entering = !entering }
        }
    }
    if (tv != null && entering) {
        Field(typed, { typed = it.trim(); typedError = false }, stringResource(R.string.tvinstall_address),
            keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri), placeholder = stringResource(R.string.tvinstall_address_example))
        if (typedError) NoteTile(stringResource(R.string.tv_ip_not_recognised))
        SecondaryButton(stringResource(R.string.tv_use_address), enabled = !searching && typed.isNotBlank(), busy = searching) {
            val address = ManualAddress.normalize(typed)
            if (address == null) { typedError = true; return@SecondaryButton }
            searching = true
            scope.launch {
                val ok = TvRelocation.useTvAddress(context, address)
                searching = false
                typedError = !ok
                if (ok) {
                    entering = false
                    stillSilent = null
                    onChanged()
                }
            }
        }
    }
    if (tv != null) Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        SecondaryButton(stringResource(R.string.tv_change), Modifier.weight(1f), onClick = onChangeTv)
        SecondaryButton(stringResource(R.string.tv_remove_pairing), Modifier.weight(1f)) { confirmRemove = true }
    }
    if (confirmRemove && tv != null) AlertDialog(
        onDismissRequest = { confirmRemove = false },
        title = { Text(stringResource(R.string.tv_remove_pairing_title)) },
        text = { Text(stringResource(R.string.tv_remove_pairing_confirm)) },
        confirmButton = {
            TextButton({
                confirmRemove = false
                TvRelocation.removeTvPairing(context)
                stillSilent = null
                onChanged()
            }) { Text(stringResource(R.string.tv_remove_pairing), color = Tokens.Color.danger) }
        },
        dismissButton = { TextButton({ confirmRemove = false }) { Text(stringResource(R.string.cancel)) } },
        containerColor = Tokens.Color.surface2,
    )
}

/**
 * "TV'yi Eşleştir" ve "Deneme Altyazısı Gönder"den önce: eşli TV'ye ulaşılıyor mu. Adres sessizse ağ hemen aranır; TV
 * yeni adreste bulunursa kayıt taşınır ve eylem sürer (null döner). Bulunamazsa TV'nin (eski) adresi döner: kart açık
 * hata gösterir.
 */
internal suspend fun unreachablePairedTv(context: android.content.Context): String? {
    val saved = Services.settings.installedTv ?: return null
    return if (TvRelocation.searchTvAgain(context) == TvReach.Location.Silent) saved.host else null
}

/** Kart durumu: TV uygulaması bekleniyor ama TV gerçekten yanıt vermiyorsa "Yanıt vermiyor — yeniden aranıyor…". */
@Composable
internal fun pairedTvWaitingText(): String {
    val silent by TvRelocation.notResponding.collectAsState()
    return stringResource(if (silent) R.string.tv_searching_again else R.string.profile_psn_missing)
}
