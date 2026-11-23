// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.couchsubs.mobile.R
import com.couchsubs.mobile.settings.AppSettings
import com.couchsubs.mobile.settings.EngineChoice
import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.KeyCheck
import com.couchsubs.mobile.translation.LocalAiServer
import com.couchsubs.mobile.translation.OnlineKeyState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * "Yerel model (Ollama, LM Studio)" motorunun alanları: Mac/Windows ve iPhone'daki gibi sunucu adresi, model adı, isteğe
 * bağlı anahtar ve "Bağlantıyı dene". Model telefonda çalışmaz; sunucu aynı ağdaki bir bilgisayardır.
 */
@Composable
fun LocalAiSection(settings: AppSettings) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var address by remember { mutableStateOf(settings.localAiBaseUrl) }
    var model by remember { mutableStateOf(settings.localAiModel) }
    var key by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf(!settings.apiKey(EngineChoice.LOCAL).isNullOrBlank()) }
    var checking by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    Field(address, { value ->
        address = value
        result = null
        if (LocalAiServer.normalize(value) != null || value.isBlank()) settings.localAiBaseUrl = value
    }, stringResource(R.string.local_ai_address), placeholder = LocalAiServer.PHONE_EXAMPLE,
        keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri))
    if (address.isNotBlank() && LocalAiServer.normalize(address) == null)
        Text(stringResource(R.string.local_ai_invalid_address, LocalAiServer.PHONE_EXAMPLE), style = Tokens.Type.caption, color = Tokens.Color.danger)
    Field(model, { value ->
        model = value
        result = null
        if (value.isNotBlank()) settings.localAiModel = value
    }, stringResource(R.string.local_ai_model), placeholder = LocalAiServer.DEFAULT_MODEL)
    Text(stringResource(R.string.local_ai_network_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    Text(stringResource(R.string.local_ai_model_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    if (saved) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatusLabel(stringResource(R.string.local_ai_key_saved))
            Spacer(Modifier.weight(1f))
            GhostButton(stringResource(R.string.local_ai_key_remove)) {
                settings.setApiKey(EngineChoice.LOCAL, null)
                saved = false
                result = null
            }
        }
    } else {
        Field(key, { key = it }, stringResource(R.string.local_ai_key), secret = true)
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        SecondaryButton(stringResource(if (checking) R.string.local_ai_testing else R.string.local_ai_test),
            enabled = !checking && LocalAiServer.normalize(address) != null) {
            val server = settings.localAiServer ?: return@SecondaryButton
            val typed = key.trim()
            checking = true
            result = null
            scope.launch {
                val (state, sample) = withContext(Dispatchers.IO) {
                    KeyCheck.aiSample(AiProvider.LOCAL, typed.ifEmpty { settings.apiKey(EngineChoice.LOCAL).orEmpty() },
                        AiModel(server.model, server.model), server = server)
                }
                // Yazılan anahtar sunucu kabul ettiyse gizli depoya yazılır (Mac/iPhone testLocalAI ile aynı).
                if (typed.isNotEmpty() && KeyCheck.accepted(state)) {
                    if (settings.storeApiKey(EngineChoice.LOCAL, typed)) { saved = true; key = "" }
                }
                result = if (state == OnlineKeyState.VALID) context.getString(R.string.local_ai_works, sample.orEmpty())
                    else describeLocal(context, state, server)
                checking = false
            }
        }
        GhostButton(stringResource(R.string.local_ai_download)) { open(context, "https://ollama.com/download") }
    }
    result?.let { Text(it, style = Tokens.Type.caption, color = Tokens.Color.secondary) }
}

/** Yerel model sunucusunun durum iletisi (Mac/iPhone LocalAIText.describe ile aynı metinler). */
fun describeLocal(context: Context, state: OnlineKeyState, server: LocalAiServer): String = when (state) {
    OnlineKeyState.VALID -> context.getString(R.string.local_ai_works, "")
    OnlineKeyState.INVALID -> context.getString(R.string.local_ai_rejected_key)
    OnlineKeyState.QUOTA_EXCEEDED -> context.getString(R.string.local_ai_busy)
    OnlineKeyState.MODEL_REJECTED ->
        if (server.kind == LocalAiServer.Kind.LM_STUDIO) context.getString(R.string.local_ai_lmstudio_model, server.model)
        else context.getString(R.string.local_ai_ollama_model, server.model)
    else -> when (server.kind) {
        LocalAiServer.Kind.OLLAMA -> context.getString(R.string.local_ai_ollama_down, server.address, server.model)
        LocalAiServer.Kind.LM_STUDIO -> context.getString(R.string.local_ai_lmstudio_down, server.address)
        LocalAiServer.Kind.OTHER -> context.getString(R.string.local_ai_other_down, server.address)
    }
}
