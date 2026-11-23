// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// Paket sunucusunun yerine geçen sahte HTTP: liste ve dosyalar bellekte.
private final class FakePackServer: @unchecked Sendable {
    private let lock = NSLock()
    var packs: [RemotePack] = []
    var files: [String: Data] = [:]
    var listStatus = 200
    private(set) var downloads: [String] = []

    func add(_ id: String, version: Int64, data: Data, title: String? = nil) {
        lock.withLock {
            packs.removeAll { $0.id == id }
            packs.append(RemotePack(id: id, title: title ?? id, version: version, sha256: PackUpdater.sha256(data),
                                    size: Int64(data.count), entries: 1))
            files[id] = data
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let reply: (Int, Data) = lock.withLock {
            if url.path == "/v1/packs" {
                return (listStatus, try! JSONEncoder().encode(["packs": packs]))
            }
            let id = url.lastPathComponent
            downloads.append(id)
            return files[id].map { (200, $0) } ?? (404, Data())
        }
        return (reply.1, HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}

private final class UpdaterClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_793_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

final class PackUpdaterTests: XCTestCase {
    private var root: URL!
    private var packs: URL { root.appendingPathComponent("packs") }
    private let server = FakePackServer()
    private let clock = UpdaterClock()

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("updater-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeUpdater() -> PackUpdater {
        let server = self.server
        let clock = self.clock
        return PackUpdater(baseURL: URL(string: "https://packs.example.test")!, directory: packs,
                           stateFile: root.appendingPathComponent("packs-remote.json"),
                           fetch: { try await server.send($0) }, clock: { clock.now })
    }

    private func content(_ id: String) -> Data? { try? Data(contentsOf: packs.appendingPathComponent("\(id).json.gz")) }

    func testDownloadsVerifiesAndSkipsUntilAWeekPasses() async {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        let first = await updater.refresh()
        XCTAssertEqual(first.downloaded, ["gta-6"])
        XCTAssertEqual(content("gta-6"), Data("one".utf8))

        server.add("gta-6", version: 2, data: Data("two".utf8))
        let early = await updater.refresh()
        XCTAssertTrue(early.skipped)
        clock.advance(PackUpdater.refreshInterval + 1)
        let later = await updater.refresh()
        XCTAssertEqual(later.downloaded, ["gta-6"])
        XCTAssertEqual(content("gta-6"), Data("two".utf8))

        // Sürüm değişmediyse yeniden inmez.
        let count = server.downloads.count
        _ = await updater.refresh(force: true)
        XCTAssertEqual(server.downloads.count, count)
    }

    func testNewGameChecksAfterTenMinutes() async {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        _ = await updater.refresh()
        server.add("pool-ppsa01234", version: 1, data: Data("auto".utf8))
        let soon = await updater.refresh(maxAge: PackUpdater.gameCheckInterval)
        XCTAssertTrue(soon.skipped)
        clock.advance(PackUpdater.gameCheckInterval + 1)
        let later = await updater.refresh(maxAge: PackUpdater.gameCheckInterval)
        XCTAssertEqual(later.downloaded, ["pool-ppsa01234"])
    }

    func testWrongChecksumIsNeverInstalled() async {
        server.add("gta-6", version: 1, data: Data("good".utf8))
        server.files["gta-6"] = Data("tampered".utf8)
        let updater = makeUpdater()
        let result = await updater.refresh()
        XCTAssertEqual(result.downloaded, [])
        XCTAssertNil(content("gta-6"))
        let installed = await updater.installed
        XCTAssertEqual(installed, [])
    }

    /// Yeni bir paket inemediyse kontrol zamanı ilerlemez: başka paket duruyor olsa da sonraki bakışta yeniden denenir.
    func testFailedNewPackIsRetriedWithoutWaitingADay() async {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        _ = await updater.refresh()

        server.add("rdr-2", version: 1, data: Data("new".utf8))
        let good = server.files["rdr-2"]
        server.files["rdr-2"] = nil
        clock.advance(PackUpdater.refreshInterval + 1)
        let failed = await updater.refresh()
        XCTAssertEqual(failed.downloaded, [])
        // "Paketleri şimdi güncelle" bunu hata olarak gösterir.
        XCTAssertTrue(failed.incomplete)

        server.files["rdr-2"] = good
        clock.advance(60)
        let retried = await updater.refresh(maxAge: PackUpdater.gameCheckInterval)
        XCTAssertFalse(retried.incomplete)
        XCTAssertFalse(retried.skipped)
        XCTAssertEqual(retried.downloaded, ["rdr-2"])
        XCTAssertEqual(content("gta-6"), Data("one".utf8))
    }

    func testFailedReplacementRetainsInstalledPackAndRetries() async throws {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        let first = await updater.refresh()
        XCTAssertEqual(first.downloaded, ["gta-6"])
        let installedBefore = await updater.installed
        XCTAssertEqual(installedBefore.count, 1)
        let original = try XCTUnwrap(installedBefore.first)

        server.add("gta-6", version: 2, data: Data("two".utf8))
        let staging = packs.appendingPathComponent(".gta-6.download")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let failed = await updater.refresh(force: true)

        XCTAssertEqual(failed.downloaded, [])
        XCTAssertTrue(failed.incomplete, "Disk write failure should be shown as an incomplete update")
        XCTAssertEqual(content("gta-6"), Data("one".utf8))
        let retained = await updater.installed
        XCTAssertEqual(retained, [
            .init(id: "gta-6", title: "gta-6", version: -1, sha256: original.sha256)
        ])

        let retried = await updater.refresh()
        XCTAssertEqual(retried.downloaded, ["gta-6"])
        XCTAssertEqual(content("gta-6"), Data("two".utf8))
        let installedAfter = await updater.installed
        XCTAssertEqual(installedAfter.first?.version, 2)
    }

    func testFailedFirstDiskWriteReportsIncompleteAndRetriesImmediately() async throws {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        _ = await updater.refresh()

        server.add("rdr-2", version: 1, data: Data("two".utf8))
        clock.advance(PackUpdater.refreshInterval + 1)
        let staging = packs.appendingPathComponent(".rdr-2.download")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let failed = await updater.refresh()
        XCTAssertTrue(failed.incomplete, "Disk failure must not count as a completed refresh")
        XCTAssertTrue(failed.downloaded.isEmpty)
        XCTAssertEqual(content("gta-6"), Data("one".utf8))
        XCTAssertNil(content("rdr-2"))

        // The updater may have removed the blocked staging directory on failure.
        try? FileManager.default.removeItem(at: staging)
        clock.advance(1)
        let retried = await updater.refresh()
        XCTAssertFalse(retried.skipped)
        XCTAssertEqual(retried.downloaded, ["rdr-2"])
    }

    func testRemovedPackIsDeletedAndUnreachableServerKeepsPacks() async {
        server.add("gta-6", version: 1, data: Data("one".utf8))
        let updater = makeUpdater()
        _ = await updater.refresh()

        server.listStatus = 503
        let down = await updater.refresh(force: true)
        XCTAssertTrue(down.failed)
        XCTAssertNotNil(content("gta-6"))

        server.listStatus = 200
        server.packs = []
        let gone = await updater.refresh(force: true)
        XCTAssertEqual(gone.removed, ["gta-6"])
        XCTAssertNil(content("gta-6"))
    }

    /// Kullanıcının klasöre kendisi bıraktığı aynı adlı dosyanın üstüne yazılmaz, silinmez.
    func testUserFilesAreLeftAlone() async throws {
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: packs.appendingPathComponent("gta-6.json.gz"))
        server.add("gta-6", version: 1, data: Data("server".utf8))
        server.add("../evil", version: 1, data: Data("x".utf8))
        let updater = makeUpdater()
        let result = await updater.refresh()
        XCTAssertEqual(result.downloaded, [])
        XCTAssertEqual(content("gta-6"), Data("mine".utf8))
        XCTAssertFalse(server.downloads.contains("evil"))

        await updater.clear()
        XCTAssertEqual(content("gta-6"), Data("mine".utf8))
    }

    func testAddressComesOnlyFromConfiguration() {
        let defaults = TestDefaults.make("packs")
        XCTAssertNil(PackUpdater.configuredBaseURL(environment: [:], defaults: defaults, bundle: Bundle(for: Self.self)))
        XCTAssertNil(PackUpdater.configuredBaseURL(environment: ["COUCHSUBS_PACKS_URL": "  "], defaults: defaults,
                                                   bundle: Bundle(for: Self.self)))
        XCTAssertNil(PackUpdater.configuredBaseURL(environment: ["COUCHSUBS_PACKS_URL": "ftp://x"], defaults: defaults,
                                                   bundle: Bundle(for: Self.self)))
        XCTAssertEqual(PackUpdater.configuredBaseURL(environment: ["COUCHSUBS_PACKS_URL": "https://packs.example.test"],
                                                     defaults: defaults, bundle: Bundle(for: Self.self))?.host, "packs.example.test")
        defaults.set("https://from-settings.test", forKey: "packsURL")
        XCTAssertEqual(PackUpdater.configuredBaseURL(environment: [:], defaults: defaults, bundle: Bundle(for: Self.self))?.host,
                       "from-settings.test")
    }

    func testPackIdsMatchTheServer() {
        XCTAssertTrue(PackUpdater.isValidId("gta-6"))
        XCTAssertTrue(PackUpdater.isValidId("red-dead-redemption-2"))
        XCTAssertFalse(PackUpdater.isValidId("-gta"))
        XCTAssertFalse(PackUpdater.isValidId("../evil"))
        XCTAssertFalse(PackUpdater.isValidId("GTA"))
        XCTAssertFalse(PackUpdater.isValidId(""))
    }
}
