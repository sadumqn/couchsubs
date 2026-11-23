// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import CouchSubs

/// DeepL yerine geçen sahte sunucu: istek gövdelerini saklar, her cümleyi "[tr] cümle" diye çevirir.
private final class FakeDeepL: URLProtocol {
    nonisolated(unsafe) static var bodies: [[String: Any]] = []
    nonisolated(unsafe) static var failing = false
    /// Verilirse bu durum koduyla yanıt verir.
    nonisolated(unsafe) static var status: Int?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        Self.bodies.append(body)
        let status = Self.status ?? (Self.failing ? 502 : 200)
        let texts = body["text"] as? [String] ?? []
        let reply = try! JSONSerialization.data(withJSONObject: ["translations": texts.map { ["text": "[tr] " + $0] }])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeDeepL.self]
        return URLSession(configuration: configuration)
    }
}

/// İndirilmemiş ya da açılamayan yerel çeviri.
private final class NoLocal: TextTranslator {
    struct Missing: Error {}
    func translate(_ text: String) async throws -> String { throw Missing() }
}

private final class FakeLocal: TextTranslator {
    private(set) var warmUpCalls = 0

    func warmUp() async { warmUpCalls += 1 }
    func translate(_ text: String) async throws -> String { "yerel: " + text }
}

/// Windows'taki DeepLTranslatorTests ile aynı durumlar.
final class DeepLTranslatorTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        FakeDeepL.bodies = []
        FakeDeepL.failing = false
        FakeDeepL.status = nil
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-deepl-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func make(_ cache: TranslationCache = TranslationCache()) -> DeepLTranslator {
        DeepLTranslator(key: "abc:fx", fallback: FakeLocal(), session: FakeDeepL.session(), cache: cache)
    }

    private func context(_ index: Int) -> String? { FakeDeepL.bodies[index]["context"] as? String }

    func testWarmUpDoesNotSendPlaceholderOrSeedFirstRequestContext() async throws {
        let fallback = FakeLocal()
        let translator = DeepLTranslator(key: "abc:fx", fallback: fallback, session: FakeDeepL.session())

        await translator.warmUp()
        XCTAssertEqual(FakeDeepL.bodies.count, 0)
        XCTAssertEqual(fallback.warmUpCalls, 1)

        _ = try await translator.translate("First real subtitle.")

        XCTAssertEqual(FakeDeepL.bodies.count, 1)
        XCTAssertNil(context(0))
        XCTAssertEqual(FakeDeepL.bodies[0]["text"] as? [String], ["First real subtitle."])
    }

    func testContextIsTheLastThreeShownLines() async throws {
        let translator = make()
        for line in ["One.", "Two.", "Two.", "Three.", "Four.", "Five."] { _ = try await translator.translate(line) }
        XCTAssertEqual(FakeDeepL.bodies.count, 5)
        XCTAssertNil(context(0))
        XCTAssertEqual(context(1), "One.")
        XCTAssertEqual(context(2), "One.\nTwo.")
        XCTAssertEqual(context(4), "Two.\nThree.\nFour.")
    }

    func testCachedLinesCountAsContext() async throws {
        let translator = make()
        for line in ["Where is he?", "Upstairs.", "Where is he?", "Go get him."] { _ = try await translator.translate(line) }
        XCTAssertEqual(FakeDeepL.bodies.count, 3)
        XCTAssertEqual(context(2), "Where is he?\nUpstairs.\nWhere is he?")
    }

    func testPersistentCacheSavesQuotaAcrossSessions() async throws {
        let file = directory.appendingPathComponent("cache.jsonl")
        _ = try await make(TranslationCache(file: file)).translate("KRATOS: We go now. Stay close.")
        FakeDeepL.bodies = []

        let translator = make(TranslationCache(file: file))
        let again = try await translator.translate("KRATOS: We go now. Stay close.")
        XCTAssertEqual(again, "KRATOS: [tr] We go now. [tr] Stay close.")
        XCTAssertTrue(FakeDeepL.bodies.isEmpty)
        let mixed = try await translator.translate("Stay close. Run!")
        XCTAssertEqual(mixed, "[tr] Stay close. [tr] Run!")
        XCTAssertEqual(FakeDeepL.bodies.count, 1)
        XCTAssertEqual(FakeDeepL.bodies[0]["text"] as? [String], ["Run!"])
        XCTAssertEqual(translator.spokenLines(for: "KRATOS: We go now. Stay close.")[1].speaker, "KRATOS")
    }

    func testFallbackResultsAreNotCachedAsDeepL() async throws {
        FakeDeepL.failing = true
        let cache = TranslationCache()
        let failed = try await make(cache).translate("Run!")
        XCTAssertEqual(failed, "yerel: Run!")
        XCTAssertNil(cache.value(for: "Run!"))

        FakeDeepL.failing = false
        let fresh = try await make(cache).translate("Run!")
        XCTAssertEqual(fresh, "[tr] Run!")
    }

    /// Yerel çeviri yokken tek bir hata DeepL'i bir dakika durduruyor, bu sürede gelen her satır düşüyordu. DeepL yine
    /// denenmeli (Windows ve Android ile aynı).
    func testErrorPauseWithoutLocalStillTriesDeepL() async throws {
        let translator = DeepLTranslator(key: "abc:fx", fallback: NoLocal(), session: FakeDeepL.session())
        FakeDeepL.status = 503
        do { _ = try await translator.translate("Run!"); XCTFail("hata beklenirdi") } catch {}
        FakeDeepL.status = nil
        let second = try await translator.translate("Hide!")
        XCTAssertEqual(second, "[tr] Hide!")
        XCTAssertEqual(FakeDeepL.bodies.count, 2)
    }

    /// DeepL 429 (çok sık istek) sonrası bekleme yerel çeviri olmasa da korunur.
    func testTooManyRequestsPauseHoldsWithoutLocal() async throws {
        let translator = DeepLTranslator(key: "abc:fx", fallback: NoLocal(), session: FakeDeepL.session())
        FakeDeepL.status = 429
        do { _ = try await translator.translate("Run!"); XCTFail("hata beklenirdi") } catch {}
        do { _ = try await translator.translate("Hide!"); XCTFail("hata beklenirdi") } catch {}
        XCTAssertEqual(FakeDeepL.bodies.count, 1)
    }
}
