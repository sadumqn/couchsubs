// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Ekranda zaten Türkçe olan satır (PS5'in Türkçe arayüzü): hedef dil Türkçeyken çevirmene gönderilmez (#289). Yazı
 * tanıma Türkçe harfleri bozduğu için ("Sistem Yazillml Güncellem€") çeviriden sonraki "aslıyla aynı" denetimi bu
 * satırları kaçırıyordu: motor bozuk harfleri düzeltip farklı bir metin döndürünce satır yeniden gösteriliyordu. Ölçüt
 * temkinlidir: Türkçe harf ve bilinen bir Türkçe sözcük birlikte bulunmalı; içinde Türkçe ad geçen İngilizce satır
 * ("Atatürk said...") çevrilir. Windows'taki TurkishText.cs ve Mac'teki TurkishText.swift ile aynı kurallar.
 */
object TurkishText {
    /** Türkçe harfler (ü, ö, ç İngilizce satırda ancak yabancı adda geçer; tek başına yetmez). */
    private val letters = setOf('ğ', 'Ğ', 'ş', 'Ş', 'ı', 'İ', 'ü', 'Ü', 'ö', 'Ö', 'ç', 'Ç')

    /**
     * Havuz süzgecinin sözcüklerine ek, Türkçe arayüzde sık geçen ve İngilizcede olmayan sözcükler (katlanmış hâlleriyle
     * karşılaştırılır; "sistem" yok: katlanınca İngilizce "system" ile bir harf farklı). Ardından oyunun kendi Türkçe
     * altyazısında sık geçen konuşma sözcükleri (GitHub #337: "Yardımcı olabilir miyim, efendim?" çevrilmeye gidiyordu).
     */
    internal val commonWords = listOf(
        "daha", "sonra", "simdi", "degil", "haydi", "tamam", "evet", "hayir", "devam", "iptal", "giris", "guncelle",
        "guncellemesi", "yazilimi", "kurulum", "sirasinda", "sisteminizi", "sistemindeki", "kapatmayin", "baglanti",
        "baglantinizi", "uzaktan", "oynama", "dosyasi", "gostergesi", "kablosunu", "bir", "canli", "yayin",
        "efendim", "yardimci", "olabilir", "miyim", "misin", "musun", "nasil", "neden", "burada", "tesekkurler", "merhaba",
        "gibi", "kadar", "belki", "hemen", "benim", "senin",
    ).map { PoolFilter.fold(it).joinToString("") }

    private val known by lazy { PoolFilter.turkishWords + commonWords }

    /**
     * Tek sözcük, Türkçe harfi bozulmuş olsa da bilinen bir Türkçe sözcük mü ("Canli": yayın arayüzü). Otomatik ekran
     * yazısındaki kısa etiket içindir; İngilizce sözcük olan etiketler ("ON", "MAP") bu listede yoktur.
     */
    fun isKnownWord(text: String): Boolean = PoolFilter.fold(text).singleOrNull()?.let { it in known } ?: false

    /**
     * PS5'in Türkçe ana ekranı ve oyun kartı menüsünün sözcükleri ("Öne Çıkan İpuçları", "Yakın zamanda oluşturulanlar",
     * "Oyunlarınızdan 7 hikâye", "Resmi haberler"). Yazı tanıma Türkçe harfleri düz harfe çevirince ("Yakin zamanda olu...")
     * satır İngilizce sanılıp paketle eşleşiyor ya da çevriliyordu (beta.89, Mac).
     */
    internal val menuWords = listOf(
        "yakin", "zamanda", "olusturulanlar", "ipuclari", "cikan", "ogrenin", "kullanmayi", "hikaye", "haberler",
        "oyunlarinizdan", "secenekler", "resmi", "yeni",
    ).map { PoolFilter.fold(it).joinToString("") }

    /** Satır denetimlerinin sözcükleri ([isKnownWord]'ün kısa etiket listesi değişmez). */
    private val lineWords by lazy { known + menuWords }

    /** Satır yüksek güvenle Türkçe mi: en az bir Türkçe harf ve en az bir bilinen Türkçe sözcük. */
    fun isSure(text: String): Boolean {
        if (text.none { it in letters }) return false
        return PoolFilter.fold(text).any { word -> lineWords.any { PoolFilter.isClose(word, it) } }
    }

    /**
     * Türkçe harfleri yazı tanımada düz harfe dönmüş Türkçe satır mı ("Yakin zamanda olu...", "e [Ikan Ipuflari Yakin
     * zamanda olu..."): en az iki bilinen Türkçe sözcük, ve iki ya da daha çok harfli sözcüklerin en az yarısı bilinen
     * Türkçe sözcük. İçinde tek Türkçe sözcük geçen İngilizce satır çevrilir.
     */
    fun isFolded(text: String): Boolean {
        val words = PoolFilter.fold(text).filter { word -> word.length >= 2 && word.any { it.isLetter() } }
        val hits = words.count { word -> lineWords.any { PoolFilter.isClose(word, it) } }
        return hits >= 2 && hits * 2 >= words.size
    }

    /** Satır Türkçe mi ([isSure] ya da [isFolded]). */
    fun looksTurkish(text: String): Boolean = isSure(text) || isFolded(text)
}
