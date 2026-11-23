// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import com.couchsubs.mobile.R
import com.couchsubs.mobile.core.GameName
import com.couchsubs.mobile.service.LiveStatus
import com.couchsubs.mobile.service.PlayedGame

/**
 * Çeviri ekranında: "Hangi oyunu oynuyorsunuz?" kartı açıksa kart, değilse "Oynanan oyun: X · Değiştir" satırı (Mac ve
 * iPhone'daki GameAsk ile aynı metin ve davranış; bkz. [PlayedGame]).
 */
@Composable
fun GameSection(status: LiveStatus) {
    // Kart açılıp kapanırken satırla solarak yer değiştirir; yükseklik farkı yumuşakça kapanır.
    AnimatedContent(status.askingGame, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "gameAsk") { asking ->
        if (asking) GameAskCard() else Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            PlayedGameRow(status.game)
            GameAreasRow(status)
        }
    }
}

/**
 * Oyunun kayıtlı alanları: uygulandıysa "X için kayıtlı alanlar kullanılıyor · Geri al"; oyun yalnız paketten
 * tanındıysa "X için kayıtlı alanlar var. Kullanılsın mı? · Kullan / Hayır" (Windows, Mac ve iPhone ile aynı).
 */
@Composable
private fun GameAreasRow(status: LiveStatus) {
    val offered = status.offeredAreaProfileGame
    val active = status.areaProfileGame
    if (offered != null) {
        Tile(Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.area_profile_offer, offered), style = Tokens.Type.body, color = Tokens.Color.text)
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                SecondaryButton(stringResource(R.string.area_profile_use)) { PlayedGame.areas.useOffered() }
                GhostButton(stringResource(R.string.area_profile_no), color = Tokens.Color.secondary) { PlayedGame.areas.declineOffered() }
            }
        }
    } else if (active != null) {
        Tile(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.area_profile_using, active), Modifier.weight(1f), style = Tokens.Type.body, color = Tokens.Color.text)
                GhostButton(stringResource(R.string.area_profile_undo)) { PlayedGame.areas.undo() }
            }
        }
    }
}

/**
 * Oyun paketle tanınmadıysa çeviri başladıktan iki dakika sonra çıkan küçük kart: arama, öneriler, "Listede yok" ve "Sorma".
 * Seçim bu oturumda ve aynı PS5'te bir sonraki oturumda (ilk öneri) hatırlanır.
 */
@Composable
private fun GameAskCard() {
    var query by rememberSaveable { mutableStateOf("") }
    val typed = query.trim()
    val suggestions = remember(query) { PlayedGame.suggestions(query).take(5) }
    val last = remember { PlayedGame.lastPlayed }
    Tile(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.game_ask_title), style = Tokens.Type.headline, color = Tokens.Color.text, modifier = Modifier.weight(1f))
            GhostButton(stringResource(R.string.game_ask_dont_ask), color = Tokens.Color.secondary) { PlayedGame.dismiss() }
        }
        Text(stringResource(R.string.game_ask_body), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        Field(query, { query = it }, stringResource(R.string.game_ask_search),
            keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done))
        Column {
            suggestions.forEachIndexed { index, name ->
                if (index > 0) HorizontalDivider(color = Tokens.Color.border)
                Row(Modifier.fillMaxWidth().clickable { PlayedGame.choose(name) }.padding(vertical = Tokens.Space.gap),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                    Text(name, style = Tokens.Type.body, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                    if (name == last) Text(stringResource(R.string.game_last_played), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
            }
        }
        if (typed.isNotEmpty() && suggestions.none { GameName.key(it) == GameName.key(typed) }) {
            SecondaryButton(stringResource(R.string.game_ask_not_listed, typed)) { PlayedGame.choose(typed) }
        }
    }
}

/** "Oynanan oyun" satırı; "Değiştir" kartı açar. */
@Composable
private fun PlayedGameRow(game: String?) {
    Tile(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                TileLabel(stringResource(R.string.game_played))
                Text(game ?: stringResource(R.string.game_unknown), style = Tokens.Type.headline, color = Tokens.Color.text, maxLines = 1)
            }
            GhostButton(stringResource(if (game == null) R.string.game_choose else R.string.game_change)) { PlayedGame.ask() }
        }
    }
}
