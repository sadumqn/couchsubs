// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubsCore

/// Birincil paket adresi (workers.dev) ulaşılamazsa yedek adres (#583).
private final class MirrorServer: @unchecked Sendable {
    enum Answer { case body(Data), status(Int), unreachable }
    private let lock = NSLock()
    private var answers: [String: Answer] = [:]
    private(set) var calls: [String] = []

    func set(_ url: String, _ answer: Answer?) { lock.withLock { answers[url] = answer } }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let answer: Answer = lock.withLock {
            calls.append(url.absoluteString)
            return answers[url.absoluteString] ?? .unreachable
        }
        switch answer {
        case let .body(data): return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case let .status(code): return (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case .unreachable: throw URLError(.cannotFindHost)
        }
    }
}

final class PackMirrorsTests: XCTestCase {
    private let primary = URL(string: "https://packs.primary.test")!
    private let fallback = URL(string: "https://packs.fallback.test/")!
    private let server = MirrorServer()

    private func get(_ mirrors: PackMirrors, _ path: String) async -> Result<Data, PackMirrors.Failure> {
        let server = self.server
        return await mirrors.get(path, timeout: 5, fetch: { try await server.send($0) })
    }

    func testPrimaryWorksFallbackUntouched() async {
        server.set("https://packs.primary.test/v1/packs", .body(Data("ok".utf8)))
        let result = await get(PackMirrors(primary: primary, fallbacks: [fallback]), "v1/packs")
        XCTAssertEqual(try? result.get(), Data("ok".utf8))
        XCTAssertEqual(server.calls, ["https://packs.primary.test/v1/packs"])
    }

    func testNetworkErrorFallsBackAndRemembersWorkingAddress() async {
        server.set("https://packs.fallback.test/v1/packs", .body(Data("list".utf8)))
        server.set("https://packs.fallback.test/v1/packs/gta-6", .body(Data("pack".utf8)))
        let mirrors = PackMirrors(primary: primary, fallbacks: [fallback])
        let list = await get(mirrors, "v1/packs")
        XCTAssertEqual(try? list.get(), Data("list".utf8))
        XCTAssertEqual(mirrors.preferredIndex, 1)
        let pack = await get(mirrors, "v1/packs/gta-6")
        XCTAssertEqual(try? pack.get(), Data("pack".utf8))
        // Paket doğrudan yedekten iner; birincil adres her istekte yeniden beklenmez.
        XCTAssertEqual(server.calls, ["https://packs.primary.test/v1/packs", "https://packs.fallback.test/v1/packs",
                                      "https://packs.fallback.test/v1/packs/gta-6"])
    }

    func testServerErrorFallsBackClientErrorDoesNot() async {
        server.set("https://packs.primary.test/v1/packs", .status(503))
        server.set("https://packs.fallback.test/v1/packs", .body(Data("list".utf8)))
        let mirrors = PackMirrors(primary: primary, fallbacks: [fallback])
        let list = await get(mirrors, "v1/packs")
        XCTAssertEqual(try? list.get(), Data("list".utf8))

        server.set("https://packs.primary.test/v1/packs/x", .status(429))
        let limited = await get(PackMirrors(primary: primary, fallbacks: [fallback]), "v1/packs/x")
        guard case .failure(.status(429)) = limited else { return XCTFail("\(limited)") }
        XCTAssertFalse(server.calls.contains("https://packs.fallback.test/v1/packs/x"))
    }

    func testBothDownIsNetworkErrorAndFallbackDownCyclesBack() async {
        let mirrors = PackMirrors([primary, fallback, URL(string: "https://packs.primary.test/")!])
        XCTAssertEqual(mirrors.urls.count, 2)
        let down = await get(mirrors, "v1/packs")
        guard case .failure(.network) = down else { return XCTFail("\(down)") }

        server.set("https://packs.fallback.test/v1/packs", .body(Data("b".utf8)))
        _ = await get(mirrors, "v1/packs")
        XCTAssertEqual(mirrors.preferredIndex, 1)
        server.set("https://packs.fallback.test/v1/packs", nil)
        server.set("https://packs.primary.test/v1/packs", .body(Data("a".utf8)))
        let back = await get(mirrors, "v1/packs")
        XCTAssertEqual(try? back.get(), Data("a".utf8))
        XCTAssertEqual(mirrors.preferredIndex, 0)
    }

    func testUpdaterDownloadsThroughFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mirrors-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("pack".utf8)
        let listing = try JSONEncoder().encode(["packs": [RemotePack(id: "gta-6", title: "GTA 6", version: 1,
                                                                     sha256: PackUpdater.sha256(data))]])
        server.set("https://packs.fallback.test/v1/packs", .body(listing))
        server.set("https://packs.fallback.test/v1/packs/gta-6", .body(data))
        let server = self.server
        let updater = PackUpdater(baseURL: primary, fallbackURLs: [fallback], directory: root.appendingPathComponent("packs"),
                                  stateFile: root.appendingPathComponent("state.json"), fetch: { try await server.send($0) })
        let result = await updater.refresh()
        XCTAssertEqual(result.downloaded, ["gta-6"])
        XCTAssertFalse(result.failed)
    }

    func testFallbackAddressComesFromConfiguration() {
        let defaults = TestDefaults.make("packs-fallback")
        let bundle = Bundle(for: Self.self)
        XCTAssertNil(PackUpdater.configuredFallbackURL(environment: [:], defaults: defaults, bundle: bundle))
        XCTAssertNil(PackUpdater.configuredFallbackURL(environment: ["COUCHSUBS_PACKS_FALLBACK_URL": "$(PACKS_API_FALLBACK_URL)"],
                                                       defaults: defaults, bundle: bundle))
        XCTAssertEqual(PackUpdater.configuredFallbackURL(environment: ["COUCHSUBS_PACKS_FALLBACK_URL": "https://b.test"],
                                                         defaults: defaults, bundle: bundle)?.host, "b.test")
        defaults.set("https://from-settings.test", forKey: "packsFallbackURL")
        XCTAssertEqual(PackUpdater.configuredFallbackURL(environment: [:], defaults: defaults, bundle: bundle)?.host, "from-settings.test")
    }
}
