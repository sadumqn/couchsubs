// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tanh

/**
 * Açılış sesi (Mac StartupChime ile aynı ses, dosya yok; sesi uygulama üretir): iki notalı kısa, yumuşak bir çan. Yalnız
 * karşılamanın ilk açılışında ve Ayarlar › Temel › Açılış Sesi açıkken çalar.
 */
object StartupChime {
    private const val RATE = 44_100
    private var track: AudioTrack? = null

    fun play() {
        stop()
        val samples = render((RATE * 3.4).toInt(), RATE.toDouble())
        val pcm = ShortArray(samples.size) { (samples[it] * Short.MAX_VALUE).toInt().toShort() }
        val audio = runCatching {
            AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
        }.getOrNull() ?: return
        audio.write(pcm, 0, pcm.size)
        audio.play()
        track = audio
    }

    fun stop() {
        track?.let { runCatching { it.stop() }; it.release() }
        track = null
    }

    /**
     * Tuvaldeki açılış sesi (Main.dc.html; Mac StartupChime.render ile aynı): 0–0,85 sn yükselen hava (bant geçiren gürültü
     * 250 → 3200 Hz), 0,78 sn derin vuruş (140 → 42 Hz), 0,80 ve 0,94 sn iki parlak tık (1318,5 / 1760 Hz), 1,15 sn'de
     * yavaş sönen sıcak akor.
     */
    fun render(count: Int, rate: Double): FloatArray {
        val data = FloatArray(count)
        var low = 0.0
        var band = 0.0
        var seed = 0x2545F491
        var kickPhase = 0.0
        val chordLow = DoubleArray(5)
        val chord = doubleArrayOf(110.0, 164.81, 220.0, 277.18, 329.63)
        fun ramp(t: Double, a: Double, b: Double, v0: Double, v1: Double): Double = when {
            t <= a -> v0
            t >= b -> v1
            else -> v0 * (v1 / v0).pow((t - a) / (b - a))
        }
        for (frame in 0 until count) {
            val t = frame / rate - 0.05
            var sample = 0.0
            // 1) Hava
            if (t >= 0 && t < 0.9) {
                seed = seed xor (seed shl 13); seed = seed xor (seed ushr 17); seed = seed xor (seed shl 5)
                val noise = (seed.toLong() and 0xffffffffL).toDouble() / 4294967295.0 * 2 - 1
                val frequency = ramp(t, 0.0, 0.72, 250.0, 3200.0)
                val f = 2 * sin(PI * frequency / rate)
                val high = noise - low - band / 1.2
                band += f * high
                low += f * band
                val gain = if (t < 0.6) ramp(t, 0.0, 0.6, 0.0001, 0.35) else ramp(t, 0.6, 0.85, 0.35, 0.0001)
                sample += band * gain
            }
            // 2) Vuruş
            if (t >= 0.78 && t < 1.6) {
                val frequency = ramp(t, 0.78, 1.1, 140.0, 42.0)
                kickPhase += 2 * PI * frequency / rate
                val gain = if (t < 0.79) ramp(t, 0.78, 0.79, 0.0001, 0.9) else ramp(t, 0.79, 1.5, 0.9, 0.0001)
                sample += sin(kickPhase) * gain
            }
            // 3) Tıklar (üçgen dalga)
            for ((start, frequency) in listOf(0.80 to 1318.5, 0.94 to 1760.0)) {
                if (t < start || t >= start + 0.4) continue
                val local = t - start
                val phase = (local * frequency) % 1.0
                val triangle = 4 * abs(phase - 0.5) - 1
                val gain = if (local < 0.01) ramp(local, 0.0, 0.01, 0.0001, 0.22) else ramp(local, 0.01, 0.35, 0.22, 0.0001)
                sample += triangle * gain
            }
            // 4) Akor (ilk ikisi testere dişi, alçak geçiren 400 → 1800 Hz)
            if (t >= 1.15 && t < 3.3) {
                val cutoff = 400 + 1400 * ((t - 1.15) / 0.45).coerceIn(0.0, 1.0)
                val alpha = 1 - exp(-2 * PI * cutoff / rate)
                for (index in chord.indices) {
                    val frequency = chord[index] * 2.0.pow((if (index % 2 == 0) -6.0 else 6.0) / 1200)
                    val local = t - 1.15
                    val phase = (local * frequency) % 1.0
                    val wave = if (index < 2) 2 * phase - 1 else sin(2 * PI * phase)
                    chordLow[index] += alpha * (wave - chordLow[index])
                    val peak = if (index < 2) 0.08 else 0.12
                    val gain = if (t < 1.3) ramp(t, 1.15, 1.3, 0.0001, peak) else ramp(t, 1.3, 3.2, peak, 0.0001)
                    sample += chordLow[index] * gain
                }
            }
            // Sıkıştırıcının yerine yumuşak sınırlama.
            data[frame] = tanh(sample * 0.9).toFloat()
        }
        return data
    }
}
