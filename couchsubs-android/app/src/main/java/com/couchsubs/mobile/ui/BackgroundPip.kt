// SPDX-License-Identifier: AGPL-3.0-only
// "Arka planda sürdür (Resim içinde resim)": çeviri sürerken uygulamadan çıkınca oyun görüntüsü ve canlı altyazı küçük
// pencerede kalır (iPhone'daki BackgroundPiP ile aynı ad, açıklama ve görünüm). Çevirinin kendisi Android'de ön plan
// hizmetinde (TranslationService, connectedDevice) ekran kilitliyken de sürer; pencere yalnız görüntüdür.
package com.couchsubs.mobile.ui

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.couchsubs.mobile.Services
import com.couchsubs.mobile.service.FramePreview
import com.couchsubs.mobile.service.LiveStatus

object BackgroundPip {
    private const val TAG = "CouchSubsPip"

    /** Çeviri sürüyor ve ayar açık: uygulamadan çıkınca pencere açılır. */
    fun eligible(running: Boolean, enabled: Boolean, supported: Boolean): Boolean = running && enabled && supported

    fun supported(activity: Activity): Boolean =
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    fun wanted(activity: Activity, status: LiveStatus): Boolean =
        eligible(status.running, Services.settings.backgroundPip, supported(activity))

    private fun params(autoEnter: Boolean): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        // Android 12+: sistem, ana ekrana dönülürken pencereyi kendisi açar (geçiş akıcı); öncesinde onUserLeaveHint.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setAutoEnterEnabled(autoEnter).setSeamlessResizeEnabled(false)
        return builder.build()
    }

    /** Çeviri başladı/durdu ya da ayar değişti: Android 12+'da kendiliğinden açılma buna göre açılır/kapanır. */
    fun update(activity: Activity, wanted: Boolean) {
        if (!supported(activity)) return
        try {
            activity.setPictureInPictureParams(params(wanted))
        } catch (error: RuntimeException) {
            // Bazı üreticilerde PiP kapalı (ayarlardan "Resim içinde resim" izni alınmış): sessizce geçilir.
            Log.w(TAG, "PiP ayarlanamadı", error)
        }
    }

    /** Kullanıcı uygulamadan çıkıyor (ana ekran, son uygulamalar). Android 11 ve öncesinde pencere burada açılır. */
    fun onUserLeave(activity: Activity, wanted: Boolean) {
        if (!wanted || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        try {
            activity.enterPictureInPictureMode(params(false))
        } catch (error: RuntimeException) {
            Log.w(TAG, "PiP açılamadı", error)
        }
    }
}

/** Küçük pencerenin içeriği: oyun görüntüsü ve altta canlı altyazı (iPhone'daki PiP karesiyle aynı düzen). */
@Composable
fun PipSubtitleView(status: LiveStatus) {
    DisposableEffect(Unit) {
        FramePreview.watch(true)
        onDispose { FramePreview.watch(false) }
    }
    val frame by FramePreview.frame.collectAsState()
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val image = frame
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        } else {
            Text("CouchSubs", color = Color.White.copy(alpha = 0.5f), fontSize = 18.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.Center))
        }
        val line = status.current.trim()
        if (line.isNotEmpty()) {
            Text(line, color = Color.White, fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.72f)).padding(horizontal = 8.dp, vertical = 6.dp))
        }
    }
}
