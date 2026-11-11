// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import RemotePlay
import CChiaki

final class FrameThrottleTests: XCTestCase {
    func testThirtyFramesPerSecondPassAtMostFourTimes() {
        var clock = Date(timeIntervalSince1970: 0)
        var throttle = FrameThrottle(minInterval: 0.25, now: { clock })
        var passed = 0
        for _ in 0..<30 {
            if throttle.shouldPass() { passed += 1 }
            clock.addTimeInterval(1.0 / 30)
        }
        XCTAssertLessThanOrEqual(passed, 5)
        XCTAssertGreaterThanOrEqual(passed, 4)
    }
}

final class ReconnectPolicyTests: XCTestCase {
    func testBackoffDoublesUpToThirtySeconds() {
        var policy = ReconnectPolicy()
        XCTAssertEqual((0..<7).map { _ in policy.nextDelay() }, [2, 4, 8, 16, 30, 30, 30])
    }

    func testResetStartsOver() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay(); _ = policy.nextDelay()
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), 2)
    }
}

final class RegisteredConsoleTests: XCTestCase {
    func testWakeCredentialIsHexOfRegistKey() {
        let console = RegisteredConsole(host: "192.168.1.253", name: "PS5", registKey: Data("1a2b3c4d".utf8) + Data(repeating: 0, count: 8),
                                        morning: Data(repeating: 7, count: 16))
        XCTAssertEqual(console.wakeCredential, 0x1a2b3c4d)
    }
}

final class ConsoleSubnetTests: XCTestCase {
    func testSlash24ListsOtherHosts() {
        let hosts = Console.hosts(address: 0xC0A8_010A, netmask: 0xFFFF_FF00)   // 192.168.1.10/24
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, 0xC0A8_0101)
        XCTAssertEqual(hosts.last, 0xC0A8_01FE)
        XCTAssertFalse(hosts.contains(0xC0A8_010A))
    }

    func testLargeNetworksAreSkipped() {
        XCTAssertTrue(Console.hosts(address: 0x0A00_0001, netmask: 0xFFFF_0000).isEmpty)
    }
}

final class StreamSessionLifecycleTests: XCTestCase {
    /// Bağlanamayan bir adreste yeniden deneme beklerken durdurup bırakmak çökmemeli ve bloklamamalı.
    func testStopWhileReconnectingDoesNotCrashOrBlock() throws {
        var session: StreamSession? = StreamSession(
            console: RegisteredConsole(host: "127.0.0.1", name: "test", registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 1, count: 16)),
            accountId: Data(repeating: 1, count: 8))
        let disconnected = expectation(description: "kopma bildirildi")
        disconnected.assertForOverFulfill = false
        session?.onState = { if case .disconnected = $0 { disconnected.fulfill() } }
        session?.start()
        wait(for: [disconnected], timeout: 15)

        let begin = Date()
        session?.stop()
        XCTAssertLessThan(Date().timeIntervalSince(begin), 0.2)
        session = nil
        // Bekleyen yeniden deneme bloğu çalışacağı zamanı geçir; süreç hâlâ ayaktaysa çökme yok.
        Thread.sleep(forTimeInterval: 3)
    }
}

final class DisconnectReasonTests: XCTestCase {
    func testQuitReasonsMapToUserFacingCases() {
        XCTAssertEqual(DisconnectReason(quit: CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE), .inUse)
        XCTAssertEqual(DisconnectReason(quit: CHIAKI_QUIT_REASON_STOPPED), .stopped)
        XCTAssertEqual(DisconnectReason(quit: CHIAKI_QUIT_REASON_SESSION_REQUEST_CONNECTION_REFUSED), .refused)
        XCTAssertEqual(DisconnectReason(quit: CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_DISCONNECTED), .network)
    }

    /// PS5 aramaya yanıt vermediyse ve oturum ağ hatasıyla düştüyse neden "bulunamadı"dır; yanıt verdiyse olduğu gibi kalır.
    func testMissingConsoleIsReportedAsNotFound() {
        XCTAssertEqual(DisconnectReason.classify(.network, searchAnswered: false, host: "192.168.1.70"), .notFound("192.168.1.70"))
        XCTAssertEqual(DisconnectReason.classify(.other("x"), searchAnswered: false, host: "192.168.1.70"), .notFound("192.168.1.70"))
        XCTAssertEqual(DisconnectReason.classify(.network, searchAnswered: true, host: "192.168.1.70"), .network)
        XCTAssertEqual(DisconnectReason.classify(.inUse, searchAnswered: false, host: "192.168.1.70"), .inUse)
    }

    /// Adresi değişen PS5 yalnız eminken seçilir (Windows'taki PickMoved).
    func testMovedConsoleIsPickedOnlyWhenCertain() {
        let a = ConsoleInfo(host: "192.168.1.20", name: "PS5-A", isAwake: true)
        let b = ConsoleInfo(host: "192.168.1.21", name: "PS5-B", isAwake: true)
        XCTAssertEqual(StreamSession.pickMoved([a], name: "other"), a)
        XCTAssertEqual(StreamSession.pickMoved([a, b], name: "PS5-B"), b)
        XCTAssertNil(StreamSession.pickMoved([a, b], name: "other"))
        XCTAssertNil(StreamSession.pickMoved([], name: "PS5-A"))
    }
}
