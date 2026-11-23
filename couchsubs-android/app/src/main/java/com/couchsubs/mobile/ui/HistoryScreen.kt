// SPDX-License-Identifier: AGPL-3.0-only
// "Geçmiş" ekranı (iPhone'daki HistoryScreen ile aynı): bu ve önceki oturumlarda çevrilen son satırlar, en yenisi üstte.
package com.couchsubs.mobile.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.core.SubtitleHistory
import java.text.DateFormat
import java.util.Date

@Composable
fun HistoryScreen(onBack: (() -> Unit)?) {
    val context = LocalContext.current
    val version by Services.historyVersion.collectAsState()
    val entries = remember(version) { Services.history.entries }
    var copiedAll by remember(version) { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    ScreenScaffold(top = { TopBar(stringResource(R.string.history), onBack = onBack) }, bottom = {
        if (entries.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            SecondaryButton(stringResource(if (copiedAll) R.string.history_copied else R.string.history_copy), Modifier.weight(1f)) {
                copy(context, SubtitleHistory.plainText(entries))
                copiedAll = true
            }
            DestructiveButton(stringResource(R.string.history_clear), Modifier.weight(1f)) { confirmClear = true }
        }
    }) {
        Text(stringResource(R.string.history_note, SubtitleHistory.DEFAULT_LIMIT), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        if (entries.isEmpty()) BodyText(stringResource(R.string.history_empty))
        else RowList(entries.map { entry -> { HistoryRow(entry) } })
    }
    if (confirmClear) AlertDialog(
        onDismissRequest = { confirmClear = false },
        title = { Text(stringResource(R.string.history_clear_title)) },
        text = { Text(stringResource(R.string.history_clear_body)) },
        confirmButton = {
            TextButton({
                confirmClear = false
                Services.clearHistory()
            }) { Text(stringResource(R.string.history_clear), color = Tokens.Color.danger) }
        },
        dismissButton = { TextButton({ confirmClear = false }) { Text(stringResource(R.string.cancel)) } },
        containerColor = Tokens.Color.surface2,
    )
}

/**
 * Bir satır: saat ve kaynak, Türkçe, altında İngilizcesi. Basılı tutunca kopyalanır: titreşim ve Android 13 öncesinde
 * "Kopyalandı" bildirimi (13 ve sonrasında sistem panoya kopyalandığını kendisi gösterir). Tek dokunuşun işi yoktur;
 * basış dalgası çıkmaz, ekran okuyucu satırda yalnız "Kopyala" eylemini sunar.
 */
@Composable
private fun HistoryRow(entry: SubtitleHistory.Entry) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val pack = entry.origin == SubtitleHistory.PACK
    val time = remember(entry.date) { DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(entry.date)) }
    val copyLabel = stringResource(R.string.history_copy)
    fun copyLine() {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        copy(context, "${entry.translation}\n${entry.source}")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) Toast.makeText(context, R.string.history_copied, Toast.LENGTH_SHORT).show()
    }
    Column(Modifier.fillMaxWidth()
        .pointerInput(entry) { detectTapGestures(onLongPress = { copyLine() }) }
        .semantics(mergeDescendants = true) { onLongClick(copyLabel) { copyLine(); true } }
        .padding(vertical = Tokens.Space.inline), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
        Text("$time · " + stringResource(if (pack) R.string.history_pack else R.string.history_engine),
            style = Tokens.Type.mono, color = if (pack) Tokens.Color.accentText else Tokens.Color.secondary)
        Text(entry.translation, style = Tokens.Type.body.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = Tokens.Color.text)
        Text(entry.source, style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

private fun copy(context: Context, text: String) {
    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("CouchSubs", text))
}
