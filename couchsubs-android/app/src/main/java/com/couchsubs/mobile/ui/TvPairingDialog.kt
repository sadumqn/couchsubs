// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.SubtitlePairing
import com.couchsubs.mobile.service.TranslationService

/**
 * TV'nin eşleştirme isteği: onay penceresi ve istek beklediği sürece ekranın üstünde duran "TV eşleşmek istiyor" satırı
 * (iPhone'daki TVPairingPrompt/TVPairingBanner ile aynı). Pencere geri tuşuyla ya da dışına dokunarak kapatılırsa istek
 * reddedilmez, yalnız pencere gizlenir: onay satırı kalır, istek yenisiyle değişirse pencere yeni kodla yeniden açılır.
 * Eskiden pencereyi kapatmak isteği reddediyor, TV on saniye boyunca yeniden deneyemiyordu.
 */
@Composable fun TvPairingPrompt(ticket: SubtitlePairing.Ticket?) {
    // Ekranın içeriğinden sonra çağrılır: satır içeriğin üstünde, ekranın tepesinde durur.
    Box(Modifier.fillMaxSize()) {
        // Kapanırken son istek görünmeye devam eder (kayarak çıkar).
        var last by remember { mutableStateOf(ticket) }
        if (ticket != null && ticket != last) last = ticket
        AnimatedVisibility(ticket != null, Modifier.align(Alignment.TopCenter),
            enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
            last?.let { TvPairingBanner(it) }
        }
    }
    TvPairingDialog(ticket)
}

@Composable fun TvPairingDialog(ticket: SubtitlePairing.Ticket?) {
    var hidden by remember { mutableStateOf<String?>(null) }
    if (ticket == null || hidden == ticket.id) return
    AlertDialog(onDismissRequest = { hidden = ticket.id },
        title = { Text(stringResource(R.string.tv_pair_title)) },
        text = { Text(stringResource(R.string.tv_pair_code, ticket.code)) },
        confirmButton = { TextButton(onClick = { TranslationService.resolvePairing(ticket.id, true) }) { Text(stringResource(R.string.tv_pair_approve)) } },
        dismissButton = { TextButton(onClick = { TranslationService.resolvePairing(ticket.id, false) }) { Text(stringResource(R.string.tv_pair_reject)) } })
}

/** Onay bekleyen TV eşleştirme isteği: pencere görünmese de her ekranın üstünde durur. */
@Composable private fun TvPairingBanner(ticket: SubtitlePairing.Ticket) {
    Column(Modifier.fillMaxWidth().background(Tokens.Color.surface)) {
        Column(Modifier.statusBarsPadding().padding(Tokens.Space.tile), verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                Icon(CouchIcons.Tv, null, tint = Tokens.Color.accentText)
                Text(stringResource(R.string.tv_pair_banner), style = Tokens.Type.headline, color = Tokens.Color.text)
            }
            Text(stringResource(R.string.tv_pair_code, ticket.code), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                PrimaryButton(stringResource(R.string.tv_pair_approve), Modifier.weight(1f)) { TranslationService.resolvePairing(ticket.id, true) }
                SecondaryButton(stringResource(R.string.tv_pair_reject), Modifier.weight(1f)) { TranslationService.resolvePairing(ticket.id, false) }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Tokens.Color.accent))
    }
}
