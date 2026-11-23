// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import com.couchsubs.mobile.tv.samsung.InstallLog
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Testler kullanıcının gerçek kurulum günlüğüne (uygulamanın files/tvinstall.log'u; Mac'te ~/Library/Logs/CouchSubs,
 * Windows'ta %LOCALAPPDATA%\CouchSubs) yazmaz: Mac'te sahte TV'lerle kurulum testleri "paket 0.6.1", "Kayıtlı anahtar
 * reddedildi" gibi satırları gerçek tvinstall.log'a karıştırıyordu. Android JVM testleri günlüğü ya yazmaz
 * (`InstallLog(null)`) ya da test başına geçici klasöre yazar.
 */
class TestLogIsolationTest {
    @Test
    fun logWithoutFileWritesNothing() {
        val folder = Files.createTempDirectory("log").toFile()
        InstallLog(null).write("deneme satırı")
        assertTrue(folder.listFiles().isNullOrEmpty())
    }

    @Test
    fun tempLogStaysInTempFolder() {
        val file = File(Files.createTempDirectory("log").toFile(), "tvinstall.log")
        InstallLog(file).write("deneme satırı")
        assertTrue(file.canonicalPath.startsWith(File(System.getProperty("java.io.tmpdir")).canonicalPath))
    }

    /** Test kaynakları günlüğü uygulamanın gerçek klasörüne (filesDir) ya da kullanıcı klasörüne açmaz. */
    @Test
    fun testSourcesNeverOpenTheRealLog() {
        val root = listOf(File("src/test"), File("app/src/test")).firstOrNull { it.isDirectory } ?: return
        val offenders = root.walkTopDown().filter { it.isFile && it.extension == "kt" && it.name != "TestLogIsolationTest.kt" }
            .filter { file ->
                val text = file.readText()
                Regex("""InstallLog\(File\([^)]*filesDir""").containsMatchIn(text) || "System.getProperty(\"user.home\")" in text
            }.map { it.path }.toList()
        assertFalse("Gerçek günlüğe yazan testler: $offenders", offenders.isNotEmpty())
    }
}
