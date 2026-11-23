// SPDX-License-Identifier: AGPL-3.0-only
// Kurulum akışı (tuval: Telefon-Karsilama, -PSN, -PS5, -Hedef): izin → karşılama (3 sayfa) → PSN girişi (ikinci
// hesap; PsnLoginScreen.kt) → PS5 eşleme → altyazı nerede. Uygulamada hesap yoktur.
package com.couchsubs.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.platform.LocalView
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.remoteplay.ConsoleDiscovery
import com.couchsubs.mobile.remoteplay.ConsoleInfo
import com.couchsubs.mobile.remoteplay.Registration
import com.couchsubs.mobile.remoteplay.RegistrationException
import com.couchsubs.mobile.remoteplay.RegistrationFailure
import com.couchsubs.mobile.settings.SubtitleTarget
import com.couchsubs.mobile.tv.FoundTv
import com.couchsubs.mobile.tv.TvBrand
import com.couchsubs.mobile.tv.TvDiscovery
import com.couchsubs.mobile.core.ManualAddress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Karşılama: üç sayfa, yatay kaydırma, nokta göstergesi; otomatik geçiş yok. */
@Composable
fun WelcomeScreen(onDemo: () -> Unit = {}, onDone: () -> Unit) {
    val pager = rememberPagerState { 3 }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == 2
    // Açılış sesi yalnız ilk açılışta ve Ayarlar › Temel › Açılış Sesi açıkken (Mac ve iPhone ile aynı).
    LaunchedEffect(Unit) { if (Services.settings.startupSound && !Services.settings.welcomeSeen) StartupChime.play() }
    // Perde: karşılamada ortam ışığı; başlık üstte, örnek kart altında; ilerleme noktaları (etkin nokta amber ve uzun).
    val gate = motionGate()
    ScreenScaffold(scroll = false, ambient = true, top = {
        Row(Modifier.fillMaxWidth().heightIn(min = Tokens.Control.icon), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            if (!last) GhostButton(stringResource(R.string.skip), onClick = onDone)
        }
    }, bottom = {
        Row(Modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
            repeat(3) { index ->
                val on = pager.currentPage == index
                val width by animateDpAsState(if (on) 24.dp else 8.dp, perdeTween(Tokens.Motion.medium, gate), label = "dot")
                Box(Modifier.size(width, 8.dp).background(if (on) Tokens.Color.accent else Tokens.Color.borderStrong, CircleShape))
            }
        }
        PrimaryButton(stringResource(if (last) R.string.welcome_start else R.string.next)) {
            if (last) onDone() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
        }
        // Kurulumdan önce: konsolu olmayan (ve mağaza incelemesi) uygulamayı örnek görüntülerle dener.
        GhostButton(stringResource(R.string.demo_mode_try), Modifier.fillMaxWidth(), onClick = onDemo)
    }) {
        HorizontalPager(pager, Modifier.fillMaxWidth().weight(1f), verticalAlignment = Alignment.Top) { page ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Tokens.Space.cards)) {
                when (page) {
                    0 -> {
                        Heading(stringResource(R.string.welcome1_title), stringResource(R.string.welcome1_body))
                        Tile(Modifier.fillMaxWidth(), spacing = Tokens.Space.gap) {
                            Text(stringResource(R.string.welcome1_sample_en), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                            Text(stringResource(R.string.welcome1_sample_tr), style = Tokens.Type.cardTitle, color = Tokens.Color.text)
                            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                                StatusChip(stringResource(R.string.perde_paired), ChipTone.OK)
                                StatusChip(stringResource(R.string.perde_ready_translation), ChipTone.AMBER, dot = false)
                            }
                        }
                    }
                    1 -> {
                        Heading(stringResource(R.string.welcome2_title), stringResource(R.string.welcome2_body))
                        // Tipografik kapak rafı: hazır paketli oyunlar (gerçek kapak görseli yok).
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                            listOf("Grand Theft Auto V" to stringResource(R.string.welcome2_gta),
                                "Red Dead Redemption 2" to stringResource(R.string.welcome2_rdr_lines),
                                "Mafia" to stringResource(R.string.welcome2_maf_lines)).forEachIndexed { index, (title, lines) ->
                                BoxWithConstraints(Modifier.weight(1f)) { val coverWidth = maxWidth
                                    Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.titleToBody)) {
                                        GameCover(title, selected = index == 0, width = coverWidth)
                                        Text(lines, style = Tokens.Type.captionNumeric, color = Tokens.Color.secondary, maxLines = 2)
                                    }
                                }
                            }
                        }
                    }
                    else -> {
                        Heading(stringResource(R.string.welcome3_title), stringResource(R.string.welcome3_body))
                        TwoColumns(
                            { StatusTile(CouchIcons.Tv, stringResource(R.string.welcome3_tv_label), stringResource(R.string.welcome3_tv), it, iconTone = IconTone.AMBER) },
                            { StatusTile(CouchIcons.Smartphone, stringResource(R.string.welcome3_phone_label), stringResource(R.string.welcome3_phone), it, iconTone = IconTone.TEAL) },
                        )
                        NoticeBox(stringResource(R.string.welcome3_wifi_body), NoticeTone.INFO, stringResource(R.string.welcome3_wifi))
                    }
                }
            }
        }
    }
}

/** Kurulumda PSN ve PS5 adımlarının sağ üstünde "Şimdilik geç" (PS5'siz de uygulama gezilebilsin). */
@Composable
internal fun SkipAction(onSkip: (() -> Unit)?) {
    if (onSkip != null) GhostButton(stringResource(R.string.skip_for_now), onClick = onSkip)
}

@Composable
fun InfoDialog(title: String, body: String, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, containerColor = Tokens.Color.surface2,
        title = { Text(title, style = Tokens.Type.headline, color = Tokens.Color.text) },
        text = { Text(body, style = Tokens.Type.body, color = Tokens.Color.secondary) },
        confirmButton = { TextButton(onDismiss) { Text(stringResource(R.string.ok), style = Tokens.Type.headline, color = Tokens.Color.accentText) } })
}

@Composable
fun PairScreen(onBack: (() -> Unit)? = null, onSkip: (() -> Unit)? = null, onDone: () -> Unit) {
    val settings = Services.settings
    var consoles by remember { mutableStateOf<List<ConsoleInfo>?>(null) }
    var host by remember { mutableStateOf(settings.console?.host ?: "") }
    var code by remember { mutableStateOf("") }
    var manual by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var addressError by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val failures = registrationErrors()
    LaunchedEffect(Unit) {
        consoles = withContext(Dispatchers.IO) { ConsoleDiscovery.discover(null, 3000) }
        if (host.isEmpty()) consoles?.firstOrNull()?.let { host = it.host }
        if (consoles.isNullOrEmpty()) manual = true
    }
    val pin = Registration.parsePin(code)
    // Perde başarı anı: "Eşleşti" (ışın + yaylı tik + başarı titreşimi), ardından sonraki adım.
    var paired by remember { mutableStateOf<String?>(null) }
    val view = LocalView.current
    Box(Modifier.fillMaxSize()) {
    ScreenScaffold(ambient = true, top = { TopBar(onBack = onBack) { SkipAction(onSkip) } }, bottom = {
        if (!manual) GhostButton(stringResource(R.string.pair_not_found)) { manual = true }
        PrimaryButton(stringResource(R.string.pair_button), enabled = !working && pin != null && host.isNotBlank()) {
            val accountId = settings.accountId ?: return@PrimaryButton
            // Elle yazılan adres temizlenir ("192.168.1.5:3000", "http://…", virgüllü yazım); adres değilse söylenir (#50).
            val address = ManualAddress.normalize(host)
            if (address == null) {
                problem = null
                addressError = true
                return@PrimaryButton
            }
            addressError = false
            working = true
            problem = null
            scope.launch {
                try {
                    val console = withContext(Dispatchers.IO) { Registration.register(address, accountId, pin!!) }
                    settings.console = console
                    paired = console.name.ifEmpty { address }
                    kotlinx.coroutines.delay(CELEBRATION_MS + 100)
                    onDone()
                } catch (error: RegistrationException) {
                    Haptics.error(view)
                    problem = failures(error.failure) + (error.detail?.let { " ($it)" } ?: "")
                } catch (error: Exception) {
                    Haptics.error(view)
                    problem = error.message
                } finally {
                    working = false
                }
            }
        }
    }) {
        Heading(stringResource(R.string.pair_title), stringResource(R.string.pair_body), stringResource(R.string.setup_step, 2))
        when (val list = consoles) {
            null -> Tile(Modifier.fillMaxWidth()) { Text(stringResource(R.string.pair_searching), style = Tokens.Type.body, color = Tokens.Color.secondary) }
            else -> list.forEach { console ->
                Tile(Modifier.fillMaxWidth(), style = if (host == console.host) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = { host = console.host }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                        TileIcon(Icons.Filled.Check, Tokens.Color.success)
                        Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                            Text(stringResource(R.string.pair_found, console.name), style = Tokens.Type.headline, color = Tokens.Color.text)
                            Text(stringResource(R.string.pair_same_wifi, console.host), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                        }
                    }
                }
            }
        }
        if (manual) Field(host, { host = it; addressError = false }, stringResource(R.string.pair_address), keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri))
        if (addressError) NoteTile(stringResource(R.string.address_invalid))
        Tile(Modifier.fillMaxWidth()) {
            TileLabel(stringResource(R.string.pair_code))
            // Görünmez alan rakamları alır; kutular gösterir.
            Box {
                CodeCells(code.filter { it.isDigit() })
                BasicTextField(code, { code = it.filter { c -> c.isDigit() }.take(8) }, Modifier.matchParentSizeCompat().alpha(0.01f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
            }
            Text(stringResource(R.string.pair_code_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        }
        problem?.let { NoteTile(stringResource(R.string.pair_failed, it)) }
        // PS5 bağlıyken "Uzaktan Oynama bağlandı" yazısı kalıcıdır; bildirim ayarı değil, bu ayar gizler (GitHub #177).
        Text(stringResource(R.string.pair_hide_status), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        if (working) Text(stringResource(R.string.pair_working), style = Tokens.Type.body, color = Tokens.Color.secondary)
    }
    paired?.let { SuccessOverlay(stringResource(R.string.perde_paired), it) }
    }
}

private fun Modifier.matchParentSizeCompat() = this.fillMaxWidth().height(48.dp)

/** Kayıt hatalarının Türkçesi (Windows'taki iletilerle aynı anlam). */
@Composable
fun registrationErrors(): (RegistrationFailure) -> String {
    val context = LocalContext.current
    return { failure ->
        context.getString(when (failure) {
            RegistrationFailure.WRONG_ACCOUNT -> R.string.regist_wrong_account
            RegistrationFailure.WRONG_CODE -> R.string.regist_wrong_code
            RegistrationFailure.IN_USE -> R.string.regist_in_use
            RegistrationFailure.VERSION_MISMATCH -> R.string.regist_version
            RegistrationFailure.CONSOLE_CRASHED -> R.string.regist_crashed
            RegistrationFailure.BAD_ADDRESS -> R.string.regist_bad_address
            RegistrationFailure.NO_ANSWER -> R.string.regist_no_answer
            RegistrationFailure.NO_REPLY -> R.string.regist_no_reply
            RegistrationFailure.PAIRING_CLOSED -> R.string.regist_pairing_closed
            RegistrationFailure.CONNECT_FAILED -> R.string.regist_connect_failed
            RegistrationFailure.NO_FREE_PORT -> R.string.regist_no_free_port
            RegistrationFailure.FAILED -> R.string.regist_failed
        })
    }
}

@Composable
fun TargetScreen(onBack: (() -> Unit)? = null, onTvInstall: (() -> Unit)? = null, onDone: () -> Unit) {
    val context = LocalContext.current
    val settings = Services.settings
    var target by remember { mutableStateOf(settings.target) }
    var tvs by remember { mutableStateOf<List<FoundTv>?>(null) }
    // Seçilen TV: çeviride açılacak ve önde tutulacak TV (iPhone ile aynı; TvChoice).
    var chosen by remember { mutableStateOf(settings.installedTv) }
    var chosenName by remember { mutableStateOf(settings.tvName) }
    var showManual by remember { mutableStateOf(false) }
    var searchVersion by remember { mutableStateOf(0) }
    LaunchedEffect(searchVersion) {
        tvs = null
        tvs = withContext(Dispatchers.IO) { runCatching { TvDiscovery.search() }.getOrDefault(emptyList()) }
    }
    fun choose(tv: FoundTv) {
        // Android TV'nin adresi bilinmiyorsa (elle seçildi) TV uygulaması telefonu kendisi bulur; kayıt yalnız adla olur.
        if (tv.host.isNotBlank()) chosen = com.couchsubs.mobile.tv.TvChoice.select(chosen, tv).also { settings.installedTv = it }
        chosenName = tv.name
        settings.tvName = tv.name
        if (!target.showsOnTv) target = SubtitleTarget.TV
    }
    ScreenScaffold(top = { TopBar(onBack = onBack) }, bottom = {
        PrimaryButton(stringResource(R.string.next_continue)) {
            settings.target = target
            // Seçim yapılmadıysa ağda görülen ilk TV kullanılır (eski davranış).
            if (chosen == null && target.showsOnTv) tvs?.firstOrNull()?.let { choose(it) }
            settings.onboarded = true
            onDone()
        }
    }) {
        Heading(stringResource(R.string.target_title), stringResource(R.string.target_body), if (onBack == null) stringResource(R.string.setup_step, 3) else null)
        Tile(Modifier.fillMaxWidth(), style = if (target == SubtitleTarget.TV) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = { target = SubtitleTarget.TV }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                TileIcon(CouchIcons.Tv)
                Text(stringResource(R.string.target_tv), style = Tokens.Type.headline, color = Tokens.Color.text, modifier = Modifier.weight(1f))
                if (target == SubtitleTarget.TV) SelectedCheck()
            }
            when (val found = tvs) {
                null -> Text(stringResource(R.string.target_searching), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                // Bulunamayınca ne yapılacağı da söylenir: TV uygulaması yoksa buradan kurulur; monitör ya da akıllı olmayan
                // TV'de "Bu telefonda" seçilir (iPhone'daki gibi; kullanıcı monitörde "Ağda TV bulunamadı"da kalmıştı).
                else -> if (found.isEmpty()) Text(stringResource(if (onTvInstall != null) R.string.target_tvs_none_help else R.string.target_tvs_none),
                    style = Tokens.Type.caption, color = Tokens.Color.secondary)
                else Unit
            }
            // Bulunan TV'ler (kayıtlı TV ağda görünmese de en üstte): dokununca seçilir.
            val listed = com.couchsubs.mobile.tv.TvChoice.list(tvs.orEmpty(), chosen, chosenName)
            listed.forEach { tv ->
                val selected = com.couchsubs.mobile.tv.TvChoice.isSelected(tv, chosen)
                Row(Modifier.fillMaxWidth().clickable { choose(tv) }.padding(vertical = Tokens.Space.inline),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(tv.name, style = Tokens.Type.body, color = Tokens.Color.text)
                        Text(brandName(tv.brand), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                    }
                    if (selected) SelectedCheck()
                    else if (tvs?.any { it.host == tv.host && it.brand == tv.brand } == true) StatusLabel(stringResource(R.string.target_tv_on_network))
                }
            }
            if (tvs != null) GhostButton(stringResource(R.string.target_search_again)) { searchVersion++ }
            if (chosen != null) Text(stringResource(R.string.target_tv_selected_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            Text(stringResource(R.string.target_tv_body), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            // TV uygulamasını bilgisayarsız, bu telefondan kurmak (ilk kurulumda da).
            if (onTvInstall != null) GhostButton(stringResource(R.string.tvinstall_entry), onClick = onTvInstall)
        }
        // Mac ve Windows'taki "İkisi de": altyazı hem TV'de hem bu telefonda görünür.
        Tile(Modifier.fillMaxWidth(), style = if (target == SubtitleTarget.BOTH) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = { target = SubtitleTarget.BOTH }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                TileIcon(CouchIcons.Tv)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.target_both), style = Tokens.Type.headline, color = Tokens.Color.text)
                    Text(stringResource(R.string.target_both_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
                if (target == SubtitleTarget.BOTH) SelectedCheck()
            }
        }
        TwoColumns(
            { StatusTile(CouchIcons.Smartphone, stringResource(R.string.target_phone_note), stringResource(R.string.target_phone), it,
                style = if (target == SubtitleTarget.PHONE) TileStyle.ACTIVE else TileStyle.NORMAL,
                corner = { if (target == SubtitleTarget.PHONE) SelectedCheck() }, onClick = { target = SubtitleTarget.PHONE }) },
            { StatusTile(Icons.Filled.Info, stringResource(R.string.target_unlisted_note), stringResource(R.string.target_unlisted), it,
                onClick = { showManual = true }) },
        )
        if (showManual) ManualTvDialog(onDismiss = { showManual = false }, onSupported = { open(context, context.getString(R.string.url_tvs)) }) { tv ->
            showManual = false
            choose(tv)
        }
        // Mac ve Windows'taki "Yalnız OBS (yayın)": TV aranmaz, bu telefonda altyazı ekranı açılmaz; altyazı yalnız aynı Wi-Fi'daki
        // bilgisayarda OBS'in tarayıcı kaynağına gider (iPhone ile aynı). Seçiliyken adres ve kopyala düğmesi görünür.
        Tile(Modifier.fillMaxWidth(), style = if (target == SubtitleTarget.OBS) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = { target = SubtitleTarget.OBS }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                TileIcon(CouchIcons.Tv)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.target_obs), style = Tokens.Type.headline, color = Tokens.Color.text)
                    Text(stringResource(R.string.target_obs_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                }
                if (target == SubtitleTarget.OBS) SelectedCheck()
            }
            if (target == SubtitleTarget.OBS) ObsOnlyAddress()
        }
        // TV'si olmayan ya da monitörde oynayan için: hangi hedef seçilirse seçilsin altyazı ayrıca bir tarayıcıda da görünür.
        SecondScreenTile()
        // TV kurulumu bitti: her çeviride TV uygulaması kendiliğinden açılmaya çalışılır; açılmazsa TV'den açılır.
        if (onBack == null && target.showsOnTv && settings.installedTv != null)
            Text(stringResource(R.string.tv_open_wizard_note), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    }
}

/**
 * "TV'm listede yok" (iPhone ile aynı): marka seçilir, LG ve Samsung'da IP adresi yazılır (temizlenir, geçersizse
 * söylenir); Android TV'de adres gerekmez, oradaki uygulama telefonu kendisi bulur.
 */
@Composable
private fun ManualTvDialog(onDismiss: () -> Unit, onSupported: () -> Unit, onConnect: (FoundTv) -> Unit) {
    var brand by remember { mutableStateOf(TvBrand.LG) }
    var host by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.target_unlisted_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                Text(stringResource(R.string.target_unlisted_body), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                Segmented(listOf("LG", "Samsung", "Android TV"), TvBrand.entries.indexOf(brand)) { brand = TvBrand.entries[it]; invalid = false }
                if (brand != TvBrand.ANDROID_TV) {
                    Field(host, { host = it; invalid = false }, stringResource(R.string.target_ip_hint),
                        keyboard = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Uri))
                    if (invalid) Text(stringResource(R.string.address_invalid), style = Tokens.Type.caption, color = Tokens.Color.danger)
                } else Text(stringResource(R.string.target_android_tv_found), style = Tokens.Type.caption, color = Tokens.Color.secondary)
                TextButton(onSupported) { Text(stringResource(R.string.target_unlisted_note)) }
            }
        },
        confirmButton = {
            TextButton({
                if (brand == TvBrand.ANDROID_TV) onConnect(FoundTv("Android TV", "", brand))
                else com.couchsubs.mobile.core.ManualAddress.normalize(host)?.let { onConnect(FoundTv(it, it, brand)) } ?: run { invalid = true }
            }, enabled = brand == TvBrand.ANDROID_TV || host.isNotBlank()) { Text(stringResource(R.string.target_connect)) }
        },
        dismissButton = { TextButton(onDismiss) { Text(stringResource(R.string.cancel)) } },
        containerColor = Tokens.Color.surface2,
    )
}

/** "Yalnız OBS (yayın)": OBS'in tarayıcı kaynağına yazılacak adres (bu telefonun ağ adresiyle) ve kopyala düğmesi. */
@Composable
private fun ObsOnlyAddress() {
    val context = LocalContext.current
    val address = remember { com.couchsubs.mobile.service.TranslationService.viewerAddress() }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            kotlinx.coroutines.delay(1500)
            copied = false
        }
    }
    Text(stringResource(R.string.target_obs_body), style = Tokens.Type.caption, color = Tokens.Color.secondary)
    address?.let { shown ->
        androidx.compose.foundation.text.selection.SelectionContainer {
            Text(shown, style = Tokens.Type.caption.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), color = Tokens.Color.text)
        }
        SecondaryButton(stringResource(if (copied) R.string.history_copied else R.string.history_copy), Modifier.fillMaxWidth()) {
            context.getSystemService(android.content.ClipboardManager::class.java)?.setPrimaryClip(android.content.ClipData.newPlainText("CouchSubs", shown))
            copied = true
        }
    }
}

fun brandName(brand: TvBrand) = when (brand) {
    TvBrand.LG -> "LG"
    TvBrand.SAMSUNG -> "Samsung"
    TvBrand.ANDROID_TV -> "Android TV"
}
