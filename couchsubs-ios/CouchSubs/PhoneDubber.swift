// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import CouchSubsCore
import Foundation

/// Telefonda Türkçe dublaj: çeviri iPhone'un kendi Türkçe sesiyle (AVSpeechSynthesizer) okunur. Windows'taki "Hızlı"
/// dublajla aynı: indirme yok, karakterler ton ve hızla ayrılır (`DubbingVoice.systemTone`), ses atamaları (`VoiceCast`)
/// masaüstüyle aynı. Ses ya bu telefondan çalar ya da WAV olarak TV uygulamasına gider (`SubtitleServer.sendSpeech`).
/// Yeni altyazı gelince eski cümleler kesilir: dublaj hep ekrandaki altyazıyı söyler.
@MainActor
final class PhoneDubber {
    private let synthesizer = AVSpeechSynthesizer()
    private let server: () -> SubtitleServer
    private var queue: [SpokenLine] = []
    private var worker: Task<Void, Never>?
    private var generation = 0

    var cast: VoiceCast
    var output: DubbingOutput
    /// Yeni bir karaktere ses verildi; ayarlara kaydedilir.
    var onCastChanged: ((VoiceCast) -> Void)?

    /// Bekleyen en çok cümle (masaüstüyle aynı): fazlası eskiden başlayarak atlanır.
    static let backlog = 3

    init(server: @escaping () -> SubtitleServer, settings: DubbingSettings) {
        self.server = server
        cast = settings.cast
        output = settings.output
    }

    /// Cihazda Türkçe ses var mı.
    static var hasTurkishVoice: Bool { SystemSpeech.hasTurkishVoice }

    func speak(_ lines: [SpokenLine]) {
        guard !lines.isEmpty else { return }
        stop()
        queue = Array(lines.suffix(Self.backlog))
        generation += 1
        let current = generation
        worker = Task { await run(current) }
    }

    /// Ayarlardaki "Dinle": deneme cümlesi her zaman bu telefondan çalar (kullanıcı o an telefonun başında).
    func preview(_ voice: DubbingVoice) {
        stop()
        synthesizer.speak(SystemSpeech.utterance("Merhaba, oyundaki karakterleri Türkçe seslendireceğim.", voice: voice))
    }

    func stop() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        server().stopSpeech()
    }

    private func run(_ number: Int) async {
        while !queue.isEmpty, number == generation, !Task.isCancelled {
            let line = queue.removeFirst()
            let before = cast
            let voice = cast.voice(for: line)
            if cast.assignments != before.assignments { onCastChanged?(cast) }
            let utterance = SystemSpeech.utterance(line.turkish, voice: voice)
            switch output {
            case .computer:
                synthesizer.speak(utterance)
                // Sıradaki cümle bu bitince başlar (konuşma başlayana kadar kısa bekleme).
                try? await Task.sleep(nanoseconds: 150_000_000)
                while synthesizer.isSpeaking, number == generation, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            case .tv:
                guard let audio = await SystemSpeech.render(utterance, with: synthesizer), number == generation, !Task.isCancelled else { return }
                let milliseconds = Int(audio.duration * 1000)
                server().sendSpeech(audio.wav, durationMs: milliseconds)
                // TV sesi ağdan alıp çalmaya biraz geç başlar; sıradaki cümle bunu kesmesin.
                try? await Task.sleep(nanoseconds: UInt64(milliseconds + 250) * 1_000_000)
            }
        }
    }
}
