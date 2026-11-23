// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * "Ekranı çevir"de fiyat ve sayılar (GTA 6 dükkânı, bahşiş menüsü): yazı tanıma "$" işaretini "S" okuyor ("$200" →
 * "S200", "$$$$" → "SSSS"); bozuk okuma harf sayılıp çevirmene gidiyor, ekranda anlamsız bir yazı çıkıyordu. Burada
 * rakam bağlamındaki "S" ve yalnız "S"/"$"den oluşan sözcük "$"a döner ([repair]); para ve ayraçlı sayılar ("$1,250",
 * "2.5") çevirmene uydurma bir adla gider ve çeviriden sonra olduğu gibi yerine konur ([protect]/[restore]). Kurallar
 * ortak deneme dosyasıyla sınanır (fixtures/price-text.json; Mac/iPhone: PriceText.swift, Windows: PriceText.cs).
 */
object PriceText {
    /** Korunan bir sayı: çevirmene giden ad ve yerine konacak değer. */
    data class Value(val name: String, val text: String)

    /** Korunmuş metin: çevirmene gidecek metin ve sırayla kullanılan adlar. */
    data class Protected(val text: String, val values: List<Value>)

    private val misreadPrice = Regex("(?<![\\p{L}\\p{N}$])[S$](?=[0-9])([0-9OoIl.,]*[0-9OoIl])([KkMm]?)(?![\\p{L}\\p{N}])")
    private val dollarRun = Regex("(?<![\\p{L}\\p{N}])[S$]{2,}(?![\\p{L}\\p{N}])")
    private val protectedNumber =
        Regex("(?<![\\p{L}\\p{N}])(?:\\$+(?:[0-9][0-9.,]*[0-9]|[0-9])?[KkMm]?|[0-9]+(?:[.,:][0-9]+)+)(?![\\p{L}\\p{N}])")

    /** Terim ve simge korumasıyla aynı adlar (çevirmenler özel adı olduğu gibi bırakır); metinde geçen ad kullanılmaz. */
    private val names = listOf("Zarmon", "Velkor", "Dorvan", "Kelmar", "Tolvar", "Brandur", "Halvor", "Feldor")

    /** Yazı tanımanın bozduğu fiyatları düzeltir; uzunluk değişmez (sözcük kutuları geçerli kalır). */
    fun repair(text: String): String {
        if ('S' !in text && '$' !in text) return text
        // "S200", "S2OO" → "$200": "S" ve içindeki O/I/l harfleri rakam bağlamında.
        val fixed = misreadPrice.replace(text) { match ->
            val digits = match.groupValues[1].map { when (it) { 'O', 'o' -> '0'; 'I', 'l' -> '1'; else -> it } }.joinToString("")
            "$" + digits + match.groupValues[2]
        }
        // "SSSS" → "$$$$"; iki harflik "SS" ancak içinde "$" varsa ("$S").
        return dollarRun.replace(fixed) { match ->
            if (match.value.length >= 3 || '$' in match.value) "$".repeat(match.value.length) else match.value
        }
    }

    /** Sözcük fiyat ya da yalnız "$" mı ("$200", "$$$$"; düzeltilmiş okumada). */
    fun isMoney(word: String): Boolean {
        val core = word.trim('(', ')', '[', ']', '.', ',', ':', ';', '!', '?')
        return core.startsWith('$') && protectedNumber.matchEntire(core) != null
    }

    /** Para ve ayraçlı sayıları adlarla değiştirir. Ad kalmazsa kalan sayılar olduğu gibi gider. */
    fun protect(text: String): Protected {
        val matches = protectedNumber.findAll(text).toList()
        if (matches.isEmpty()) return Protected(text, emptyList())
        val free = ArrayDeque(names.filter { !text.contains(it, ignoreCase = true) })
        val values = mutableListOf<Value>()
        val builder = StringBuilder()
        var at = 0
        for (match in matches) {
            val name = free.removeFirstOrNull() ?: break
            values.add(Value(name, match.value))
            builder.append(text, at, match.range.first).append(name)
            at = match.range.last + 1
        }
        builder.append(text, at, text.length)
        return Protected(builder.toString(), values)
    }

    /**
     * Çevirideki adları değerlerine döndürür; adın Türkçe eki kesme işaretiyle korunur ("Zarmon'a" → "$200'a",
     * "Zarmona" → "$200'a"). Çeviride bulunmayan değer sona eklenir (fiyat kaybolmasın).
     */
    fun restore(translation: String, values: List<Value>): String {
        var text = translation
        val missing = mutableListOf<String>()
        for (value in values) {
            val pattern = Regex(
                "(?<![\\p{L}\\p{N}])" + Regex.escape(value.name) + "(?:\\s?['’`´](\\p{L}+)|(\\p{L}+))?(?![\\p{L}\\p{N}])",
                RegexOption.IGNORE_CASE,
            )
            if (!pattern.containsMatchIn(text)) {
                missing.add(value.text)
                continue
            }
            text = pattern.replace(text) { match ->
                val suffix = match.groups[1]?.value ?: match.groups[2]?.value
                value.text + (suffix?.let { "'$it" } ?: "")
            }
        }
        return if (missing.isEmpty()) text else (listOf(text) + missing).joinToString(" ")
    }
}
