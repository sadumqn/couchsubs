// SPDX-License-Identifier: AGPL-3.0-only
// Robolectric'te "AndroidKeyStore" yok: ekran görüntüsü testlerinde SecretStore (PS5 kaydı, PSN hesabı) yazılabilsin diye
// bellekte tutulan sahte bir anahtar deposu ve AES anahtar üreteci. Yalnız testlerde kurulur.
package com.couchsubs.mobile.ui.screenshots

import java.io.InputStream
import java.io.OutputStream
import java.security.Key
import java.security.KeyStore
import java.security.KeyStoreSpi
import java.security.Provider
import java.security.SecureRandom
import java.security.Security
import java.security.cert.Certificate
import java.security.spec.AlgorithmParameterSpec
import java.util.Collections
import java.util.Date
import java.util.Enumeration
import javax.crypto.KeyGenerator
import javax.crypto.KeyGeneratorSpi
import javax.crypto.SecretKey

object FakeAndroidKeyStore {
    private val keys = mutableMapOf<String, SecretKey>()
    private var last: SecretKey? = null

    fun install() {
        if (Security.getProvider("AndroidKeyStore") != null) return
        Security.addProvider(object : Provider("AndroidKeyStore", 1.0, "Sahte AndroidKeyStore (test)") {
            init {
                put("KeyStore.AndroidKeyStore", Store::class.java.name)
                put("KeyGenerator.AES", Generator::class.java.name)
            }
        })
    }

    class Generator : KeyGeneratorSpi() {
        override fun engineInit(random: SecureRandom?) {}
        override fun engineInit(params: AlgorithmParameterSpec?, random: SecureRandom?) {}
        override fun engineInit(keysize: Int, random: SecureRandom?) {}
        override fun engineGenerateKey(): SecretKey {
            val key = KeyGenerator.getInstance("AES", "SunJCE").apply { init(256) }.generateKey()
            last = key
            keys["couchsubs-secrets"] = key
            return key
        }
    }

    class Store : KeyStoreSpi() {
        override fun engineGetKey(alias: String, password: CharArray?): Key? = keys[alias]
        override fun engineGetEntry(alias: String, protParam: KeyStore.ProtectionParameter?): KeyStore.Entry? =
            keys[alias]?.let { KeyStore.SecretKeyEntry(it) }
        override fun engineGetCertificateChain(alias: String?): Array<Certificate>? = null
        override fun engineGetCertificate(alias: String?): Certificate? = null
        override fun engineGetCreationDate(alias: String?): Date = Date()
        override fun engineSetKeyEntry(alias: String, key: Key, password: CharArray?, chain: Array<out Certificate>?) {
            keys[alias] = key as SecretKey
        }
        override fun engineSetKeyEntry(alias: String?, key: ByteArray?, chain: Array<out Certificate>?) {}
        override fun engineSetCertificateEntry(alias: String?, cert: Certificate?) {}
        override fun engineDeleteEntry(alias: String) {
            keys.remove(alias)
        }
        override fun engineAliases(): Enumeration<String> = Collections.enumeration(keys.keys)
        override fun engineContainsAlias(alias: String): Boolean = alias in keys
        override fun engineSize(): Int = keys.size
        override fun engineIsKeyEntry(alias: String): Boolean = alias in keys
        override fun engineIsCertificateEntry(alias: String?): Boolean = false
        override fun engineGetCertificateAlias(cert: Certificate?): String? = null
        override fun engineStore(stream: OutputStream?, password: CharArray?) {}
        override fun engineLoad(stream: InputStream?, password: CharArray?) {}
    }
}
