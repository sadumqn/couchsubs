// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Kullanım verisi (GA4 Measurement Protocol): ortak deneme dosyasındaki olaylardan aynı adres ve gövde (Fixtures/
/// usage-stats.json; Windows UsageStatsTests.cs aynı dosyayı okur), kapalıyken ve yapılandırılmamışken hiç istek yok.
final class UsageStatsTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        var status = 204
        var fails = false
        var requests: [URLRequest] { lock.withLock { stored } }

        var send: UsageStats.Send {
            { request in
                self.lock.withLock { self.stored.append(request) }
                if self.fails { throw URLError(.notConnectedToInternet) }
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    private let config = UsageStats.Config(measurementID: "G-TEST", apiSecret: "secret")!

    private func idFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)").appendingPathComponent("usage-id")
    }

    private func fixture() throws -> [String: Any] {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("usage-stats.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private static func event(_ spec: [String: Any]) -> UsageStats.Event {
        switch spec["kind"] as! String {
        case "screen": .screen(spec["screen"] as! String)
        case "onboarding_done": .onboardingDone(target: spec["target"] as! String, console: spec["console"] as! String)
        case "session_start": .sessionStart(target: spec["target"] as! String, engine: spec["engine"] as! String,
                                            packs: spec["packs"] as! Bool, console: spec["console"] as! String)
        case "session_stop": .sessionStop(seconds: spec["seconds"] as! Int, lines: spec["lines"] as! Int, packLines: spec["pack_lines"] as! Int)
        case "tv_connected": .tvConnected(count: spec["count"] as! Int, brand: spec["brand"] as! String)
        case "pack_hit": .packHit(spec["pack"] as! String)
        default: fatalError("bilinmeyen olay")
        }
    }

    func testSharedVectorBuildsSameURLAndBody() throws {
        let vector = try fixture()
        let config = try XCTUnwrap(UsageStats.Config(measurementID: vector["measurement_id"] as? String, apiSecret: vector["api_secret"] as? String))
        XCTAssertEqual(UsageStats.url(config)?.absoluteString, vector["url"] as? String)
        let events = (vector["events"] as! [[String: Any]]).map(Self.event)
        let body = UsageStats.payload(clientID: vector["client_id"] as! String, sessionID: vector["session_id"] as! String,
                                      userProperties: vector["user_properties"] as! [String: String], events: events)
        let built = try JSONSerialization.jsonObject(with: body) as! NSDictionary
        XCTAssertEqual(built, vector["body"] as! NSDictionary)
    }

    func testSendsQueuedEventsInBatchesWithStableRandomID() async throws {
        let recorder = Recorder()
        let file = idFile()
        let stats = UsageStats(config: config, idFile: file, appVersion: "1", osVersion: "macOS 15", platform: "mac", send: recorder.send)
        for _ in 0..<30 { stats.record(.screen("home")) }
        await stats.flush()
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertTrue(stats.queued.isEmpty)
        let first = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual((first["events"] as! [Any]).count, UsageStats.batchSize)
        let id = first["client_id"] as! String
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), id)
        // Yeni açılışta aynı kimlik kullanılır.
        let again = UsageStats(config: config, idFile: file, appVersion: "1", osVersion: "macOS 15", platform: "mac", send: recorder.send)
        again.record(.packHit("gta6"))
        await again.flush()
        let third = try JSONSerialization.jsonObject(with: recorder.requests[2].httpBody!) as! [String: Any]
        XCTAssertEqual(third["client_id"] as? String, id)
    }

    func testTurnedOffSendsNothing() async {
        let recorder = Recorder()
        let stats = UsageStats(config: config, enabled: false, idFile: idFile(), appVersion: "1", osVersion: "x", platform: "mac", send: recorder.send)
        stats.record(.screen("home"))
        stats.record(.sessionStart(target: "tv", engine: "free", packs: true, console: "ps5"))
        await stats.flush()
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertTrue(stats.queued.isEmpty)
    }

    func testTurningOffDropsWaitingEvents() async {
        let recorder = Recorder()
        let stats = UsageStats(config: config, idFile: idFile(), appVersion: "1", osVersion: "x", platform: "mac", send: recorder.send)
        stats.record(.screen("home"))
        stats.setEnabled(false)
        await stats.flush()
        XCTAssertTrue(recorder.requests.isEmpty)
        stats.setEnabled(true)
        await stats.flush()
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testWithoutBuildConfigNothingIsQueuedOrSent() async {
        XCTAssertNil(UsageStats.Config(measurementID: "", apiSecret: "secret"))
        XCTAssertNil(UsageStats.Config(measurementID: "$(GA_MEASUREMENT_ID)", apiSecret: "$(GA_API_SECRET)"))
        let recorder = Recorder()
        let file = idFile()
        let stats = UsageStats(config: nil, idFile: file, appVersion: "1", osVersion: "x", platform: "mac", send: recorder.send)
        XCTAssertFalse(stats.isConfigured)
        stats.record(.screen("home"))
        await stats.flush()
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertTrue(stats.queued.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testNetworkErrorKeepsEventsQuietly() async {
        let recorder = Recorder()
        recorder.fails = true
        let stats = UsageStats(config: config, idFile: idFile(), appVersion: "1", osVersion: "x", platform: "mac", send: recorder.send)
        stats.record(.screen("home"))
        await stats.flush()
        XCTAssertEqual(stats.queued.count, 1)
        recorder.fails = false
        await stats.flush()
        XCTAssertTrue(stats.queued.isEmpty)
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testQueueIsBounded() {
        let stats = UsageStats(config: config, idFile: idFile(), appVersion: "1", osVersion: "x", platform: "mac", send: Recorder().send)
        for index in 0..<(UsageStats.maxQueue + 10) { stats.record(.packHit("p\(index)")) }
        XCTAssertEqual(stats.queued.count, UsageStats.maxQueue)
        XCTAssertEqual(stats.queued.first, .packHit("p10"))
    }
}
