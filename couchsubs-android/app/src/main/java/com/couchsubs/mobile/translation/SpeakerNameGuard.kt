// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Konuşan etiketlerinden ("PRICE: …") öğrenilip cümle içinde çeviriden korunan adlar (#287: "Price, get down!" →
 * "Fiyat, yere yat!" olmasın). Mac/iPhone: SpeakerNames (SubtitleSegmenter.swift), Windows: SpeakerNameGuard.cs;
 * kurallar ve hariç tutulan sözcükler aynı. Ad, cümlede büyük harfle başlayıp tam sözcük olarak geçince korunur.
 */
class SpeakerNameGuard {
    private val kept = ConcurrentHashMap.newKeySet<String>()

    /** Çeviriden korunacak adlar, cümlede beklenen yazılışla ("PRICE" etiketi → "Price"). */
    val protected: Set<String> get() = kept.toSet()

    /** Etiketteki adı öğrenir ("CAPTAIN PRICE" → "Price"). */
    fun learn(name: String) {
        kept.addAll(protectable(name))
    }

    companion object {
        /** Görev ve tür sözcükleri: etikette geçse de ad sayılmaz, cümle içinde korunmaz ("SOLDIER:", "OLD MAN:"). */
        val NOT_NAMES: Set<String> = setOf(
            "soldier", "soldiers", "guard", "guards", "man", "men", "woman", "women", "boy", "girl", "kid", "child",
            "radio", "pilot", "copilot", "officer", "enemy", "enemies", "narrator", "voice", "announcer", "intercom",
            "speaker", "operator", "driver", "gunner", "sniper", "medic", "civilian", "hostage", "prisoner", "militia",
            "mercenary", "merc", "terrorist", "agent", "commander", "captain", "sergeant", "sgt", "lieutenant", "lt",
            "general", "colonel", "major", "corporal", "private", "admiral", "chief", "doctor", "dr", "mr", "mrs", "ms",
            "sir", "old", "young", "little", "big", "unknown", "stranger", "someone", "everyone", "all", "both", "team",
            "squad", "leader", "hq", "command", "control", "player", "you", "the", "a", "an", "of", "and", "friendly",
            "hostile", "female", "male", "tv", "news", "reporter", "crowd", "villager", "worker", "scientist", "nurse",
            "cop", "police",
        )

        /**
         * Etiketteki addan korunacak sözcükler: en az iki harf, yalnız harf/kesme/tire, görev sözcüğü değil. Tümü büyük
         * harfli sözcük cümle düzeninde beklenir ("PRICE" → "Price"); küçük harfle başlayan sözcük alınmaz.
         */
        fun protectable(name: String): List<String> = name.split(' ').filter { it.isNotEmpty() }.mapNotNull { word ->
            if (word.count { it.isLetter() } < 2 || !word.all { it.isLetter() || it == '\'' || it == '’' || it == '-' } ||
                !word[0].isUpperCase() || word.lowercase(Locale.ROOT) in NOT_NAMES) null
            else if (word.any { it.isLowerCase() }) word
            else word.substring(0, 1) + word.substring(1).lowercase(Locale.ROOT)
        }

        /** [names] içinden metinde tam sözcük olarak geçenler, sıralı. [exact]: yalnız aynı büyük/küçük harfle. */
        fun occurring(names: Collection<String>, text: String, exact: Boolean): List<String> {
            fun boundary(index: Int) = index < 0 || index >= text.length || !text[index].isLetterOrDigit()
            return names.filter { name ->
                var start = 0
                var found = false
                while (start <= text.length - name.length) {
                    val index = text.indexOf(name, start, ignoreCase = !exact)
                    if (index < 0) break
                    if (boundary(index - 1) && boundary(index + name.length)) { found = true; break }
                    start = index + 1
                }
                found
            }.sorted()
        }
    }
}
