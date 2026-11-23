// SPDX-License-Identifier: AGPL-3.0-only
// TV kurulumunun ortak Perde parçaları (iPhone TVInstallParts.swift ile aynı): liste başlığı + arama halkası, aranıyor
// kartı, TV kartı, numaralı adım listesi, canlı adım çizelgesi, başarı anı ("Kurulum Tamam") ve hata kutusu (neden,
// numaralı çözüm, ayrıntı, Günlüğü Paylaş; belirince hata titreşimi). Üç marka (Samsung, LG, Android TV) aynı parçaları kullanır.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.tv.samsung.InstallStep

/** Listenin başlığı (kart başlığı) ve sağda tarama sürerken arama halkası + "TV'ler aranıyor…". */
@Composable
internal fun InstallListTitle(text: String, searching: Boolean) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
        Text(text, style = Tokens.Type.cardTitle, color = Tokens.Color.text, modifier = Modifier.weight(1f).semantics { heading() })
        if (searching) {
            SearchRings(22.dp)
            Text(stringResource(R.string.tvinstall_searching), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
    }
}

/** Tarama sürerken listenin yerinde duran kart: büyük arama halkası ve yazı. */
@Composable
internal fun InstallSearching() {
    Tile(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().heightIn(min = Tokens.Control.row), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            SearchRings(40.dp)
            Text(stringResource(R.string.tvinstall_searching), style = Tokens.Type.body, color = Tokens.Color.secondary)
        }
    }
}

/** TV bulunamadı: düz bilgi kartı. */
@Composable
internal fun InstallEmpty(text: String) {
    Tile(Modifier.fillMaxWidth()) { Text(text, style = Tokens.Type.body, color = Tokens.Color.secondary) }
}

/**
 * Numaralı kurulum adımları (iPhone NumberedStep): solda yuvarlak içinde sıra numarası, sağda adım. Tıklanmaz; seçenek
 * gibi görünmez, sıkı aralıkla dizilir.
 */
@Composable
internal fun InstallSteps(title: String, steps: List<String>, extra: (@Composable () -> Unit)? = null) {
    Tile(Modifier.fillMaxWidth(), spacing = Tokens.Space.gap) {
        SectionTitle(title)
        steps.forEachIndexed { index, step ->
            // Metinlerde sıra numarası yazılıysa ("1. …") yuvarlakta durduğu için yazıdan çıkar.
            NumberedStep(index + 1, step.replace(Regex("^\\d+\\.\\s*"), ""))
            if (index == steps.lastIndex - 1) extra?.invoke()
        }
    }
}

@Composable
internal fun NumberedStep(number: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
        Box(Modifier.size(24.dp).background(Tokens.Color.field, CircleShape), contentAlignment = Alignment.Center) {
            Text("$number", style = Tokens.Type.small.copy(fontWeight = FontWeight.Bold), color = Tokens.Color.text)
        }
        Text(text, style = Tokens.Type.body, color = Tokens.Color.text, modifier = Modifier.weight(1f))
    }
}

/** Kurulumun altı aşaması (iPhone InstallStage); her [InstallStep] birine düşer. */
internal enum class InstallStage(val title: Int) {
    CONNECT(R.string.stage_connect), APPROVE(R.string.stage_approve), SEND(R.string.stage_send),
    INSTALL(R.string.stage_install), OPEN(R.string.stage_open), READY(R.string.stage_ready);

    companion object {
        fun of(step: InstallStep): InstallStage = when (step) {
            InstallStep.CONNECTING, InstallStep.READING, InstallStep.PAIRING -> CONNECT
            InstallStep.APPROVE_ON_TV, InstallStep.KEY, InstallStep.SIGN_IN, InstallStep.OPEN_PLAY -> APPROVE
            InstallStep.CERTIFICATE, InstallStep.SIGNING -> SEND
            InstallStep.INSTALLING, InstallStep.UNINSTALLING -> INSTALL
            InstallStep.LAUNCHING -> OPEN
        }
    }
}

/** Canlı adım çizelgesi: geçilen aşamalar amber tik, süren aşama yükleyicili ve altında o anki ayrıntı, kalanlar soluk. */
@Composable
internal fun InstallTimeline(step: InstallStep?, done: Boolean = false) {
    val current = if (done) InstallStage.READY else step?.let { InstallStage.of(it) } ?: InstallStage.CONNECT
    StepTimeline(InstallStage.entries.map { stage ->
        val phase = when {
            done || stage.ordinal < current.ordinal -> StepPhase.DONE
            stage == current -> StepPhase.CURRENT
            else -> StepPhase.TODO
        }
        TimelineStep(stringResource(stage.title), phase, if (phase == StepPhase.CURRENT && step != null) stepText(step) else null)
    })
}

/** Kurulum sürüyor: çizelge kartı. */
@Composable
internal fun InstallWorking(step: InstallStep) {
    Tile(Modifier.fillMaxWidth()) { InstallTimeline(step) }
}

/** Kurulum bitti: başarı anı (ışın + yaylı tik + başarı titreşimi, ≤ 1 sn), tamam çizelgesi, sürüm ve sonraki adım. */
@Composable
internal fun InstallDone(text: String) {
    Tile(Modifier.fillMaxWidth(), style = TileStyle.ACTIVE, spacing = Tokens.Space.gap) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Celebration(64.dp) }
        InstallTimeline(null, done = true)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            Icon(Icons.Filled.CheckCircle, null, tint = Tokens.Color.successText, modifier = Modifier.size(18.dp))
            Text(text, style = Tokens.Type.headline, color = Tokens.Color.successText)
        }
        // Telefondan kuranların çoğunun bilgisayarı yoktur; TV'nin bekleme ekranı hata sanılıyordu (#113).
        Text(stringResource(R.string.tvinstall_next), style = Tokens.Type.muted, color = Tokens.Color.secondary)
    }
}

/**
 * Hata kutusu (iPhone InstallErrorBox): kırmızı ince çerçeve; üstte "Kurulum Tamamlanamadı", ilk cümle başlık (neden),
 * kalan cümleler numaralı çözüm adımları, sonraki paragraflar (TV'nin yanıtı) gri; altta Günlüğü Paylaş. "Yeniden Dene"
 * kutunun altındaki ana düğmedir. Kutu belirince hata titreşimi.
 */
@Composable
internal fun InstallErrorBox(text: String, onShareLog: () -> Unit, actions: (@Composable () -> Unit)? = null) {
    val view = LocalView.current
    LaunchedEffect(text) { Haptics.error(view) }
    val (title, steps, extra) = InstallErrorText.parse(text)
    Tile(Modifier.fillMaxWidth(), style = TileStyle.DANGER, spacing = Tokens.Space.gap) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            Icon(Icons.Filled.Warning, null, tint = Tokens.Color.danger, modifier = Modifier.size(15.dp))
            Text(stringResource(R.string.perde_install_failed), style = Tokens.Type.label, color = Tokens.Color.danger)
        }
        Text(title, style = Tokens.Type.cardTitle, color = Tokens.Color.text)
        steps.forEachIndexed { index, step -> NumberedStep(index + 1, step) }
        extra.forEach { Text(it, style = Tokens.Type.muted, color = Tokens.Color.secondary) }
        actions?.invoke()
        PerdeButton(stringResource(R.string.tvinstall_share_log), ButtonKind.SECONDARY, fullWidth = false,
            leading = { Icon(Icons.Filled.Share, null, tint = Tokens.Color.text, modifier = Modifier.size(16.dp)) }, onClick = onShareLog)
    }
}

/** Hata metnini başlık, numaralı adımlar ve ayrıntıya ayırır (iPhone InstallErrorBox.parse ile aynı kural). */
internal object InstallErrorText {
    /** İlk paragrafın ilk cümlesi başlık, kalan cümleleri adımlar; sonraki paragraflar ayrıntı. */
    fun parse(text: String): Triple<String, List<String>, List<String>> {
        val paragraphs = text.split("\n\n").map { it.trim() }.filter { it.isNotEmpty() }
        val first = paragraphs.firstOrNull() ?: return Triple(text, emptyList(), emptyList())
        val sentences = sentences(first)
        return Triple(sentences.firstOrNull() ?: first, sentences.drop(1), paragraphs.drop(1))
    }

    /** Cümlelere böler: nokta, soru ya da ünlem + boşluk + büyük harf ya da tırnak (adres ve sürüm numaraları bölünmez). */
    fun sentences(text: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        var index = 0
        while (index < text.length) {
            val character = text[index]
            current.append(character)
            if (character in ".?!" && index + 2 < text.length && text[index + 1] == ' ' &&
                (text[index + 2].isUpperCase() || text[index + 2] == '“' || text[index + 2] == '"')) {
                result += current.toString().trim()
                current.clear()
                index++
            }
            index++
        }
        if (current.isNotBlank()) result += current.toString().trim()
        return result
    }
}
