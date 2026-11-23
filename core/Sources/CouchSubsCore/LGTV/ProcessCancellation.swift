// SPDX-License-Identifier: AGPL-3.0-only

#if os(macOS)
import Foundation

/// Bir `Process`'i görev iptaliyle güvenle başlatır ve durdurur.
///
/// Foundation, hiç başlamamış `Process`'e `terminate()` çağrılınca `NSInvalidArgumentException` ("task not launched")
/// fırlatır ve uygulama kapanır. `withTaskCancellationHandler` ise görev zaten iptal edilmişse iptal bloğunu işten
/// önce çalıştırır; Mac'te Android TV kurulumunda "Devam"a basınca uygulama böyle çöküyordu (#359). Burada başlatma
/// ve durdurma aynı kilitle sıraya girer: iptal önce gelirse süreç hiç başlatılmaz, sonra gelirse çalışan süreç durur.
public final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var cancelled = false
    private var launched = false

    public init(_ process: Process) { self.process = process }

    /// Süreci başlatır. İptal edildiyse başlatmaz, `CancellationError` atar.
    public func launch() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
            launched = true
        }
    }

    /// İptal: başlamışsa ve çalışıyorsa süreci durdurur, başlamadıysa bir daha başlatılmasını engeller.
    public func cancel() {
        lock.withLock {
            cancelled = true
            if launched, process.isRunning { process.terminate() }
        }
    }

    public var isCancelled: Bool { lock.withLock { cancelled } }
}
#endif
