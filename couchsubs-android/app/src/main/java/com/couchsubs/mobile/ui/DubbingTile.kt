// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.DubbingOutput
import com.couchsubs.mobile.core.DubbingVoice
import com.couchsubs.mobile.core.VoiceCast
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Ayarlardaki Türkçe dublaj kutusu: iPhone DubbingTile ve Mac/Windows'taki Türkçe dublaj kartıyla aynı adlar ve
 * seçenekler (açma, sesin çalacağı yer, anlatıcı/ikinci konuşan/karakter sesleri, Dinle). Ses telefonun kendi Türkçe
 * sesidir (Windows'taki "Hızlı"); indirme gerekmez.
 */
@Composable
fun DubbingTile() {
    val settings = Services.settings
    var enabled by remember { mutableStateOf(settings.dubbingEnabled) }
    var output by remember { mutableStateOf(settings.dubbingOutput) }
    var cast by remember { mutableStateOf(VoiceCast.fromJson(settings.dubbingCast)) }
    var hasVoice by remember { mutableStateOf(true) }
    LaunchedEffect(enabled) { if (enabled) hasVoice = withContext(Dispatchers.IO) { Services.dubber.hasTurkishVoice() } }
    fun save(changed: VoiceCast) {
        settings.dubbingCast = changed.toJson()
        cast = VoiceCast.fromJson(settings.dubbingCast)
    }
    Tile(Modifier.fillMaxWidth()) {
        SwitchRow(stringResource(R.string.dubbing_title), stringResource(R.string.dubbing_enable), enabled) {
            enabled = it; settings.dubbingEnabled = it; if (!it) Services.dubberIfCreated?.stop()
        }
        Caption(stringResource(R.string.dubbing_setup))
        if (enabled) {
            Caption(stringResource(R.string.dubbing_engine_note))
            if (!hasVoice) Caption(stringResource(R.string.dubbing_no_voice))
            TileLabel(stringResource(R.string.dubbing_output))
            Segmented(listOf(stringResource(R.string.main_target_tv), stringResource(R.string.main_target_phone)),
                if (output == DubbingOutput.TV) 0 else 1) {
                output = if (it == 0) DubbingOutput.TV else DubbingOutput.PHONE
                settings.dubbingOutput = output
                Services.dubberIfCreated?.stop()
            }
            VoiceRow(stringResource(R.string.dubbing_narrator), cast.narrator) { save(cast.also { c -> c.narrator = it }) }
            VoiceRow(stringResource(R.string.dubbing_partner), cast.partner) { save(cast.also { c -> c.partner = it }) }
            val names = cast.assignments.keys.sorted()
            if (names.isNotEmpty()) {
                TileLabel(stringResource(R.string.dubbing_characters))
                for (name in names) VoiceRow(displayName(name), cast.assignments.getValue(name)) { save(cast.also { c -> c.assign(it, name) }) }
            }
        }
    }
}

@Composable
private fun Caption(text: String) = Text(text, style = Tokens.Type.caption, color = Tokens.Color.secondary)

@Composable
private fun VoiceRow(title: String, voice: DubbingVoice, onChange: (DubbingVoice) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Box(Modifier.weight(1f)) {
            RowItem(title, voiceLabel(voice), onClick = { open = true })
            DropdownMenu(open, { open = false }) {
                for (option in DubbingVoice.entries) DropdownMenuItem(text = { Text(voiceLabel(option)) }, onClick = {
                    open = false
                    onChange(option)
                })
            }
        }
        GhostButton(stringResource(R.string.dubbing_listen)) { Services.dubber.preview(voice) }
    }
}

@Composable
private fun voiceLabel(voice: DubbingVoice): String = stringResource(when (voice) {
    DubbingVoice.FEMALE_1 -> R.string.dubbing_voice_female_1
    DubbingVoice.FEMALE_2 -> R.string.dubbing_voice_female_2
    DubbingVoice.FEMALE_3 -> R.string.dubbing_voice_female_3
    DubbingVoice.MALE_1 -> R.string.dubbing_voice_male_1
    DubbingVoice.MALE_2 -> R.string.dubbing_voice_male_2
    DubbingVoice.MALE_3 -> R.string.dubbing_voice_male_3
})

/** "OLD MAN" → "Old Man" (Mac/iPhone DubbingCard ile aynı). */
private fun displayName(name: String): String =
    name.lowercase().split(' ').joinToString(" ") { word -> word.replaceFirstChar { it.uppercase() } }
