// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
@testable import CouchSubsCore
final class SubtitlePairingTests: XCTestCase {
    func testSharedLifecycleVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appendingPathComponent("subtitle-pairing.json"))
        let scenarios = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        for scenario in scenarios {
            var time: Int64 = 1000
            let pairing = SubtitlePairing(clock: { time })
            var id = ""
            var previous = ""
            let name = scenario["name"] as! String
            for step in scenario["steps"] as! [[String: Any]] {
                let who = step["wrong"] as? Bool == true ? "not-the-request-secret" : step["previous"] as? Bool == true ? previous : id
                switch step["op"] as! String {
                case "session": pairing.setSession(step["value"] as! Bool)
                case "open": pairing.open()
                case "reset": pairing.reset()
                case "advance": time += Int64(step["ms"] as! Int)
                case "begin":
                    let ticket = pairing.begin()
                    XCTAssertEqual(ticket != nil, step["ok"] as! Bool, name)
                    if let ticket { XCTAssertEqual(ticket.id.count, 22); XCTAssertEqual(ticket.code.count, 6); previous = id; id = ticket.id }
                case "resolve": XCTAssertEqual(pairing.resolve(who, accept: step["accept"] as! Bool), step["ok"] as! Bool, name)
                case "poll": XCTAssertEqual(pairing.poll(who), step["state"] as! String, name)
                case "pending": XCTAssertEqual(pairing.pending?.id, step["state"] as! String == "current" ? id : nil, name)
                case "isOpen": XCTAssertEqual(pairing.isOpen, step["value"] as! Bool, name)
                default: XCTFail("Bilinmeyen adım")
                }
            }
        }
    }

    func testWireApprovalAndRotation() async throws {
        let server = SubtitleServer(port: 0, allowLegacy: false)
        let port = try await server.start()
        defer { server.stop() }
        let base = "http://127.0.0.1:\(port)"
        var request = URLRequest(url: URL(string: base + "/pair")!)
        request.httpMethod = "POST"
        let (_, closed) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((closed as? HTTPURLResponse)?.statusCode, 409)
        server.pairing.open()
        request.setValue("https://foreign.example", forHTTPHeaderField: "Origin")
        let (_, denied) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 403)
        request.setValue(nil, forHTTPHeaderField: "Origin")
        let (data, _) = try await URLSession.shared.data(for: request)
        let ticket = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        let id = try XCTUnwrap(ticket["id"])
        let url = URL(string: base + "/pair?id=" + id)!
        let (pending, _) = try await URLSession.shared.data(from: url)
        XCTAssertFalse(String(decoding: pending, as: UTF8.self).contains(server.accessKey))
        XCTAssertTrue(server.pairing.resolve(id, accept: true))
        let (approved, _) = try await URLSession.shared.data(from: url)
        XCTAssertTrue(String(decoding: approved, as: UTF8.self).contains(server.accessKey))
        server.rotateKey(SubtitleAccess.createKey())
        let (expired, _) = try await URLSession.shared.data(from: url)
        XCTAssertFalse(String(decoding: expired, as: UTF8.self).contains(server.accessKey))
        XCTAssertTrue(String(decoding: expired, as: UTF8.self).contains("expired"))
    }

    /// TV'de Tamam ile yeniden deneme ya da TV uygulamasının yeniden açılması: bekleyen isteğin yerini yenisi alır.
    func testNewRequestSupersedesAnUnansweredOne() {
        var time: Int64 = 1000
        let pairing = SubtitlePairing(clock: { time })
        pairing.setSession(true)
        let first = pairing.begin()!
        XCTAssertNil(pairing.begin(), "art arda iki istek: ikincisi reddedilir")
        time += SubtitlePairing.supersedeAfterMs
        let second = pairing.begin()!
        XCTAssertEqual(pairing.pending, second)
        XCTAssertEqual(pairing.poll(first.id), "expired")
        XCTAssertFalse(pairing.resolve(first.id, accept: true))
        XCTAssertTrue(pairing.resolve(second.id, accept: true))
        XCTAssertNil(pairing.pending)
        // Onaylanmış ama TV'nin henüz almadığı istek korunur; TV anahtarı alınca sıra boşalır.
        time += SubtitlePairing.supersedeAfterMs
        XCTAssertNil(pairing.begin())
        XCTAssertEqual(pairing.poll(second.id), "approved")
        XCTAssertNotNil(pairing.begin())
    }

    /// Süresi dolan isteğin on saniyelik beklemesi dolduğu andan sayılır: TV'de iki dakika sonra Tamam'a basılınca
    /// (bekleme çoktan geçmiş) yeni istek hemen kabul edilir.
    func testRetryAfterExpiryIsAcceptedAtOnce() {
        var time: Int64 = 1000
        let pairing = SubtitlePairing(clock: { time })
        pairing.setSession(true)
        XCTAssertNotNil(pairing.begin())
        time += 120_000 + 10_000
        XCTAssertNil(pairing.pending)
        XCTAssertNotNil(pairing.begin())
    }

    private func json(_ method: String, _ url: String) async throws -> (Int, [String: String]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, body)
    }

    /// TestFlight, 21 Kas: TV kod beklerken telefon sunucuyu yeniden açınca (sağlık yoklaması, arka plandan dönüş) istek
    /// siliniyor, TV "Eşleştirme tamamlanmadı" diyordu. Yeniden açılış isteği, onayı ve anahtarı korur.
    func testRestartKeepsPendingRequestAndPairedKey() async throws {
        let probe = SubtitleServer(port: 0)
        let port = try await probe.start()
        probe.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        let server = SubtitleServer(port: port, allowLegacy: false)
        var requests: [SubtitlePairing.Ticket] = []
        let lock = NSLock()
        server.onPairingRequest = { ticket in lock.lock(); requests.append(ticket); lock.unlock() }
        _ = try await server.start()
        defer { server.stop() }
        server.pairing.setSession(true)
        let base = "http://127.0.0.1:\(port)"
        let key = server.accessKey

        let (status, ticket) = try await json("POST", base + "/pair")
        XCTAssertEqual(status, 200)
        let id = try XCTUnwrap(ticket["id"])
        server.stop(keepPairing: true)
        _ = try await server.start()
        // Bekleyen istek yeniden açılıştan sonra da onaylanabilir ve anahtar TV'ye döner.
        XCTAssertEqual(server.pairing.pending?.id, id)
        let (_, pending) = try await json("GET", base + "/pair?id=" + id)
        XCTAssertEqual(pending["state"], "pending")
        XCTAssertTrue(server.pairing.resolve(id, accept: true))
        let (_, approved) = try await json("GET", base + "/pair?id=" + id)
        XCTAssertEqual(approved["state"], "approved")
        XCTAssertEqual(approved["key"], key)

        // Önceden eşleşmiş TV yeniden açılıştan sonra onaysız bağlanır: kayıtlı anahtarı geçerlidir.
        server.stop(keepPairing: true)
        _ = try await server.start()
        let (_, valid) = try await json("GET", base + "/pair?validate=1&k=" + key)
        XCTAssertEqual(valid["state"], "valid")

        // Yeniden açılıştan sonra gelen yeni istek arayüze ulaşır (geri çağrı bağlı kalır) ve onay TV'ye döner.
        let (again, next) = try await json("POST", base + "/pair")
        XCTAssertEqual(again, 200)
        let nextId = try XCTUnwrap(next["id"])
        try await Task.sleep(nanoseconds: 300_000_000)
        lock.lock(); let seen = requests.map(\.id); lock.unlock()
        XCTAssertEqual(seen, [id, nextId])
        XCTAssertTrue(server.pairing.resolve(nextId, accept: true))
        let (_, done) = try await json("GET", base + "/pair?id=" + nextId)
        XCTAssertEqual(done["key"], key)

        // Çeviriyi durdurmak (sıradan stop) eşleştirmeyi kapatır.
        server.stop()
        _ = try await server.start()
        let (closed, _) = try await json("POST", base + "/pair")
        XCTAssertEqual(closed, 409)
    }

    /// Port değişince sunucu yeni örnekle kurulur; eşleştirme durumu ve anahtar yeni örneğe taşınır.
    func testReplacementServerSharesPairingAndKey() async throws {
        let first = SubtitleServer(port: 0, allowLegacy: false)
        let firstPort = try await first.start()
        first.pairing.open()
        let (_, ticket) = try await json("POST", "http://127.0.0.1:\(firstPort)/pair")
        let id = try XCTUnwrap(ticket["id"])
        first.stop(keepPairing: true)
        let second = SubtitleServer(port: 0, key: first.accessKey, allowLegacy: false, pairing: first.pairing)
        let port = try await second.start()
        defer { second.stop() }
        XCTAssertTrue(second.pairing.resolve(id, accept: true))
        let (_, approved) = try await json("GET", "http://127.0.0.1:\(port)/pair?id=" + id)
        XCTAssertEqual(approved["key"], first.accessKey)
    }
}
