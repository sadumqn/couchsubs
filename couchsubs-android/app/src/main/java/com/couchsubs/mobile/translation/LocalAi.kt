// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import java.net.URI
import java.util.Locale

/**
 * Yerel model sunucusu (Ollama, LM Studio ya da başka OpenAI uyumlu sunucu): Mac/iPhone `LocalAIServer` ve Windows
 * `LocalAiServer` ile aynı kural. Telefonda model çalışmaz; sunucu aynı ağdaki bir bilgisayardır ve adresi o bilgisayarın
 * ağ adresidir ("http://192.168.1.20:11434/v1"). [baseUrl] sonunda "/" olmayan, `/v1` gibi yollu temel adrestir.
 */
data class LocalAiServer(val baseUrl: String, val model: String) {
    enum class Kind { OLLAMA, LM_STUDIO, OTHER }

    private val uri: URI get() = URI(baseUrl)

    /** Sunucunun türü; adresin kapısından tahmin edilir (hata iletisinde doğru yönerge için). */
    val kind: Kind get() = when (uri.port) {
        11434 -> Kind.OLLAMA
        1234 -> Kind.LM_STUDIO
        else -> Kind.OTHER
    }

    /** İsteğin gittiği adres. */
    val chatUrl: String get() = "$baseUrl/chat/completions"

    /** Kullanıcıya gösterilen kısa adres: "http://192.168.1.20:11434". */
    val address: String get() = uri.let { "${it.scheme}://${it.host}" + if (it.port >= 0) ":${it.port}" else "" }

    /** Ollama'da düşünme kapatılır: düşünen modeller altyazı çevirisinde boşuna yavaşlar (#295). */
    val disablesThinking: Boolean get() = kind == Kind.OLLAMA

    /** Kalıcı önbellekteki motor adı: sunucu ve model ayrı tutulur (Mac `engineID` ile aynı biçim). */
    val engineId: String get() = "local:$address:$model"

    companion object {
        const val OLLAMA_URL = "http://127.0.0.1:11434/v1"
        const val DEFAULT_MODEL = "qwen2.5:7b"
        /** Telefonda örnek adres bilgisayarın ağ adresidir; 127.0.0.1 telefonun kendisidir. */
        const val PHONE_EXAMPLE = "http://192.168.1.20:11434/v1"
        /** Ollama'nın OpenAI uyumlu adresindeki keep_alive (Mac/Windows ile aynı): model bellekte kalır. */
        const val OLLAMA_KEEP_ALIVE = "24h"
        /** Yerel modelin yanıtı bulut hizmetinden yavaş gelir (bilgisayarın gücüne bağlı). */
        const val TIMEOUT_MS = 20_000

        /** Adres ya da model geçersizse null. */
        fun of(baseUrl: String, model: String): LocalAiServer? {
            val name = model.trim()
            if (name.isEmpty()) return null
            return normalize(baseUrl)?.let { LocalAiServer(it, name) }
        }

        /**
         * Kullanıcının yazdığı adresin düzeltilmiş hali; geçersizse null. Şemasız adrese "http://", yolsuz adrese "/v1"
         * eklenir; sona yapıştırılmış "/chat/completions" atılır (Mac `LocalAIServer.normalize` ile aynı).
         */
        fun normalize(text: String): String? {
            var value = text.trim()
            if (value.isEmpty() || value.contains(' ')) return null
            if (!value.contains("://")) value = "http://$value"
            value = value.trimEnd('/')
            if (value.lowercase(Locale.ROOT).endsWith("/chat/completions")) value = value.dropLast("/chat/completions".length)
            value = value.trimEnd('/')
            val uri = try {
                URI(value)
            } catch (error: java.net.URISyntaxException) {
                return null
            }
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            if ((scheme != "http" && scheme != "https") || uri.host.isNullOrEmpty()) return null
            val path = uri.rawPath.orEmpty().ifEmpty { "/v1" }
            return "$scheme://${uri.rawAuthority}$path"
        }
    }
}
