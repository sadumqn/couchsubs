// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Görüntü çözücüden (saniyede 20 kare) ana iş parçacığına giden karelerin tek gözlü posta kutusu: yalnız en son kare
/// bekler, yenisi gelince eskisi atılır; ana iş parçacığına aynı anda tek teslim işi kurulur.
///
/// iPhone'da her kare için ayrı bir `Task { @MainActor }` kuruluyordu. Ana iş parçacığı bir an yavaşlayınca (ağır
/// çizim, ekran dönüşü, paket araması) bu işler birikiyordu: her biri 1080p bir kareyi (8 MB) tutuyor, sıra eridiğinde
/// hepsi art arda çalışıyor, bu arada dokunuşlar ("Çeviriyi durdur", altyazı ekranını kapatma) ve ekran dönüşü
/// gecikiyordu. Kutu, beklemedeki kare sayısını bire indirir; yavaş ana iş parçacığı yalnız kare atlar.
public final class FrameMailbox<Frame>: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Frame?
    private var delivering = false
    private var dropped = 0

    public init() {}

    /// Kareyi bırakır. Teslim işi yoksa true döner: çağıran bir teslim işi kurmalı (ve `take` boş dönene dek almalı).
    public func put(_ frame: Frame) -> Bool {
        lock.withLock {
            if latest != nil { dropped += 1 }
            latest = frame
            guard !delivering else { return false }
            delivering = true
            return true
        }
    }

    /// Bekleyen son kare; yoksa nil ve teslim işi biter (sonraki `put` yenisini kurar).
    public func take() -> Frame? {
        lock.withLock {
            guard let frame = latest else {
                delivering = false
                return nil
            }
            latest = nil
            return frame
        }
    }

    /// Kutuda başkası gelmeden üstüne yazılan (ana iş parçacığı yetişemediği için atlanan) kare sayısı; okununca sıfırlanır.
    public func takeDropped() -> Int {
        lock.withLock {
            defer { dropped = 0 }
            return dropped
        }
    }

    /// Çeviri durdu: bekleyen kare atılır.
    public func clear() {
        lock.withLock { latest = nil }
    }
}
