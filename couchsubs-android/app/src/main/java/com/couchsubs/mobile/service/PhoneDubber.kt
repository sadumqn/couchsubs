// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.couchsubs.mobile.core.DubbingOutput
import com.couchsubs.mobile.core.DubbingVoice
import com.couchsubs.mobile.core.SpokenLine
import com.couchsubs.mobile.core.SubtitleServer
import com.couchsubs.mobile.core.VoiceCast
import java.io.File
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Telefonda Türkçe dublaj: çeviri telefonun kendi Türkçe sesiyle (TextToSpeech) okunur. iPhone PhoneDubber ve Windows'taki
 * "Hızlı" dublajla aynı: indirme yok, karakterler ton ve hızla ayrılır ([DubbingVoice.pitch], [DubbingVoice.rate]), ses
 * atamaları ([VoiceCast]) masaüstüyle aynı kural. Ses ya bu telefondan çalar ya da WAV olarak TV uygulamasına gider
 * ([SubtitleServer.sendSpeech]). Yeni altyazı gelince eski cümleler kesilir: dublaj hep ekrandaki altyazıyı söyler.
 */
class PhoneDubber(context: Context) {
    private val appContext = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor { Thread(it, "CouchSubs dubbing").apply { isDaemon = true } }
    private val generation = AtomicInteger()
    private val ready = CountDownLatch(1)
    @Volatile private var turkish = false
    private val done = java.util.concurrent.ConcurrentHashMap<String, CountDownLatch>()
    private val tts: TextToSpeech = TextToSpeech(appContext) { status ->
        if (status == TextToSpeech.SUCCESS) turkish = setTurkish()
        ready.countDown()
    }

    /** Altyazı sunucusu (çeviri sürerken); yoksa TV'ye ses gitmez. */
    @Volatile var server: SubtitleServer? = null
    /** Yeni bir karaktere ses verildi; ayarlara kaydedilir (JSON, bkz. [VoiceCast.toJson]). */
    @Volatile var onCastChanged: ((String) -> Unit)? = null
    /** Ses atamaları: ayarlardaki JSON değişince yeniden okunur; tireli konuşmanın sırası oturum boyunca korunur. */
    private var cast = VoiceCast()
    private var castJson: String? = null

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { utteranceId?.let { done.remove(it)?.countDown() } }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { utteranceId?.let { done.remove(it)?.countDown() } }
            override fun onError(utteranceId: String?, errorCode: Int) { utteranceId?.let { done.remove(it)?.countDown() } }
            override fun onStop(utteranceId: String?, interrupted: Boolean) { utteranceId?.let { done.remove(it)?.countDown() } }
        })
    }

    /** Telefonda Türkçe ses var mı (yoksa ayarlarda ses paketinin nereden ekleneceği yazar). */
    fun hasTurkishVoice(): Boolean {
        ready.await(2, TimeUnit.SECONDS)
        return turkish
    }

    private fun setTurkish(): Boolean = try {
        tts.setLanguage(Locale.forLanguageTag("tr-TR")) >= TextToSpeech.LANG_AVAILABLE
    } catch (error: Exception) {
        false
    }

    fun speak(lines: List<SpokenLine>, castJson: String?, output: DubbingOutput) {
        if (lines.isEmpty()) return
        stop()
        val number = generation.get()
        val queue = lines.takeLast(BACKLOG)
        worker.execute {
            if (castJson != this.castJson) {
                cast = VoiceCast.fromJson(castJson)
                this.castJson = castJson
            }
            run(number, queue, output)
        }
    }

    /** Ayarlardaki "Dinle": deneme cümlesi her zaman bu telefondan çalar. */
    fun preview(voice: DubbingVoice) {
        stop()
        worker.execute {
            if (!ready.await(5, TimeUnit.SECONDS)) return@execute
            tone(voice)
            tts.speak(PREVIEW, TextToSpeech.QUEUE_FLUSH, null, "preview")
        }
    }

    fun stop() {
        generation.incrementAndGet()
        runCatching { tts.stop() }
        done.values.forEach { it.countDown() }
        done.clear()
        server?.stopSpeech()
    }

    private fun run(number: Int, lines: List<SpokenLine>, output: DubbingOutput) {
        if (!ready.await(5, TimeUnit.SECONDS)) return
        for (line in lines) {
            if (generation.get() != number) return
            val before = cast.assignments
            val voice = cast.voiceFor(line)
            if (cast.assignments != before) cast.toJson().let { json -> castJson = json; onCastChanged?.invoke(json) }
            tone(voice)
            val id = "line-$number-${System.nanoTime()}"
            val finished = CountDownLatch(1).also { done[id] = it }
            when (output) {
                DubbingOutput.PHONE -> {
                    tts.speak(line.turkish, TextToSpeech.QUEUE_ADD, null, id)
                    finished.await(30, TimeUnit.SECONDS)
                }
                DubbingOutput.TV -> {
                    val file = File(appContext.cacheDir, "speech.wav")
                    if (tts.synthesizeToFile(line.turkish, null, file, id) != TextToSpeech.SUCCESS) { done.remove(id); continue }
                    finished.await(30, TimeUnit.SECONDS)
                    if (generation.get() != number) return
                    val wav = runCatching { file.readBytes() }.getOrNull() ?: continue
                    val milliseconds = wavDurationMs(wav) ?: continue
                    server?.sendSpeech(wav, milliseconds)
                    // TV sesi ağdan alıp çalmaya biraz geç başlar; sıradaki cümle bunu kesmesin.
                    sleepUnlessStopped(number, milliseconds + 250L)
                }
            }
        }
    }

    private fun tone(voice: DubbingVoice) {
        tts.setPitch(voice.pitch)
        tts.setSpeechRate(voice.rate)
    }

    private fun sleepUnlessStopped(number: Int, milliseconds: Long) {
        val until = System.currentTimeMillis() + milliseconds
        while (generation.get() == number && System.currentTimeMillis() < until) Thread.sleep(50)
    }

    companion object {
        private const val TAG = "CouchSubsDubbing"
        /** Bekleyen en çok cümle (masaüstüyle aynı): fazlası eskiden başlayarak atlanır. */
        const val BACKLOG = 3
        const val PREVIEW = "Merhaba, oyundaki karakterleri Türkçe seslendireceğim."

        /** RIFF/WAVE başlığından süre (ms); PCM değilse ya da başlık bozuksa null. */
        fun wavDurationMs(wav: ByteArray): Int? {
            fun int(at: Int) = (wav[at].toInt() and 0xff) or ((wav[at + 1].toInt() and 0xff) shl 8) or
                ((wav[at + 2].toInt() and 0xff) shl 16) or ((wav[at + 3].toInt() and 0xff) shl 24)
            if (wav.size < 44 || String(wav, 0, 4, Charsets.US_ASCII) != "RIFF" || String(wav, 8, 4, Charsets.US_ASCII) != "WAVE") return null
            var at = 12
            var byteRate = 0
            while (at + 8 <= wav.size) {
                val id = String(wav, at, 4, Charsets.US_ASCII)
                val size = int(at + 4)
                if (id == "fmt " && at + 16 <= wav.size) byteRate = int(at + 16)
                if (id == "data") {
                    if (byteRate <= 0) return null
                    val bytes = minOf(size.toLong() and 0xffffffffL, (wav.size - at - 8).toLong())
                    return (bytes * 1000 / byteRate).toInt()
                }
                at += 8 + size
                if (size < 0) return null
            }
            Log.w(TAG, "WAV: veri parçası yok")
            return null
        }
    }
}
