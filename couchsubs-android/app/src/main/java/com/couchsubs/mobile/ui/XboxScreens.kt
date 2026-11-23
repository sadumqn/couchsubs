// SPDX-License-Identifier: AGPL-3.0-only
// Konsol seçimi (PlayStation varsayılan, Xbox Beta) ve Xbox kurulumu: Microsoft girişi (cihaz kodu) → Xbox seçimi.
// Xbox'ta "İkinci hesap" (PSN) adımı yoktur. Windows'taki XboxLoginStep ve XboxConsoleStep'in karşılığı.
package com.couchsubs.mobile.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import com.couchsubs.mobile.R
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.settings.ConsolePlatform
import com.couchsubs.mobile.xbox.XboxConsole
import com.couchsubs.mobile.xbox.XboxDeviceCode
import com.couchsubs.mobile.xbox.XboxError
import com.couchsubs.mobile.xbox.XboxException
import com.couchsubs.mobile.xbox.XboxHome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

/** "Konsolunuz": PlayStation 5 (varsayılan) ya da Xbox (Beta). */
@Composable
fun PlatformScreen(onBack: (() -> Unit)? = null, onDone: () -> Unit) {
    val settings = Services.settings
    var chosen by remember { mutableStateOf(settings.platform) }
    ScreenScaffold(top = { TopBar(onBack = onBack) }, bottom = {
        PrimaryButton(stringResource(R.string.next)) {
            settings.platformChoice = chosen
            onDone()
        }
    }) {
        Heading(stringResource(R.string.platform_title), stringResource(R.string.platform_body))
        PlatformTile(stringResource(R.string.platform_ps), stringResource(R.string.platform_ps_body), beta = false,
            selected = chosen == ConsolePlatform.PLAYSTATION) { chosen = ConsolePlatform.PLAYSTATION }
        PlatformTile(stringResource(R.string.platform_xbox), stringResource(R.string.platform_xbox_body), beta = true,
            selected = chosen == ConsolePlatform.XBOX) { chosen = ConsolePlatform.XBOX }
        if (chosen == ConsolePlatform.XBOX) NoteTile(stringResource(R.string.xbox_beta_note), Tokens.Color.secondary)
    }
}

@Composable
private fun PlatformTile(title: String, body: String, beta: Boolean, selected: Boolean, onClick: () -> Unit) {
    Tile(Modifier.fillMaxWidth(), style = if (selected) TileStyle.ACTIVE else TileStyle.NORMAL, onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
            TileIcon(CouchIcons.Gamepad, if (selected) Tokens.Color.accentText else Tokens.Color.secondary)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) {
                    Text(title, style = Tokens.Type.headline, color = Tokens.Color.text)
                    if (beta) Pill(stringResource(R.string.beta))
                }
                Text(body, style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
            if (selected) SelectedCheck()
        }
    }
}

/**
 * Microsoft girişinin durumu ekrandan bağımsız tutulur: kullanıcı kodu tarayıcıda yazarken tablet döner ya da Android
 * etkinliği yeniden kurar; ekranın kapsamında çalışan bekleme o an iptal oluyor, kullanıcı onaylayıp döndüğünde giriş
 * hiç bitmiyordu. Bekleme kodun süresi dolana kadar sürer; geri ya da "Şimdilik geç" iptal eder.
 */
internal object XboxLoginFlow {
    var code by mutableStateOf<XboxDeviceCode?>(null)
        private set
    var working by mutableStateOf(false)
        private set
    var problem by mutableStateOf<String?>(null)
        private set
    /** Giriş bitti; ekran bunu görünce bir sonraki adıma geçer ve [consume] ile siler. */
    var completed by mutableStateOf(false)
        private set
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    fun begin(context: Context) {
        val app = context.applicationContext
        job?.cancel()
        problem = null
        completed = false
        working = true
        job = scope.launch {
            try {
                val challenge = withContext(Dispatchers.IO) { Services.xboxAuth.startDeviceCode() }
                code = challenge
                copy(app, challenge.userCode)
                if (!openLink(app, challenge.verificationUri)) problem = app.getString(R.string.xbox_login_no_browser, challenge.verificationUri)
                val active = coroutineContext
                withContext(Dispatchers.IO) { Services.xboxAuth.pollDeviceCode(challenge) { !active.isActive } }
                code = null
                completed = true
            } catch (error: XboxException) {
                problem = xboxProblem(app, error)
                code = null
            } catch (error: InterruptedException) {
                // İptal edildi.
            } catch (error: CancellationException) {
                // İptal edildi.
            } catch (error: Exception) {
                problem = error.message ?: error.javaClass.simpleName
                code = null
            } finally {
                // Yerine yeni giriş başlatıldıysa onun durumuna dokunulmaz.
                if (job === coroutineContext[Job]) working = false
            }
        }
    }

    fun cancel() {
        job?.cancel()
        job = null
        code = null
        working = false
    }

    fun consume() { completed = false }
}

/** Microsoft girişi: cihaz kodu gösterilir ve kopyalanır, Microsoft sayfası tarayıcıda açılır, onay beklenir. */
@Composable
fun XboxLoginScreen(onBack: (() -> Unit)? = null, onSkip: (() -> Unit)? = null, onDone: () -> Unit) {
    val context = LocalContext.current
    val auth = Services.xboxAuth
    val flow = XboxLoginFlow
    LaunchedEffect(flow.completed) {
        if (flow.completed) {
            flow.consume()
            onDone()
        }
    }
    val back = onBack?.let { action -> { flow.cancel(); action() } }
    val skip = onSkip?.let { action -> { flow.cancel(); action() } }
    ScreenScaffold(top = { TopBar(onBack = back) { SkipAction(skip) } }, bottom = {
        val current = flow.code
        if (current != null) GhostButton(stringResource(R.string.xbox_login_open)) {
            copy(context, current.userCode)
            openLink(context, current.verificationUri)
        }
        PrimaryButton(stringResource(R.string.xbox_login_button), enabled = !flow.working) { flow.begin(context) }
    }) {
        Heading(stringResource(R.string.xbox_login_title), stringResource(R.string.xbox_login_body), stringResource(R.string.setup_step, 1))
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Space.inline)) { Pill(stringResource(R.string.beta)) }
        if (auth.signedIn && flow.code == null) StatusLabel(stringResource(R.string.xbox_login_done))
        if (flow.code == null && !flow.working) BodyText(stringResource(R.string.xbox_login_how))
        flow.code?.let { challenge ->
            Tile(Modifier.fillMaxWidth()) {
                TileLabel(stringResource(R.string.xbox_login_code))
                Text(challenge.userCode, style = Tokens.Type.title, color = Tokens.Color.accentText,
                    modifier = Modifier.clickable(onClickLabel = stringResource(R.string.xbox_login_copy)) { copy(context, challenge.userCode) })
                Text(challenge.verificationUri.removePrefix("https://"), style = Tokens.Type.headline, color = Tokens.Color.accentText,
                    textDecoration = TextDecoration.Underline,
                    modifier = Modifier.clickable(onClickLabel = stringResource(R.string.xbox_login_open)) {
                        copy(context, challenge.userCode)
                        openLink(context, challenge.verificationUri)
                    })
                Text(stringResource(R.string.xbox_login_steps), style = Tokens.Type.caption, color = Tokens.Color.secondary)
            }
            if (flow.working) BodyText(stringResource(R.string.xbox_login_waiting))
        }
        flow.problem?.let { NoteTile(stringResource(R.string.xbox_login_failed, it)) }
    }
}

/** Hesaptaki Xbox'lar; yalnız uzaktan oynatması açık olan seçilebilir. */
@Composable
fun XboxConsoleScreen(onBack: (() -> Unit)? = null, onSkip: (() -> Unit)? = null, onSignIn: () -> Unit, onDone: () -> Unit) {
    val settings = Services.settings
    var consoles by remember { mutableStateOf<List<XboxConsole>?>(null) }
    var selected by remember { mutableStateOf(settings.xboxConsole?.id) }
    var problem by remember { mutableStateOf<String?>(null) }
    var needsSignIn by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    LaunchedEffect(attempt) {
        consoles = null
        problem = null
        try {
            val list = withContext(Dispatchers.IO) { XboxHome(Services.xboxAuth).consoles() }
            consoles = list
            if (selected == null) selected = list.firstOrNull { it.streamingEnabled }?.id
        } catch (error: XboxException) {
            needsSignIn = error.kind == XboxError.SIGN_IN_REQUIRED
            problem = xboxProblem(context, error)
            consoles = emptyList()
        } catch (error: Exception) {
            problem = error.message
            consoles = emptyList()
        }
    }
    val choice = consoles?.firstOrNull { it.id == selected && it.streamingEnabled }
    ScreenScaffold(top = { TopBar(onBack = onBack) { SkipAction(onSkip) } }, bottom = {
        GhostButton(stringResource(R.string.xbox_consoles_refresh)) { attempt++ }
        if (needsSignIn) PrimaryButton(stringResource(R.string.xbox_login_button), onClick = onSignIn)
        else PrimaryButton(stringResource(R.string.xbox_console_choose), enabled = choice != null) {
            settings.xboxConsole = choice
            onDone()
        }
    }) {
        Heading(stringResource(R.string.xbox_consoles_title), stringResource(R.string.xbox_consoles_body), stringResource(R.string.setup_step, 2))
        when (val list = consoles) {
            null -> Tile(Modifier.fillMaxWidth()) { BodyText(stringResource(R.string.xbox_consoles_searching)) }
            else -> {
                if (list.isEmpty() && problem == null) NoteTile(stringResource(R.string.xbox_consoles_empty), Tokens.Color.secondary)
                list.forEach { console ->
                    Tile(Modifier.fillMaxWidth(), style = if (selected == console.id) TileStyle.ACTIVE else TileStyle.NORMAL,
                        onClick = { if (console.streamingEnabled) selected = console.id }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.Space.gap)) {
                            if (console.streamingEnabled) TileIcon(Icons.Filled.Check, Tokens.Color.success)
                            else TileIcon(Icons.Filled.Warning, Tokens.Color.warning)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair)) {
                                Text(console.name.ifEmpty { console.model }, style = Tokens.Type.headline, color = Tokens.Color.text)
                                Text(stringResource(if (console.streamingEnabled) R.string.xbox_console_ready else R.string.xbox_console_off),
                                    style = Tokens.Type.caption, color = Tokens.Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        problem?.let { NoteTile(it) }
    }
}

/** Ekranda gösterilecek anlaşılır neden; beklenmedik yanıtta teknik ayrıntı parantez içinde. */
internal fun xboxProblem(context: Context, error: XboxException): String = when (error.kind) {
    XboxError.SIGN_IN_REQUIRED, XboxError.SIGN_IN_DECLINED -> context.getString(R.string.xbox_error_sign_in)
    XboxError.CODE_EXPIRED -> context.getString(R.string.xbox_login_expired)
    XboxError.NO_XBOX_ACCOUNT -> context.getString(R.string.xbox_error_no_account)
    XboxError.NETWORK -> context.getString(R.string.xbox_error_offline)
    else -> context.getString(R.string.xbox_error_unexpected, error.message ?: error.kind.name)
}

/** Bağlantıyı tarayıcıda açar; açacak uygulama yoksa false (kullanıcıya adres yazılır). */
private fun openLink(context: Context, url: String): Boolean = try {
    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (error: Exception) {
    false
}

private fun copy(context: Context, code: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("Microsoft", code))
    Toast.makeText(context, context.getString(R.string.xbox_login_copied), Toast.LENGTH_SHORT).show()
}
