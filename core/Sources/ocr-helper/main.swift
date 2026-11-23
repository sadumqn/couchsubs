// SPDX-License-Identifier: AGPL-3.0-only

// Yedek okuyucunun (ayrı süreçte yazı tanıma, `OcrHelper`) testlerde ve ölçümde kullanılan çalıştırılabilir hâli.
// Uygulamada yardımcı, uygulamanın kendi dosyasıdır (`--ocr-helper`).
//
//   ocr-helper                      stdin'den kare alır, stdout'a satırları yazar (uygulamadaki gibi)
//   ocr-helper olc <png> <tur>      aynı kareyi <tur> kez okur; süre, bellek ve takılmayı ölçer (uzun çalıştırma)

import CoreGraphics
import CouchSubsCore
import Foundation
import ImageIO

#if os(macOS)
let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "olc" {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, nil),
          let frame = CGImageSourceCreateImageAtIndex(source, 0, nil), let rounds = Int(arguments[3]) else {
        print("kare okunamadı")
        exit(1)
    }
    // Altyazı bölgesi, bir ek alan ve bütün kare sırayla; okumalar uygulamadaki gibi `ReadQueue`'dan geçer.
    let reader = VisionReader(language: "en")
    let crops: [CGImage] = [
        frame.cropping(to: CGRect(x: 0, y: Int(Double(frame.height) * 0.7), width: frame.width, height: Int(Double(frame.height) * 0.3))) ?? frame,
        frame.cropping(to: CGRect(x: 0, y: 0, width: frame.width / 2, height: frame.height / 2)) ?? frame,
        frame,
    ]
    let queue = ReadQueue(label: "olc")
    queue.onEvent = { print("OLAY: \($0)") }
    let done = DispatchSemaphore(value: 0)
    Task {
        let began = Date()
        var total = 0.0, longest = 0.0, failures = 0, characters = 0
        var round = 1
        while round <= rounds {
            let crop = crops[round % crops.count]
            let started = Date()
            do {
                let reading = try await queue.run(priority: round % 3 == 0 ? .subtitle : .background, detail: ReadQueue.detail("ölçüm", crop)) {
                    try reader.readLines(crop, deep: false)
                }
                characters += reading.text.count
            } catch ReadQueueError.stuck {
                // Okuyucu takılı (ör. model derleniyor): uygulamadaki gibi beklenir, aynı kare yeniden denenir.
                try? await Task.sleep(for: .milliseconds(500))
                continue
            } catch {
                failures += 1
            }
            defer { round += 1 }
            let ms = Date().timeIntervalSince(started) * 1000
            total += ms
            longest = max(longest, ms)
            if round % 1000 == 0 || round == rounds {
                print(String(format: "%6d okuma  ort %.0f ms  en uzun %.0f ms  hata %d  bellek %d MB  ısı %@  %.0f sn", round, total / Double(round),
                             longest, failures, ReadQueue.memoryMB() ?? -1, ReadQueue.thermalName(), Date().timeIntervalSince(began)))
                fflush(stdout)
            }
        }
        print("karakter: \(characters)")
        done.signal()
    }
    done.wait()
    exit(0)
}
OcrHelper.runAsHelper()
#else
print("yalnız macOS")
#endif
