// SPDX-License-Identifier: AGPL-3.0-only

#if os(macOS)
import XCTest
@testable import CouchSubsCore

final class ProcessCancellationTests: XCTestCase {
    private func sleeper(_ seconds: String = "30") -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        return process
    }

    /// #359: iptal, süreç başlamadan gelirse (görev zaten iptal edilmiş) uygulama çökmemeli, süreç başlamamalı.
    func testCancelBeforeLaunchDoesNotCrashAndBlocksLaunch() {
        let process = sleeper()
        let guardian = ProcessCancellation(process)
        guardian.cancel()
        XCTAssertThrowsError(try guardian.launch()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(process.isRunning)
    }

    /// Önceden iptal edilmiş görevde `withTaskCancellationHandler` iptal bloğunu işten önce çalıştırır (çökmenin yolu).
    func testAlreadyCancelledTaskThrowsCancellation() async {
        let process = sleeper()
        let task = Task { () -> Bool in
            let guardian = ProcessCancellation(process)
            return await withTaskCancellationHandler {
                do {
                    try guardian.launch()
                    return false
                } catch {
                    return error is CancellationError
                }
            } onCancel: {
                guardian.cancel()
            }
        }
        task.cancel()
        let cancelled = await task.value
        // Görev iptalden önce başlamış olabilir; o durumda süreç başlar ama hemen durdurulmalı.
        if !cancelled { process.waitUntilExit() }
        XCTAssertFalse(process.isRunning)
    }

    func testCancelAfterLaunchTerminatesProcess() throws {
        let process = sleeper()
        let guardian = ProcessCancellation(process)
        try guardian.launch()
        XCTAssertTrue(process.isRunning)
        guardian.cancel()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    func testCancelAfterExitIsHarmless() throws {
        let process = sleeper("0")
        let guardian = ProcessCancellation(process)
        try guardian.launch()
        process.waitUntilExit()
        guardian.cancel()
        XCTAssertTrue(guardian.isCancelled)
    }
}
#endif
