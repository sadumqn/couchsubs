// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.UUID

/** İçe aktarılacak dosyanın önizlemesi: kullanılabilir satırlar (anahtar → Türkçe) ve sayılar. */
class GamePackImportPreview(
    val suggestedTitle: String?,
    val entries: Map<String, String>,
    val invalidCount: Int,
    val duplicateCount: Int,
    val conflictCount: Int,
)

/**
 * Topluluk çeviri dosyasını (JSON, TXT ya da iki dilli SRT) oyun paketine çevirir. Mac'teki GamePackImporter.swift
 * (core) ve Windows'taki GamePackImporter.cs ile birebir aynı kurallar: İngilizce taraf [PackKey] ile özetlenir, yalnız
 * anahtar ve Türkçe saklanır; aynı satır bir kez sayılır, aynı anahtara farklı Türkçe gelirse satır alınmaz (çakışma).
 * Dosya telefonda kalır, sunucuya ya da havuza gitmez.
 */
object GamePackImporter {
    enum class Failure {
        UNSUPPORTED_FILE_TYPE, INVALID_UTF8, INVALID_JSON, UNSUPPORTED_PACK_FORMAT,
        BLANK_TITLE, EMPTY_PACK, DESTINATION_EXISTS, FILE_TOO_LARGE,
    }

    class ImportException(val failure: Failure) : IOException(failure.name)

    /** İçe aktarılan çeviri dosyası için üst sınır (bellek taşmasını önler; masaüstüyle aynı). */
    const val MAX_FILE_BYTES = 64 * 1024 * 1024

    /** İç içe JSON derinliği sınırı (yığın taşmasın). */
    private const val MAX_DEPTH = 512

    fun parse(data: ByteArray, fileName: String): GamePackImportPreview {
        if (data.size > MAX_FILE_BYTES) throw ImportException(Failure.FILE_TOO_LARGE)
        val bomless = data.size >= 3 && data[0] == 0xef.toByte() && data[1] == 0xbb.toByte() && data[2] == 0xbf.toByte()
        val source = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(data, if (bomless) 3 else 0, data.size - if (bomless) 3 else 0)).toString()
        } catch (error: CharacterCodingException) {
            throw ImportException(Failure.INVALID_UTF8)
        }
        val pairs = Pairs()
        var title: String? = null
        when (fileName.substringAfterLast('/').let { name -> if ('.' in name) name.substringAfterLast('.') else "" }.lowercase()) {
            "json" -> title = parseJson(source, pairs)
            "txt" -> parseText(lines(source), pairs)
            "srt" -> parseSrt(lines(source), pairs)
            else -> throw ImportException(Failure.UNSUPPORTED_FILE_TYPE)
        }
        return GamePackImportPreview(title, pairs.entries.toMap(), pairs.invalidCount, pairs.duplicateCount, pairs.conflicts.size)
    }

    /** "community-<slug>": küçük ASCII harf ve rakamlar, aralarında tire, en çok 80 karakter; yoksa "game". */
    fun makeId(title: String): String {
        val slug = StringBuilder()
        var gap = false
        for (byte in title.toByteArray(Charsets.UTF_8)) {
            val code = byte.toInt() and 0xff
            val letter = when (code) {
                in 65..90 -> code + 32
                in 97..122, in 48..57 -> code
                else -> {
                    gap = slug.isNotEmpty()
                    continue
                }
            }
            if (slug.length + (if (gap) 2 else 1) > 80) break
            if (gap) slug.append('-')
            slug.append(letter.toChar())
            gap = false
        }
        return "community-" + if (slug.isEmpty()) "game" else slug
    }

    /**
     * Paketi [directory]'ye `<id>.json` (biçim 1) olarak yazar: önce geçici dosyaya, sonra yerine konur. Aynı kimlikte
     * paket varsa [replacing] false iken [Failure.DESTINATION_EXISTS]; var olan dosyaya dokunulmaz.
     */
    fun install(preview: GamePackImportPreview, title: String, directory: File, replacing: Boolean): File {
        val name = nonblank(title) ?: throw ImportException(Failure.BLANK_TITLE)
        if (preview.entries.isEmpty()) throw ImportException(Failure.EMPTY_PACK)
        val id = makeId(name)
        val destination = File(directory, "$id.json")
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create ${directory.path}")
        if (!replacing && destination.exists()) throw ImportException(Failure.DESTINATION_EXISTS)
        val temporary = File(directory, ".${UUID.randomUUID()}.tmp")
        try {
            val entries = JSONObject()
            preview.entries.forEach { (key, value) -> entries.put(key, value) }
            val pack = JSONObject().put("format", 1).put("id", id).put("title", name).put("entries", entries)
            temporary.writeText(pack.toString(), Charsets.UTF_8)
            if (!replacing && destination.exists()) throw ImportException(Failure.DESTINATION_EXISTS)
            java.nio.file.Files.move(temporary.toPath(), destination.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        } finally {
            temporary.delete()
        }
        return destination
    }

    private class Pairs {
        val entries = LinkedHashMap<String, String>()
        var invalidCount = 0
        var duplicateCount = 0
        /** Çakışan anahtarın gördüğü bütün Türkçeler: sonraki tekrarlar da sayılsın. */
        val conflicts = HashMap<String, MutableSet<String>>()

        fun add(key: String?, target: String?) {
            val text = nonblank(target)
            if (key == null || text == null) {
                invalidCount++
                return
            }
            val seen = conflicts[key]
            val earlier = entries[key]
            when {
                seen != null -> if (!seen.add(text)) duplicateCount++
                earlier == null -> entries[key] = text
                earlier == text -> duplicateCount++
                else -> {
                    conflicts[key] = mutableSetOf(earlier, text)
                    entries.remove(key)
                }
            }
        }
    }

    /** Swift'in `trimmingCharacters(in: .whitespacesAndNewlines)`'ı gibi; boşsa null. */
    private fun nonblank(text: String?): String? = text?.trim { it.isWhitespace() }?.takeIf { it.isNotEmpty() }

    private fun parseJson(source: String, pairs: Pairs): String? {
        val root = JsonReader(source).document()
        val format = root["format"]
        if (format is Double) {
            if (format != 1.0) throw ImportException(Failure.UNSUPPORTED_PACK_FORMAT)
            val entries = root["entries"] as? JsonObject ?: throw ImportException(Failure.INVALID_JSON)
            for ((key, target) in entries.members) pairs.add(hashedKey(key), target as? String)
            return nonblank(root["title"] as? String) ?: nonblank(root["game"] as? String)
        }
        if (root["entries"] is JsonObject) throw ImportException(Failure.UNSUPPORTED_PACK_FORMAT)
        (root["subtitles"] as? JsonObject)?.let { subtitles ->
            for ((source, target) in subtitles.members) pairs.add(PackKey.key(source), target as? String)
            return nonblank(root["game"] as? String) ?: nonblank(root["title"] as? String)
        }
        for ((source, target) in root.members) pairs.add(PackKey.key(source), target as? String)
        return null
    }

    private fun hashedKey(key: String): String? =
        key.takeIf { it.length == 16 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' } }?.lowercase()

    private fun lines(source: String): List<String> = source.replace("\r\n", "\n").replace('\r', '\n').split('\n')

    private fun parseText(lines: List<String>, pairs: Pairs) {
        for (line in lines) {
            val trimmed = nonblank(line) ?: continue
            if (trimmed.startsWith("#")) continue
            val tabFields = line.split('\t')
            val delimiter = line.indexOf(" = ")
            when {
                tabFields.size == 2 -> pairs.add(PackKey.key(tabFields[0]), tabFields[1])
                tabFields.size == 1 && delimiter >= 0 -> pairs.add(PackKey.key(line.substring(0, delimiter)), line.substring(delimiter + 3))
                else -> pairs.invalidCount++
            }
        }
    }

    private val timestamp = Regex("[0-9]{2}:[0-5][0-9]:[0-5][0-9],[0-9]{3}")

    private fun validTiming(line: String): Boolean {
        val times = line.split(" --> ")
        // Sabit genişlik: zaman sırası metin sırasıyla aynı.
        return times.size == 2 && times[0] < times[1] && times.all { timestamp.matches(it) }
    }

    private fun parseSrt(lines: List<String>, pairs: Pairs) {
        val cue = mutableListOf<String>()
        fun finishCue() {
            if (cue.isEmpty()) return
            if (cue.size == 4 && cue[0].all { it in '0'..'9' } && validTiming(cue[1])) pairs.add(PackKey.key(cue[2]), cue[3])
            else pairs.invalidCount++
            cue.clear()
        }
        for (line in lines) {
            val text = nonblank(line)
            if (text != null) cue.add(text) else finishCue()
        }
        finishCue()
    }

    /** Sıralı JSON nesnesi: aynı adlı üyeler de sırasıyla kalır (masaüstünde de tekrarlar sayılır). */
    private class JsonObject(val members: List<Pair<String, Any?>>) {
        /** Aynı addaki son üye (Foundation'ın sözlüğüyle aynı). */
        operator fun get(name: String): Any? = members.lastOrNull { it.first == name }?.second
    }

    private object JsonNull

    /** Katı JSON okuyucu (RFC 8259); kök nesne olmalı, değilse [Failure.INVALID_JSON]. */
    private class JsonReader(private val text: String) {
        private var position = 0

        fun document(): JsonObject {
            skipSpace()
            if (peek() != '{') fail()
            val root = value(0) as JsonObject
            skipSpace()
            if (position != text.length) fail()
            return root
        }

        private fun fail(): Nothing = throw ImportException(Failure.INVALID_JSON)

        private fun peek(): Char {
            if (position >= text.length) fail()
            return text[position]
        }

        private fun skipSpace() {
            while (position < text.length && text[position].let { it == ' ' || it == '\t' || it == '\n' || it == '\r' }) position++
        }

        private fun expect(char: Char) {
            if (position >= text.length || text[position] != char) fail()
            position++
        }

        private fun value(depth: Int): Any? {
            if (depth > MAX_DEPTH) fail()
            skipSpace()
            return when (peek()) {
                '{' -> {
                    position++
                    val members = mutableListOf<Pair<String, Any?>>()
                    skipSpace()
                    if (peek() == '}') {
                        position++
                    } else {
                        while (true) {
                            skipSpace()
                            if (peek() != '"') fail()
                            val name = string()
                            skipSpace()
                            expect(':')
                            members.add(name to value(depth + 1))
                            skipSpace()
                            if (peek() == ',') position++ else { expect('}'); break }
                        }
                    }
                    JsonObject(members)
                }
                '[' -> {
                    position++
                    val items = mutableListOf<Any?>()
                    skipSpace()
                    if (peek() == ']') {
                        position++
                    } else {
                        while (true) {
                            items.add(value(depth + 1))
                            skipSpace()
                            if (peek() == ',') position++ else { expect(']'); break }
                        }
                    }
                    items
                }
                '"' -> string()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", JsonNull)
                else -> number()
            }
        }

        private fun literal(word: String, result: Any): Any {
            if (!text.startsWith(word, position)) fail()
            position += word.length
            return result
        }

        private fun number(): Double {
            val start = position
            if (position < text.length && text[position] == '-') position++
            when {
                position < text.length && text[position] == '0' -> position++
                position < text.length && text[position] in '1'..'9' -> while (position < text.length && text[position].isAsciiDigit()) position++
                else -> fail()
            }
            if (position < text.length && text[position] == '.') {
                position++
                if (position >= text.length || !text[position].isAsciiDigit()) fail()
                while (position < text.length && text[position].isAsciiDigit()) position++
            }
            if (position < text.length && (text[position] == 'e' || text[position] == 'E')) {
                position++
                if (position < text.length && (text[position] == '+' || text[position] == '-')) position++
                if (position >= text.length || !text[position].isAsciiDigit()) fail()
                while (position < text.length && text[position].isAsciiDigit()) position++
            }
            return text.substring(start, position).toDouble()
        }

        private fun Char.isAsciiDigit() = this in '0'..'9'

        private fun string(): String {
            expect('"')
            val output = StringBuilder()
            while (true) {
                if (position >= text.length) fail()
                val char = text[position++]
                when {
                    char == '"' -> return output.toString()
                    char == '\\' -> {
                        if (position >= text.length) fail()
                        when (text[position++]) {
                            '"' -> output.append('"')
                            '\\' -> output.append('\\')
                            '/' -> output.append('/')
                            'b' -> output.append('\b')
                            'f' -> output.append('\u000c')
                            'n' -> output.append('\n')
                            'r' -> output.append('\r')
                            't' -> output.append('\t')
                            'u' -> {
                                if (position + 4 > text.length) fail()
                                val hex = text.substring(position, position + 4)
                                if (!hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) fail()
                                val code = hex.toInt(16)
                                position += 4
                                output.append(code.toChar())
                            }
                            else -> fail()
                        }
                    }
                    char < ' ' -> fail()
                    else -> output.append(char)
                }
            }
        }
    }
}
