// SPDX-License-Identifier: AGPL-3.0-only
// Uygulamaya özgü küçük çizgi simgeler (24 birimlik tuval, 2 birim çizgi, yuvarlak uç). material-icons-core'da oyun kolu,
// TV, geçmiş ve paket simgesi yok; bütün simge setini (material-icons-extended, ~30 MB) eklemek yerine burada çizilir.
// Renk, Icon'un tint'inden gelir.
package com.couchsubs.mobile.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

object CouchIcons {
    /** Oyun kolu (PS5, Xbox). */
    val Gamepad: ImageVector by lazy {
        icon("Gamepad") {
            stroke {
                // Gövde: üstte düz, altta iki tutamak.
                moveTo(7f, 7f)
                horizontalLineTo(17f)
                arcTo(4f, 4f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 21f, y1 = 11f)
                verticalLineTo(14f)
                arcTo(3f, 3f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 18f, y1 = 17f)
                lineTo(16f, 15f)
                horizontalLineTo(8f)
                lineTo(6f, 17f)
                arcTo(3f, 3f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 3f, y1 = 14f)
                verticalLineTo(11f)
                arcTo(4f, 4f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 7f, y1 = 7f)
                close()
                // Yön tuşu.
                moveTo(8f, 9.5f)
                verticalLineTo(12.5f)
                moveTo(6.5f, 11f)
                horizontalLineTo(9.5f)
            }
            fill {
                dot(15f, 10.5f, 1f)
                dot(17f, 12.5f, 1f)
            }
        }
    }

    /** TV (altyazı TV'de). */
    val Tv: ImageVector by lazy {
        icon("Tv") {
            stroke {
                moveTo(5f, 5f)
                horizontalLineTo(19f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 21f, y1 = 7f)
                verticalLineTo(15f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 19f, y1 = 17f)
                horizontalLineTo(5f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 3f, y1 = 15f)
                verticalLineTo(7f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 5f, y1 = 5f)
                close()
                // Ayak.
                moveTo(12f, 17f)
                verticalLineTo(20f)
                moveTo(8.5f, 20f)
                horizontalLineTo(15.5f)
            }
        }
    }

    /** Akıllı telefon (altyazı bu telefonda). */
    val Smartphone: ImageVector by lazy {
        icon("Smartphone") {
            stroke {
                moveTo(9f, 3f)
                horizontalLineTo(15f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 17f, y1 = 5f)
                verticalLineTo(19f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 15f, y1 = 21f)
                horizontalLineTo(9f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 7f, y1 = 19f)
                verticalLineTo(5f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, x1 = 9f, y1 = 3f)
                close()
                moveTo(11f, 18f)
                horizontalLineTo(13f)
            }
        }
    }

    /** Geçmiş: geriye dönen ok ve saat kolları. */
    val History: ImageVector by lazy {
        icon("History") {
            stroke {
                // Soldan başlayıp alttan ve sağdan dolaşan çember yayı, sol üstte okun ucuna iner.
                moveTo(4f, 12f)
                arcToRelative(8f, 8f, 0f, isMoreThanHalf = true, isPositiveArc = false, dx1 = 8f, dy1 = -8f)
                arcToRelative(8f, 8f, 0f, isMoreThanHalf = false, isPositiveArc = false, dx1 = -5.66f, dy1 = 2.34f)
                lineTo(4f, 8.5f)
                // Ok ucu.
                moveTo(4f, 4.5f)
                verticalLineTo(8.5f)
                horizontalLineTo(8f)
                // Saat kolları.
                moveTo(12f, 8f)
                verticalLineTo(12f)
                lineTo(15f, 14f)
            }
        }
    }

    /** Oyun paketi: kapalı kutu. */
    val Package: ImageVector by lazy {
        icon("Package") {
            stroke {
                moveTo(12f, 3f)
                lineTo(20f, 7.5f)
                verticalLineTo(16.5f)
                lineTo(12f, 21f)
                lineTo(4f, 16.5f)
                verticalLineTo(7.5f)
                close()
                moveTo(4f, 7.5f)
                lineTo(12f, 12f)
                lineTo(20f, 7.5f)
                moveTo(12f, 12f)
                verticalLineTo(21f)
                // Bant.
                moveTo(8f, 5.25f)
                lineTo(16f, 9.75f)
            }
        }
    }

    /** Ayar kaydırıcıları (Ayarlar sekmesi, Temel). */
    val Sliders: ImageVector by lazy {
        icon("Sliders") {
            stroke {
                moveTo(4f, 6f); horizontalLineTo(20f)
                moveTo(4f, 12f); horizontalLineTo(20f)
                moveTo(4f, 18f); horizontalLineTo(20f)
            }
            fill {
                dot(9f, 6f, 2.6f)
                dot(15f, 12f, 2.6f)
                dot(8f, 18f, 2.6f)
            }
        }
    }

    /** Yazı boyu ("Aa"; Altyazı Görünümü). */
    val TextSize: ImageVector by lazy {
        icon("TextSize") {
            stroke {
                // Büyük A.
                moveTo(3f, 19f); lineTo(8.5f, 5f); lineTo(14f, 19f)
                moveTo(5.2f, 14f); horizontalLineTo(11.8f)
                // Küçük a.
                moveTo(15.5f, 13f); lineTo(18f, 8f); lineTo(20.5f, 13f)
                moveTo(16.3f, 11.4f); horizontalLineTo(19.7f)
            }
        }
    }

    /** Vizör (Altyazı Alanı). */
    val Viewfinder: ImageVector by lazy {
        icon("Viewfinder") {
            stroke {
                moveTo(4f, 9f); verticalLineTo(5f); horizontalLineTo(8f)
                moveTo(16f, 5f); horizontalLineTo(20f); verticalLineTo(9f)
                moveTo(20f, 15f); verticalLineTo(19f); horizontalLineTo(16f)
                moveTo(8f, 19f); horizontalLineTo(4f); verticalLineTo(15f)
            }
        }
    }

    /** Ses dalgası (Türkçe Seslendirme). */
    val Waveform: ImageVector by lazy {
        icon("Waveform") {
            stroke {
                moveTo(4f, 10f); verticalLineTo(14f)
                moveTo(8f, 7f); verticalLineTo(17f)
                moveTo(12f, 4f); verticalLineTo(20f)
                moveTo(16f, 8f); verticalLineTo(16f)
                moveTo(20f, 10.5f); verticalLineTo(13.5f)
            }
        }
    }

    /** Ev (Ana Ekran sekmesi). */
    val Home: ImageVector by lazy {
        icon("Home") {
            stroke {
                moveTo(4f, 10.5f); lineTo(12f, 4f); lineTo(20f, 10.5f)
                moveTo(6f, 9f); verticalLineTo(19f); horizontalLineTo(18f); verticalLineTo(9f)
                moveTo(10f, 19f); verticalLineTo(14f); horizontalLineTo(14f); verticalLineTo(19f)
            }
        }
    }

    /** Saat (Geçmiş sekmesi). */
    val Clock: ImageVector by lazy {
        icon("Clock") {
            stroke {
                moveTo(12f, 3.5f)
                arcTo(8.5f, 8.5f, 0f, isMoreThanHalf = true, isPositiveArc = true, x1 = 11.99f, y1 = 3.5f)
                close()
                moveTo(12f, 7.5f); verticalLineTo(12f); horizontalLineTo(15.5f)
            }
        }
    }

    private inline fun icon(name: String, block: ImageVector.Builder.() -> Unit): ImageVector =
        ImageVector.Builder(name = name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply(block)
            .build()

    private inline fun ImageVector.Builder.stroke(crossinline block: PathBuilder.() -> Unit) {
        path(stroke = SolidColor(Color.Black), strokeLineWidth = 2f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round) {
            block()
        }
    }

    private inline fun ImageVector.Builder.fill(crossinline block: PathBuilder.() -> Unit) {
        path(fill = SolidColor(Color.Black)) { block() }
    }

    /** (x, y) merkezli r yarıçaplı dolu daire. */
    private fun PathBuilder.dot(x: Float, y: Float, r: Float) {
        moveTo(x - r, y)
        arcToRelative(r, r, 0f, isMoreThanHalf = true, isPositiveArc = true, dx1 = 2 * r, dy1 = 0f)
        arcToRelative(r, r, 0f, isMoreThanHalf = true, isPositiveArc = true, dx1 = -2 * r, dy1 = 0f)
        close()
    }
}
