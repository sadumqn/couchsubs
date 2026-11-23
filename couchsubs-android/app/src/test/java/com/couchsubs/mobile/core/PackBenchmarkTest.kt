// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Paket eşleşme ölçümü (Mac: PackBenchmarkTests.swift): oyunun kendi satırlarından üretilmiş OCR benzeri ekranlar
 * (tools/packs/bench.py). İngilizce metin depoda olmadığından yalnız `COUCHSUBS_PACK_BENCH=<cases.json>` verilince çalışır;
 * `COUCHSUBS_PACK_BENCH_PACK` paket dosyası (varsayılan gta-v.json.gz). Kategori başına doğru ve yanlış oranı yazar.
 */
class PackBenchmarkTest {
    /** `COUCHSUBS_PACK_BENCH` virgülle ayrılmış birden çok dosya da olabilir. */
    @Test
    fun packMatchRate() {
        val paths = System.getenv("COUCHSUBS_PACK_BENCH")
        assumeTrue("COUCHSUBS_PACK_BENCH verilmedi", paths != null)
        for (path in paths!!.split(',')) run(path)
    }

    private fun run(path: String) {
        val file = System.getenv("COUCHSUBS_PACK_BENCH_PACK") ?: "gta-v.json.gz"
        val directory = File(System.getenv("COUCHSUBS_PACK_BENCH_DIR") ?: System.getProperty("couchsubs.packs"))
        val fixtures = JSONObject(File(path).readText())
        val library = GamePackLibrary({ listOf(file to { File(directory, file).readBytes() }) }, null)
        assertNotNull(PackLookup.match(library, fixtures.getString("warmUp")))
        val order = mutableListOf<String>()
        val stats = mutableMapOf<String, IntArray>()
        val wrong = mutableListOf<String>()
        val cases = fixtures.getJSONArray("cases")
        val started = System.nanoTime()
        for (index in 0 until cases.length()) {
            val item = cases.getJSONObject(index)
            val category = item.getString("cat")
            val parts = item.getJSONArray("parts").let { array -> (0 until array.length()).map { array.getString(it) } }
            // Parçasız durum başka oyunun satırıdır: hiç eşleşmemeli, bulunursa yanlış sayılır.
            val expected = parts.mapNotNull { PackLookup.match(library, it)?.text }
            if (expected.size != parts.size) continue
            if (category !in stats) order.add(category)
            val entry = stats.getOrPut(category) { IntArray(3) }
            entry[0]++
            val found = PackLookup.match(library, item.getString("screen"))?.text ?: continue
            entry[1]++
            if (expected.isNotEmpty() && expected.all { found.contains(it) }) entry[2]++
            else if (wrong.size < 30) wrong.add("[$category] ${item.getString("screen")} → $found")
        }
        val elapsedMs = (System.nanoTime() - started) / 1e6
        val total = IntArray(3)
        val report = mutableListOf<String>()
        fun row(name: String, entry: IntArray) = String.format(
            java.util.Locale.ROOT, "BENCH %s %s %d  doğru %.1f%%  yanlış %.1f%%", file, name, entry[0],
            100.0 * entry[2] / maxOf(entry[0], 1), 100.0 * (entry[1] - entry[2]) / maxOf(entry[0], 1),
        )
        for (category in order) {
            val entry = stats.getValue(category)
            for (i in 0..2) total[i] += entry[i]
            report.add(row(category, entry))
        }
        report.add(row("TOPLAM", total))
        report.add(String.format(java.util.Locale.ROOT, "BENCH süre %.0f ms (%d durum)", elapsedMs, cases.length()))
        report += wrong.map { "BENCH-WRONG $it" }
        File("$path.$file.android.txt").writeText(report.joinToString("\n"))
        println(report.joinToString("\n"))
    }
}
