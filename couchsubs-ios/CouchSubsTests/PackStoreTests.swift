// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import CouchSubs

/// Sahte paket sunucusu: istekleri kaydeder, yol başına yanıt verir.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.responses[request.url!.path] ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PackStoreTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private let base = URL(string: "https://packs.test")!
    private let pack = Data(#"{"format":1,"id":"demo","title":"Demo","entries":{"\#(PackKey.key("Hello there, my friend.")!)":"Merhaba dostum."}}"#.utf8)

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
        StubProtocol.requests = []
        StubProtocol.responses = [:]
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    /// Sunucunun biçimi: sürüm artan bir sayı (server/packs/scripts/build-index.mjs).
    private func manifest(sha: String) -> Data {
        Data(#"{"packs":[{"id":"demo","title":"Demo","version":1,"sha256":"\#(sha)","size":10,"entries":1}]}"#.utf8)
    }

    private func store(token: String? = "token", now: Date = Date()) -> PackStore {
        PackStore(baseURL: base, directory: directory, session: session, token: { token }, now: { now })
    }

    func testDownloadsVerifiedPackAndSendsToken() async throws {
        StubProtocol.responses["/v1/packs"] = (200, manifest(sha: PackStore.sha256(pack)))
        StubProtocol.responses["/v1/packs/demo"] = (200, pack)
        let store = store()
        let downloaded = try await store.refresh(force: true)
        XCTAssertEqual(downloaded, 1)
        let file = store.filesDirectory.appendingPathComponent("demo.json.gz")
        XCTAssertEqual(try Data(contentsOf: file), pack)
        XCTAssertEqual(StubProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        // Kütüphane indirilen paketi okur.
        let library = GamePackLibrary(bundled: nil, user: store.filesDirectory)
        XCTAssertEqual(library.packs.map(\.id), ["demo"])
    }

    func testUnchangedPackIsNotDownloadedAgain() async throws {
        StubProtocol.responses["/v1/packs"] = (200, manifest(sha: PackStore.sha256(pack)))
        StubProtocol.responses["/v1/packs/demo"] = (200, pack)
        let store = store()
        try await store.refresh(force: true)
        StubProtocol.requests = []
        let second = try await store.refresh(force: true)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(StubProtocol.requests.map { $0.url!.path }, ["/v1/packs"])
    }

    func testChecksumMismatchKeepsFileOut() async {
        StubProtocol.responses["/v1/packs"] = (200, manifest(sha: String(repeating: "0", count: 64)))
        StubProtocol.responses["/v1/packs/demo"] = (200, pack)
        let store = store()
        do {
            try await store.refresh(force: true)
            XCTFail("SHA-256 tutmadı")
        } catch {
            XCTAssertEqual(error as? PackStore.Failure, .badChecksum("demo"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.filesDirectory.appendingPathComponent("demo.json.gz").path))
    }

    func testServerRefusalsAreExplained() async {
        StubProtocol.responses["/v1/packs"] = (200, manifest(sha: PackStore.sha256(pack)))
        StubProtocol.responses["/v1/packs/demo"] = (403, Data(#"{"error":"subscription_required"}"#.utf8))
        do {
            try await store().refresh(force: true)
            XCTFail("abonelik yok")
        } catch {
            XCTAssertEqual(error as? PackStore.Failure, .notSubscribed)
        }
        // Liste herkese açık; paket jeton ister ve jetonsuz paket isteği gönderilmez.
        StubProtocol.requests = []
        do {
            try await store(token: nil).refresh(force: true)
            XCTFail("giriş yok")
        } catch {
            XCTAssertEqual(error as? PackStore.Failure, .notSignedIn)
        }
        XCTAssertEqual(StubProtocol.requests.map { $0.url!.path }, ["/v1/packs"])
        XCTAssertNil(StubProtocol.requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testRefreshIsWeekly() async throws {
        StubProtocol.responses["/v1/packs"] = (200, Data(#"{"packs":[]}"#.utf8))
        let start = Date()
        try await store(now: start).refresh(force: true)
        let soon = await store(now: start.addingTimeInterval(3 * 24 * 3600)).needsRefresh()
        XCTAssertFalse(soon)
        let later = await store(now: start.addingTimeInterval(8 * 24 * 3600)).needsRefresh()
        XCTAssertTrue(later)
        StubProtocol.requests = []
        try await store(now: start.addingTimeInterval(24 * 3600)).refresh()
        XCTAssertTrue(StubProtocol.requests.isEmpty, "hafta dolmadan istek yok")
    }

    func testRemovedPackIsDeletedFromCache() async throws {
        StubProtocol.responses["/v1/packs"] = (200, manifest(sha: PackStore.sha256(pack)))
        StubProtocol.responses["/v1/packs/demo"] = (200, pack)
        let store = store()
        try await store.refresh(force: true)
        StubProtocol.responses["/v1/packs"] = (200, Data(#"{"packs":[]}"#.utf8))
        try await store.refresh(force: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.filesDirectory.appendingPathComponent("demo.json.gz").path))
    }
}
