// SPDX-License-Identifier: AGPL-3.0-only
// #483: iPhone'dan LG kurulumu "TV anahtarları yeniden değiştirmek istedi (desteklenmiyor)" hatasıyla duruyordu. SSH
// istemcisi sunucunun ilk KEXINIT'ini de yeniden değişim sanıyordu; bağlantı ortasındaki gerçek yeniden değişimi
// (RFC 4253 §9) de desteklemiyordu.

import XCTest
@testable import CouchSubs

final class SshRekeyTests: XCTestCase {
    private func upload(_ options: FakeSshServer.Options, size: Int) throws -> (FakeSshServer, SshSession.ExecResult, [UInt8]) {
        let server = try FakeSshServer(options)
        let input = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let session = try SshSession.connect(host: "127.0.0.1", port: server.port, user: "prisoner", key: try RsaKey.generate(), timeout: 5)
        let result = try session.exec("cat > '/media/developer/temp/couchsubs.ipk'", input: input, timeout: 20)
        session.close()
        try server.finish()
        return (server, result, input)
    }

    func testConnectsAndUploadsWithoutRekey() throws {
        let (server, result, input) = try upload(FakeSshServer.Options(), size: 100_000)
        XCTAssertEqual(server.rekeys, 1)
        XCTAssertEqual(server.command, "cat > '/media/developer/temp/couchsubs.ipk'")
        XCTAssertEqual(server.received, input)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "ok")
    }

    func testServerRekeyRightAfterHandshake() throws {
        var options = FakeSshServer.Options()
        options.rekeyAfterHandshake = true
        let (server, result, input) = try upload(options, size: 10_000)
        XCTAssertEqual(server.rekeys, 2)
        XCTAssertEqual(server.received, input)
        XCTAssertEqual(result.status, 0)
    }

    func testServerRekeyInTheMiddleOfUpload() throws {
        var options = FakeSshServer.Options()
        options.rekeyAfterBytes = 8 * 1024
        let (server, result, input) = try upload(options, size: 300_000)
        XCTAssertEqual(server.rekeys, 2)
        XCTAssertEqual(server.received, input)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "ok")
    }
}
