// SPDX-License-Identifier: AGPL-3.0-only
// İlk kareden sonra Xbox görüntüsü kesilince uyarı ve yeniden kurma. Sahte saat: anlar ms olarak verilir.
// Windows'taki XboxPictureWatchTests.cs ve Android'deki XboxPictureWatchTest.kt ile aynı durumlar.

import XCTest
@testable import CouchSubsCore

final class XboxPictureWatchTests: XCTestCase {
    func testNothingIsDecidedBeforeTheFirstFrame() {
        var watch = XboxPictureWatch()
        watch.iceChanged(.disconnected, atMs: 0)
        XCTAssertEqual(watch.tick(atMs: 60_000), .fine)
    }

    func testFlowingPictureIsFine() {
        var watch = XboxPictureWatch()
        for second in 0..<120 {
            watch.frameArrived(atMs: second * 1000)
            XCTAssertEqual(watch.tick(atMs: second * 1000 + 500), .fine)
        }
    }

    func testWarnsOnceThenReconnectsWhenFramesStopWhileTheConnectionLooksOpen() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 0)
        watch.frameArrived(atMs: 40_000)
        XCTAssertEqual(watch.tick(atMs: 44_000), .fine)
        XCTAssertEqual(watch.tick(atMs: 45_000), .warn)
        XCTAssertTrue(watch.warned)
        XCTAssertEqual(watch.tick(atMs: 46_000), .fine)
        XCTAssertEqual(watch.tick(atMs: 51_000), .fine)
        XCTAssertEqual(watch.tick(atMs: 52_000), .stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"))
    }

    /// Yayının ilk 30 sn'sinde kare boşluğu oturumu kapatmaz (yalnız uyarı); sınırdan sonra kapatır.
    func testGapsInTheFirstThirtySecondsDoNotEndTheSession() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 1000)
        XCTAssertEqual(watch.tick(atMs: 6000), .warn)
        for at in stride(from: 7000, through: 30_000, by: 1000) { XCTAssertEqual(watch.tick(atMs: at), .fine) }
        XCTAssertEqual(watch.tick(atMs: 31_000), .stalled("Xbox'tan 30 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"))
    }

    func testFlowingMeansARecentFrame() {
        var watch = XboxPictureWatch()
        XCTAssertFalse(watch.isFlowing(atMs: 0))
        watch.frameArrived(atMs: 1000)
        XCTAssertTrue(watch.isFlowing(atMs: 5999))
        XCTAssertFalse(watch.isFlowing(atMs: 6000))
    }

    func testRecoversWhenFramesComeBackBeforeTheLimit() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 0)
        XCTAssertEqual(watch.tick(atMs: 6000), .warn)
        watch.frameArrived(atMs: 8000)
        XCTAssertEqual(watch.tick(atMs: 8500), .recovered)
        XCTAssertFalse(watch.warned)
        XCTAssertEqual(watch.tick(atMs: 9500), .fine)
    }

    func testIceDisconnectedWarnsAfterOneSecondWithoutFrames() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 0)
        watch.iceChanged(.disconnected, atMs: 200)
        XCTAssertEqual(watch.tick(atMs: 500), .fine)
        XCTAssertEqual(watch.tick(atMs: 1200), .warn)
        watch.iceChanged(.connected, atMs: 3000)
        watch.frameArrived(atMs: 3100)
        XCTAssertEqual(watch.tick(atMs: 3500), .recovered)
    }

    func testIceStuckInDisconnectedEndsTheSessionAtTheLimit() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 0)
        watch.frameArrived(atMs: 40_000)
        watch.iceChanged(.disconnected, atMs: 40_100)
        XCTAssertEqual(watch.tick(atMs: 41_000), .warn)
        XCTAssertEqual(watch.tick(atMs: 52_000), .stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (ICE disconnected)"))
    }

    func testIceFailedEndsTheSessionAtOnce() {
        var watch = XboxPictureWatch()
        watch.frameArrived(atMs: 0)
        watch.iceChanged(.failed, atMs: 500)
        XCTAssertEqual(watch.tick(atMs: 600), .stalled("Xbox ICE bağlantısı koptu (failed)"))
    }

    func testFramesWhileIceSaysDisconnectedDoNotWarn() {
        var watch = XboxPictureWatch()
        watch.iceChanged(.disconnected, atMs: 0)
        for second in 0..<20 {
            watch.frameArrived(atMs: second * 1000)
            XCTAssertEqual(watch.tick(atMs: second * 1000 + 300), .fine)
        }
    }

    func testStalledSessionRetriesThroughTheMachine() {
        var clock = 0.0
        var machine = XboxSessionMachine(clock: { clock })
        XCTAssertEqual(machine.start(), .play)
        XCTAssertEqual(machine.played(), .pollState(delayMs: 0))
        XCTAssertEqual(machine.status("Provisioned", errorDetails: nil), .negotiate)
        XCTAssertTrue(machine.streaming())
        clock = 30_000
        XCTAssertEqual(machine.fail(.noPicture, "Xbox'tan 12 sn'dir görüntü gelmiyor"), .retry(delayMs: 5000))
        XCTAssertEqual(machine.phase, .failed(.noPicture, message: "Xbox'tan 12 sn'dir görüntü gelmiyor", willRetry: true, attempt: 1))
    }

    /// Sahte Xbox oturumu (bekçiler XboxStreamSession'daki gibi saniyede bir; canlı tutma 30 sn'de bir). Play'deki bildirim
    /// (Android beta.85): "uzaktan yürütme başlatıldı, hemen ardından durdu, tekrar başladı/durdu". Yayın başında görüntü
    /// birkaç saniye bekliyor, canlı tutma 404 dönüyor: ilk 30 sn'de (ve görüntü akarken sonrasında da) oturum kapatılmıyor,
    /// yeniden açılmıyor. Sonra gerçek kopma: en çok bir kez, 5 sn sonra yeniden bağlanılıyor. Android'deki
    /// fakeXboxSessionDoesNotLoopAndReconnectsAtMostOnce ve Windows'taki aynı adlı testle aynı senaryo.
    func testFakeXboxSessionDoesNotLoopAndReconnectsAtMostOnce() {
        let session = FakeXboxSession()
        session.connect()
        session.frames(1000...3000)
        // 3–20 sn: Xbox görüntüyü bekletiyor (yükleme, bildirim); 20 sn'den sonra yine akıyor.
        session.frames(20_000...70_000)
        session.keepaliveFails = "Xbox service HTTP 404: "
        for at in stride(from: 0, through: 70_000, by: 1000) { session.tick(at) }
        XCTAssertEqual(session.ends, [], "ilk 30 sn'de ve görüntü akarken kapatma yok")
        XCTAssertEqual(session.plays, 1)

        // Gerçek kopma: Wi-Fi gitti, ICE disconnected, kare yok.
        session.iceLost(70_500)
        for at in stride(from: 71_000, through: 82_000, by: 1000) { session.tick(at) }
        XCTAssertEqual(session.ends.count, 1)
        XCTAssertEqual(session.retries, [5000])
        XCTAssertEqual(session.plays, 2)
        // Yeniden bağlanma da kısa sürede kopuyor: ikinci deneme yok, yayın durur ("Yeniden bağlan" düğmesi).
        session.frames(96_000...100_000)
        session.iceLost(100_500)
        for at in stride(from: 96_000, through: 160_000, by: 1000) { session.tick(at) }
        XCTAssertEqual(session.retries, [5000, nil])
        XCTAssertEqual(session.plays, 2)
    }
}

/// XboxStreamSession'ın bekçi döngüsünün ağsız kopyası (oturum makinesi, görüntü bekçisi, canlı tutma).
private final class FakeXboxSession {
    private var now = 0
    private lazy var machine = XboxSessionMachine(clock: { [unowned self] in Double(self.now) })
    private var watch = XboxPictureWatch()
    private var keepalive = XboxKeepalive()
    private var frameTimes = Set<Int>()
    private var connectedAt = 0
    private var stopped = false
    var keepaliveFails: String?
    var plays = 0
    var ends: [String] = []
    var retries: [Int?] = []

    func connect() {
        _ = machine.start(); _ = machine.played(); _ = machine.status("Provisioned", errorDetails: nil)
        plays += 1
        connectedAt = now
        watch = XboxPictureWatch()
        keepalive = XboxKeepalive()
    }

    /// Xbox bu aralıkta ~60 kare/sn gönderir.
    func frames(_ range: ClosedRange<Int>) { for at in stride(from: range.lowerBound, through: range.upperBound, by: 16) { frameTimes.insert(at) } }

    func iceLost(_ at: Int) {
        frameTimes = frameTimes.filter { $0 < at }
        watch.iceChanged(.disconnected, atMs: at)
    }

    func tick(_ at: Int) {
        guard !stopped else { return }
        now = at
        for frame in frameTimes.filter({ $0 > at - 1000 && $0 <= at }).sorted() {
            if machine.phase == .negotiating { _ = machine.streaming() }
            watch.frameArrived(atMs: frame)
        }
        let since = at - connectedAt
        if since > 0 && since % (XboxKeepalive.intervalSeconds * 1000) == 0, let error = keepaliveFails {
            let exhausted = keepalive.failed()
            if XboxKeepalive.shouldEnd(gone: XboxKeepalive.sessionGone(error), exhausted: exhausted, pictureFlowing: watch.isFlowing(atMs: at)) {
                return end("canlı tutma", .serverClosed)
            }
        }
        if case let .stalled(reason) = watch.tick(atMs: at) { end(reason, .noPicture) }
    }

    private func end(_ reason: String, _ kind: XboxErrorKind) {
        ends.append(reason)
        guard case let .retry(delay) = machine.fail(kind, reason) else { return }
        retries.append(delay)
        guard let delay else {
            stopped = true
            return
        }
        now += delay
        connect()
    }
}
