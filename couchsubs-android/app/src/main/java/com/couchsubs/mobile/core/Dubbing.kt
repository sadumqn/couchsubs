// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import java.util.Locale

/**
 * Türkçe dublaj sesleri: masaüstündeki Pocket TTS seslerinin adları (Mac/iPhone VoiceCast.swift, Windows VoiceCast.cs).
 * Telefonda sesler telefonun kendi Türkçe sesidir (TextToSpeech; Windows'taki "Hızlı" dublaj); karakterler ton ve hızla
 * ayrılır ([pitch], [rate]; Windows WindowsVoiceModel.Tone ve Swift DubbingVoice.systemTone ile aynı değerler).
 */
enum class DubbingVoice(val id: String, val female: Boolean, val pitch: Float, val rate: Float) {
    FEMALE_1("female_1", true, 1.55f, 1.1f),
    FEMALE_2("female_2", true, 1.4f, 1.0f),
    FEMALE_3("female_3", true, 1.48f, 1.05f),
    MALE_1("male_1", false, 0.85f, 0.95f),
    MALE_2("male_2", false, 1.05f, 1.15f),
    MALE_3("male_3", false, 0.95f, 1.05f);

    companion object {
        fun of(id: String?): DubbingVoice? = entries.firstOrNull { it.id == id }
    }
}

/** Dublajın çalacağı yer: TV uygulaması ya da bu telefon (Swift DubbingOutput: tv / computer). */
enum class DubbingOutput(val id: String) {
    TV("tv"), PHONE("computer");

    companion object {
        fun of(id: String?): DubbingOutput = entries.firstOrNull { it.id == id } ?: TV
    }
}

/** Seslendirilecek bir cümle (Swift SpokenLine). */
data class SpokenLine(val english: String, val turkish: String, val speaker: String? = null, val newTurn: Boolean = false) {
    companion object {
        /**
         * Gösterilen satırın cümleleri: konuşan adı İngilizceden alınır ("ARTHUR: …"), Türkçedeki ad atılır; tireyle
         * başlayan satır yeni konuşmadır ("- Gidelim." / "- Bekle!").
         */
        fun of(source: String, translation: String): List<SpokenLine> {
            val speaker = SpeakerPrefix.split(source)?.name
            val text = if (speaker != null) SpeakerPrefix.split(translation)?.takeIf { it.name == speaker }?.body ?: translation else translation
            return text.split('\n').map { it.trim() }.filter { line -> line.any { it.isLetter() } }.map { line ->
                val dash = line.first() in "-–—"
                SpokenLine(source, if (dash) line.drop(1).trim() else line, if (dash) null else speaker, dash)
            }
        }
    }
}

/**
 * Karakterlere ses dağıtır (Swift VoiceCast ile aynı kural): her ad kalıcı olarak bir sese bağlanır; etiketsiz satırlar
 * anlatıcı sesiyle, tireyle değişen konuşmalar anlatıcı ve ikinci konuşan arasında sırayla okunur.
 */
class VoiceCast(
    assignments: Map<String, DubbingVoice> = emptyMap(),
    var narrator: DubbingVoice = DubbingVoice.MALE_1,
    var partner: DubbingVoice = DubbingVoice.FEMALE_1,
) {
    private val map = LinkedHashMap(assignments)
    private var lastWasPartner = false

    val assignments: Map<String, DubbingVoice> get() = map.toMap()

    /** Satırın sesi; yeni bir ad ilk kez görülünce ona bir ses ayrılır. */
    fun voiceFor(line: SpokenLine): DubbingVoice {
        line.speaker?.let { speaker ->
            lastWasPartner = false
            val key = key(speaker)
            map[key]?.let { return it }
            return pick(NameGender.guess(speaker)).also { map[key] = it }
        }
        if (line.newTurn) lastWasPartner = !lastWasPartner
        return if (lastWasPartner) partner else narrator
    }

    fun assign(voice: DubbingVoice, name: String) { map[key(name)] = voice }

    /** Yeni karakter için en az kullanılan ses; cinsiyet bilinmiyorsa iki cinsiyetten de seçilir. */
    private fun pick(female: Boolean?): DubbingVoice {
        val candidates = DubbingVoice.entries.filter { female == null || it.female == female }
        val uses = HashMap<DubbingVoice, Int>()
        for (voice in map.values) uses[voice] = (uses[voice] ?: 0) + 1
        // Anlatıcı sesi en sona kalsın: etiketsiz satırlarla karışmasın.
        uses[narrator] = (uses[narrator] ?: 0) + 1
        return candidates.minWith(compareBy<DubbingVoice> { uses[it] ?: 0 }.thenBy { it.ordinal })
    }

    fun toJson(): String = JSONObject()
        .put("narrator", narrator.id).put("partner", partner.id)
        .put("assignments", JSONObject().apply { map.forEach { (name, voice) -> put(name, voice.id) } })
        .toString()

    companion object {
        fun key(name: String): String = name.uppercase(Locale.US)

        fun fromJson(text: String?): VoiceCast {
            if (text.isNullOrBlank()) return VoiceCast()
            return try {
                val json = JSONObject(text)
                val assigned = json.optJSONObject("assignments")
                val map = LinkedHashMap<String, DubbingVoice>()
                assigned?.keys()?.forEach { name -> DubbingVoice.of(assigned.optString(name))?.let { map[name] = it } }
                VoiceCast(map, DubbingVoice.of(json.optString("narrator")) ?: DubbingVoice.MALE_1,
                    DubbingVoice.of(json.optString("partner")) ?: DubbingVoice.FEMALE_1)
            } catch (error: org.json.JSONException) {
                VoiceCast()
            }
        }
    }
}

/** Addan cinsiyet tahmini (Swift NameGender ile aynı liste). Bilinmeyen ad null döner (true: kadın). */
object NameGender {
    private val female = setOf(
        "freya", "faye", "angrboda", "sif", "thrud", "ellie", "abby", "dina", "tess", "marlene", "riley", "aloy",
        "elisabet", "beta", "mary", "jane", "mj", "may", "rio", "hailey", "lara", "jill", "claire", "ada", "ashley",
        "tifa", "aerith", "yuffie", "jessie", "yuna", "lulu", "rikku", "ciri", "yennefer", "triss", "kassandra",
        "aya", "evie", "lydia", "anna", "emma", "olivia", "sophia", "isabella", "mia", "amelia", "harper", "evelyn",
        "abigail", "emily", "ella", "elizabeth", "sofia", "avery", "scarlett", "grace", "chloe", "victoria", "lily",
        "hannah", "zoe", "nora", "sarah", "rachel", "rebecca", "laura", "julia", "maria", "kate", "katie", "lucy",
        "alice", "eve", "helen", "linda", "susan", "karen", "nancy", "lisa", "betty", "margaret", "sandra", "kim",
        "mother", "mom", "mum", "queen", "princess", "lady", "girl", "woman", "sister", "aunt", "grandma", "witch",
        "goddess", "daughter", "wife",
    )
    private val male = setOf(
        "kratos", "atreus", "mimir", "baldur", "thor", "odin", "brok", "sindri", "tyr", "heimdall", "freyr",
        "durlin", "joel", "tommy", "bill", "henry", "jesse", "lev", "isaac", "owen", "manny", "jerry", "rost",
        "erend", "varl", "sylens", "kotallo", "peter", "miles", "harry", "otto", "kraven", "venom", "norman",
        "aaron", "ganke", "leon", "chris", "albert", "wesker", "ethan", "cloud", "barret", "zack", "sephiroth",
        "noctis", "tidus", "auron", "geralt", "jaskier", "alexios", "bayek", "ezio", "altair", "connor", "edward",
        "arthur", "dutch", "john", "micah", "hosea", "nathan", "nate", "drake", "sully", "jin", "khotun", "deacon",
        "boozer", "james", "robert", "michael", "william", "david", "richard", "joseph", "thomas", "charles",
        "daniel", "matthew", "anthony", "mark", "paul", "steven", "andrew", "kenneth", "kevin", "brian", "george",
        "jack", "jacob", "luke", "max", "father", "dad", "boy", "king", "prince", "lord", "sir", "man", "brother",
        "uncle", "grandpa", "son", "husband", "soldier", "guard", "captain", "commander", "general",
    )

    fun guess(name: String): Boolean? {
        val lower = name.lowercase(Locale.ROOT)
        if (lower in female) return true
        if (lower in male) return false
        // Çok sözcüklü adda sözcüklere bakılır ("OLD MAN", "Mary Jane", "Guard Captain").
        for (word in lower.split(' ')) {
            if (word in female) return true
            if (word in male) return false
        }
        return null
    }
}
