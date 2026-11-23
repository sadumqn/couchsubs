// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * PS5'te o an çalışan oyun: keşif yanıtındaki `running-app-titleid` ve `running-app-name`. Ortak havuza giden satıra
 * eklenir; yeni bir oyun (ör. GTA 6) çıkınca o oyunun satırları ayrı toplanıp hızla paket yapılır. Yalnız oyunun kimliği ve
 * adı gider. PS5 çoğu zaman çalışan oyunu bildirmiyor; o zaman oyun uygulamanın paketten tanıdığı ya da kullanıcının
 * seçtiği addır ([GameSense]): kimlik yoktur, yalnız ad gider. Mac'teki RunningGame.swift ve Windows'taki RunningGame.cs ile
 * aynı kurallar.
 */
data class RunningGame(val titleId: String?, val name: String?) {
    companion object {
        const val MAX_NAME = 120
        private val TITLE_ID = Regex("^[A-Z]{4}\\d{5}(_\\d{2})?$")

        /** Kimlik PS5 biçiminde değilse null. */
        fun create(titleId: String?, name: String?): RunningGame? {
            val id = normalizedTitleId(titleId) ?: return null
            return RunningGame(id, normalizedName(name))
        }

        /** Yalnız adıyla bilinen oyun (paketten tanındı ya da kullanıcı seçti); ad boşsa null. Kimlik geçerliyse o da tutulur. */
        fun named(name: String?, titleId: String? = null): RunningGame? {
            val clean = normalizedName(name) ?: return null
            return RunningGame(normalizedTitleId(titleId), clean)
        }

        fun normalizedTitleId(value: String?): String? {
            val id = value?.trim()?.uppercase() ?: return null
            return id.takeIf { TITLE_ID.matches(it) }
        }

        /** Denetim karakterleri ve fazla boşluk atılır, en çok 120 karakter; boşsa null. */
        fun normalizedName(value: String?): String? {
            if (value == null) return null
            val cleaned = buildString {
                value.codePoints().forEach { cp ->
                    val type = Character.getType(cp)
                    if (type == Character.CONTROL.toInt() || type == Character.FORMAT.toInt()) append(' ') else appendCodePoint(cp)
                }
            }
            val words = cleaned.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            return words.take(MAX_NAME).trim().ifEmpty { null }
        }
    }
}
