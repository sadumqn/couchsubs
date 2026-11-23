// SPDX-License-Identifier: AGPL-3.0-only
// Geliştirici imzası: ana ekranın, Profil'in ve Ayarlar'ın en altında, içerik bittikten sonra (iPhone'daki
// DeveloperSignature ile aynı). Soluk "Geliştirici" yazısı, altında ondan biraz büyük Enmera logosu; logoya dokununca
// enmera.com.tr sistem tarayıcısında açılır.
package com.couchsubs.mobile.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.dp
import com.couchsubs.mobile.R

private const val ENMERA_URL = "https://enmera.com.tr"

@Composable
fun DeveloperSignature() {
    val context = LocalContext.current
    val label = stringResource(R.string.developer_a11y)
    fun open() {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(ENMERA_URL)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
        }
    }
    // Logo uygulamanın görünümüne göre: koyu zeminde beyaz, açık zeminde siyah. Uygulama sistem temasından bağımsız hep
    // koyu olduğundan drawable-night yerine zeminin parlaklığına bakılır.
    val logo = if (Tokens.Color.bg.luminance() < 0.5f) R.drawable.enmera_logo_white else R.drawable.enmera_logo_black
    Column(
        Modifier.fillMaxWidth().padding(top = Tokens.Space.screen)
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                onClick { open(); true }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.hair),
    ) {
        Text(stringResource(R.string.developer_label), style = Tokens.Type.caption, color = Tokens.Color.secondary)
        Image(
            painterResource(logo), contentDescription = null, contentScale = ContentScale.Fit,
            modifier = Modifier.clickable(onClick = ::open).padding(horizontal = Tokens.Space.tile, vertical = Tokens.Space.gap)
                .height(20.dp).alpha(0.85f),
        )
    }
}
