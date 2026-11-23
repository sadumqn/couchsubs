// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Oyun paketi JSON'unun akış hâlinde okunması: `entries` nesnesindeki her satır nesne ağacı kurulmadan [parse]'ın geri
 * çağrısına verilir (GTA V paketi tek başına ~190 bin satır; org.json bütün ağacı bellekte tutardı). Kökteki dize alanları
 * (`id`, `title` ya da düz biçimde satırların kendisi) ayrıca döner.
 */
object PackJson {
    class Result(
        /** Kökte `entries` nesnesi vardı (sarılı biçim). */
        val wrapped: Boolean,
        val format: Double?,
        val id: String?,
        val title: String?,
        /** Kökteki dize alanları sırayla (düz biçimde satırlar). */
        val rootStrings: List<Pair<String, String>>,
        /** Biçim 2'deki "fuzzy" nesnesi (bulanık imzalar); yoksa null. */
        val fuzzy: Fuzzy? = null,
    )

    /** "fuzzy" nesnesi: base64 alanlar doğrudan baytlara açılır (ara String yok); eksik ya da bozuk alan null. */
    class Fuzzy(val version: Double?, val count: Double?, val mask: ByteArray?, val lengths: ByteArray?, val blooms: ByteArray?)

    /** [onSegment]: biçim 2'deki "segments" nesnesinin satırları (oyunun ayrı gösterdiği parçalar). */
    fun parse(data: ByteArray, onEntry: (String, String) -> Unit, onSegment: (String, String) -> Unit = { _, _ -> }): Result = try {
        Reader(data).root(onEntry, onSegment)
    } catch (error: IndexOutOfBoundsException) {
        throw InvalidPackException("Paket JSON değil", error)
    }

    private class Reader(private val data: ByteArray) {
        private var position = 0
        private val buffer = java.io.ByteArrayOutputStream(256)

        fun root(onEntry: (String, String) -> Unit, onSegment: (String, String) -> Unit): Result {
            skipSpace()
            if (peek() != '{'.code) throw InvalidPackException(if (peek() == '['.code) "Paket JSON nesnesi değil" else "Paket JSON değil")
            position++
            var wrapped = false
            var format: Double? = null
            var fuzzy: Fuzzy? = null
            val strings = mutableListOf<Pair<String, String>>()
            members { name ->
                when {
                    name == "fuzzy" && peek() == '{'.code -> {
                        position++
                        fuzzy = fuzzy()
                    }
                    name == "entries" && peek() == '{'.code -> {
                        wrapped = true
                        position++
                        members { key -> if (peek() == '"'.code) onEntry(key, string()) else skipValue() }
                    }
                    name == "segments" && peek() == '{'.code -> {
                        position++
                        members { key -> if (peek() == '"'.code) onSegment(key, string()) else skipValue() }
                    }
                    name == "format" && isNumberStart(peek()) -> format = number()
                    peek() == '"'.code -> strings.add(name to string())
                    else -> skipValue()
                }
            }
            skipSpace()
            if (position != data.size) throw InvalidPackException("Paket JSON değil")
            val id = strings.lastOrNull { it.first == "id" }?.second
            val title = strings.lastOrNull { it.first == "title" }?.second
            return Result(wrapped, format, id, title, strings, fuzzy)
        }

        /** `{` okunmuş "fuzzy" nesnesi. */
        private fun fuzzy(): Fuzzy {
            var version: Double? = null
            var count: Double? = null
            val bytes = HashMap<String, ByteArray?>()
            members { name ->
                when {
                    (name == "version" || name == "count") && isNumberStart(peek()) -> {
                        val value = number()
                        if (name == "version") version = value else count = value
                    }
                    (name == "mask" || name == "lengths" || name == "blooms") && peek() == '"'.code -> bytes[name] = base64()
                    else -> skipValue()
                }
            }
            return Fuzzy(version, count, bytes["mask"], bytes["lengths"], bytes["blooms"])
        }

        /** base64 dize: kaçış yoksa kaynak baytlardan doğrudan açılır; bozuksa null. */
        private fun base64(): ByteArray? {
            val begin = position + 1
            var end = begin
            while (end < data.size && data[end] != '"'.code.toByte() && data[end] != '\\'.code.toByte()) end++
            if (end < data.size && data[end] == '"'.code.toByte()) {
                position = end + 1
                return try {
                    val decoded = java.util.Base64.getDecoder().decode(java.nio.ByteBuffer.wrap(data, begin, end - begin))
                    ByteArray(decoded.remaining()).also { decoded.get(it) }
                } catch (error: IllegalArgumentException) {
                    null
                }
            }
            val text = string()
            return try {
                java.util.Base64.getDecoder().decode(text)
            } catch (error: IllegalArgumentException) {
                null
            }
        }

        /** `{` okunmuş nesnenin üyeleri: her ad için [value] değeri okumalıdır; `}` ile biter. */
        private inline fun members(value: (String) -> Unit) {
            skipSpace()
            if (peek() == '}'.code) {
                position++
                return
            }
            while (true) {
                skipSpace()
                if (peek() != '"'.code) fail()
                val name = string()
                skipSpace()
                expect(':')
                skipSpace()
                value(name)
                skipSpace()
                when (next()) {
                    ','.code -> continue
                    '}'.code -> return
                    else -> fail()
                }
            }
        }

        private fun skipValue() {
            skipSpace()
            when (val c = peek()) {
                '"'.code -> string()
                '{'.code -> {
                    position++
                    members { skipValue() }
                }
                '['.code -> {
                    position++
                    skipSpace()
                    if (peek() == ']'.code) {
                        position++
                        return
                    }
                    while (true) {
                        skipValue()
                        skipSpace()
                        when (next()) {
                            ','.code -> continue
                            ']'.code -> return
                            else -> fail()
                        }
                    }
                }
                't'.code -> literal("true")
                'f'.code -> literal("false")
                'n'.code -> literal("null")
                else -> if (isNumberStart(c)) number() else fail()
            }
        }

        private fun string(): String {
            expect('"')
            buffer.reset()
            var pendingHigh = -1
            while (true) {
                val b = data[position++].toInt() and 0xff
                when {
                    b == '"'.code -> break
                    b == '\\'.code -> {
                        val escape = data[position++].toInt().toChar()
                        val unit = when (escape) {
                            '"' -> '"'.code
                            '\\' -> '\\'.code
                            '/' -> '/'.code
                            'b' -> 8
                            'f' -> 12
                            'n' -> 10
                            'r' -> 13
                            't' -> 9
                            'u' -> {
                                val hex = String(data, position, 4, Charsets.US_ASCII)
                                position += 4
                                hex.toIntOrNull(16) ?: fail()
                            }
                            else -> fail()
                        }
                        if (unit in 0xD800..0xDBFF) {
                            pendingHigh = unit
                            continue
                        }
                        val codePoint = if (pendingHigh >= 0 && unit in 0xDC00..0xDFFF) Character.toCodePoint(pendingHigh.toChar(), unit.toChar()) else unit
                        pendingHigh = -1
                        buffer.write(String(Character.toChars(codePoint)).toByteArray(Charsets.UTF_8))
                        continue
                    }
                    b < 0x20 -> fail()
                    else -> buffer.write(b)
                }
                pendingHigh = -1
            }
            return buffer.toString(Charsets.UTF_8.name())
        }

        private fun number(): Double {
            val start = position
            while (position < data.size && (data[position].toInt().toChar().let { it.isDigit() || it in "+-.eE" })) position++
            return String(data, start, position - start, Charsets.US_ASCII).toDoubleOrNull() ?: fail()
        }

        private fun literal(word: String) {
            for (c in word) if (next() != c.code) fail()
        }

        private fun isNumberStart(c: Int) = c == '-'.code || c in '0'.code..'9'.code

        private fun skipSpace() {
            while (position < data.size) {
                val c = data[position].toInt()
                if (c == ' '.code || c == '\n'.code || c == '\r'.code || c == '\t'.code) position++ else break
            }
            // UTF-8 BOM
            if (position == 0 && data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()) {
                position = 3
                skipSpace()
            }
        }

        private fun peek(): Int = if (position < data.size) data[position].toInt() and 0xff else -1

        private fun next(): Int = data[position++].toInt() and 0xff

        private fun expect(c: Char) {
            if (next() != c.code) fail()
        }

        private fun fail(): Nothing = throw InvalidPackException("Paket JSON değil")
    }
}
