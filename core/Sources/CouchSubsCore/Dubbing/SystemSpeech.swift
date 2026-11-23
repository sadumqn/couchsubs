// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import Foundation

/// Cihazın kendi Türkçe sesiyle dublaj ("Hızlı"; Windows'ta Microsoft Tolga, Android'de TextToSpeech): Mac ve iPhone
/// AVSpeechSynthesizer kullanır. İndirme gerekmez; karakterler ton ve hızla ayrılır (`DubbingVoice.systemTone`).
public enum SystemSpeech {
    /// Cihazda Türkçe ses var mı (yoksa sistemin varsayılan sesi Türkçeyi yabancı aksanla okur).
    public static var hasTurkishVoice: Bool { turkishVoice != nil }

    static var turkishVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: "tr-TR")
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("tr") }
    }

    /// Okunacak cümle. Duygu etiketi ("[kızgın]") yalnız Pocket TTS içindir; sistem sesi onu yüksek sesle okurdu.
    public static func utterance(_ turkish: String, voice: DubbingVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: SpeechText.prepare(turkish))
        utterance.voice = turkishVoice
        let tone = voice.systemTone
        utterance.pitchMultiplier = Float(min(max(tone.pitch, 0.5), 2.0))
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(tone.rate), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }

    /// Cümleyi çalmadan sese çevirir (TV'ye gidecek WAV için örnekler toplanır). Ses çıkmazsa nil.
    public static func render(_ utterance: AVSpeechUtterance, with synthesizer: AVSpeechSynthesizer) async -> SpeechAudio? {
        await withCheckedContinuation { (continuation: CheckedContinuation<SpeechAudio?, Never>) in
            let collector = SampleCollector(continuation)
            synthesizer.write(utterance) { buffer in collector.add(buffer) }
        }
    }
}

/// AVSpeechSynthesizer.write'ın parçalarını toplar; boş parça sesin bittiğini bildirir.
private final class SampleCollector: @unchecked Sendable {
    private var continuation: CheckedContinuation<SpeechAudio?, Never>?
    private var samples: [Float] = []
    private var sampleRate = 22050
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<SpeechAudio?, Never>) { self.continuation = continuation }

    func add(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let pcm = buffer as? AVAudioPCMBuffer else { return finish() }
        if pcm.frameLength == 0 { return finish() }
        sampleRate = Int(pcm.format.sampleRate)
        let count = Int(pcm.frameLength)
        if let data = pcm.floatChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count))
        } else if let data = pcm.int16ChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count).map { Float($0) / 32768 })
        } else if let data = pcm.int32ChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count).map { Float($0) / 2_147_483_648 })
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: samples.isEmpty ? nil : SpeechAudio(samples: samples, sampleRate: sampleRate))
    }
}
