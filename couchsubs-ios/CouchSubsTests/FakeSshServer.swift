// SPDX-License-Identifier: AGPL-3.0-only
// SshSession testleri için yerel sahte SSH sunucusu (LG geliştirici modunun dropbear'ı yerine): curve25519-sha256,
// ssh-ed25519, aes128-ctr, hmac-sha2-256. Her girişi kabul eder; tek "exec" kanalının girişini toplar. İstenirse
// bağlantının ortasında anahtarları kendisi yeniden değiştirir (RFC 4253 §9), dropbear'ın süre/veri sınırındaki gibi.

import CryptoKit
import Foundation
@testable import CouchSubs

final class FakeSshServer {
    struct Options {
        /// Girişten hemen sonra (ssh-userauth isteğini beklemeden) yeniden anahtar değişimi.
        var rekeyAfterHandshake = false
        /// Kanala bu kadar bayt geldikten sonra yeniden anahtar değişimi (nil: hiç).
        var rekeyAfterBytes: Int?
        /// Kanalın başlangıç penceresi; küçük olursa istemci okumaya geçer ve KEXINIT'i görür.
        var window: UInt32 = 16 * 1024
    }

    let port: UInt16
    private(set) var received: [UInt8] = []
    private(set) var command = ""
    private(set) var rekeys = 0
    private(set) var error: Error?
    private let options: Options
    private let listener: Int32
    private var fd: Int32 = -1
    private let done = DispatchSemaphore(value: 0)

    private struct Keys {
        var cipher: AesCtr?
        var mac: SshMac?
        var macKey: [UInt8] = []
        var sequence: UInt32 = 0
    }

    private var outgoing = Keys()
    private var incoming = Keys()
    private var buffer: [UInt8] = []
    private var sessionId: [UInt8] = []
    private var clientVersion = ""
    private let serverVersion = "SSH-2.0-dropbear_2019.78"
    private let hostKey = Curve25519.Signing.PrivateKey()

    struct Failure: Error, CustomStringConvertible { let description: String }

    init(_ options: Options = Options()) throws {
        self.options = options
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        self.listener = listener
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(listener, 1) == 0 else { throw Failure(description: "dinlenemedi") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        Thread.detachNewThread { [self] in
            do { try serve() } catch { self.error = error }
            if fd >= 0 { Darwin.close(fd) }
            Darwin.close(listener)
            done.signal()
        }
    }

    /// Sunucu iş parçacığının bitmesini bekler; sunucudaki hatayı döner.
    func finish(timeout: TimeInterval = 20) throws {
        guard done.wait(timeout: .now() + timeout) == .success else { throw Failure(description: "sunucu bitmedi") }
        if let error { throw error }
    }

    // MARK: Akış

    private func serve() throws {
        fd = accept(listener, nil, nil)
        guard fd >= 0 else { throw Failure(description: "bağlantı yok") }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        try write(Array((serverVersion + "\r\n").utf8))
        var line: [UInt8] = []
        while true {
            let byte = try read(1)[0]
            if byte == 0x0A { break }
            if byte != 0x0D { line.append(byte) }
        }
        clientVersion = String(decoding: line, as: UTF8.self)
        try keyExchange()
        if options.rekeyAfterHandshake { try keyExchange() }

        try expect(5)
        var accept = SshWriter()
        accept.byte(6)
        accept.string("ssh-userauth")
        try send(accept.bytes)
        try expect(50)
        try send([52])

        var open = SshReader(try expect(90))
        _ = try open.byte()
        _ = try open.string()
        let channel = try open.uint32()
        var confirm = SshWriter()
        confirm.byte(91)
        confirm.uint32(channel)
        confirm.uint32(0)
        confirm.uint32(options.window)
        confirm.uint32(32_768)
        try send(confirm.bytes)

        var request = SshReader(try expect(98))
        _ = try request.byte()
        _ = try request.uint32()
        guard try request.text() == "exec" else { throw Failure(description: "exec bekleniyordu") }
        let wantReply = try request.bool()
        command = try request.text()
        if wantReply {
            var success = SshWriter()
            success.byte(99)
            success.uint32(channel)
            try send(success.bytes)
        }

        var unacknowledged = 0
        var rekeyed = false
        func adjust() throws {
            guard unacknowledged > 0 else { return }
            var message = SshWriter()
            message.byte(93)
            message.uint32(channel)
            message.uint32(UInt32(unacknowledged))
            try send(message.bytes)
            unacknowledged = 0
        }
        loop: while true {
            let message = try next()
            switch message.first {
            case 94:
                var reader = SshReader(message)
                _ = try reader.byte()
                _ = try reader.uint32()
                let data = try reader.string()
                received += data
                unacknowledged += data.count
                if let limit = options.rekeyAfterBytes, !rekeyed, received.count >= limit {
                    rekeyed = true
                    try keyExchange()
                }
                if unacknowledged >= Int(options.window) / 2 { try adjust() }
            case 96:
                break loop
            default:
                throw Failure(description: "kanalda beklenmeyen ileti \(message.first ?? 0)")
            }
        }

        var output = SshWriter()
        output.byte(94)
        output.uint32(channel)
        output.string("ok")
        try send(output.bytes)
        var status = SshWriter()
        status.byte(98)
        status.uint32(channel)
        status.string("exit-status")
        status.bool(false)
        status.uint32(0)
        try send(status.bytes)
        var eof = SshWriter()
        eof.byte(96)
        eof.uint32(channel)
        try send(eof.bytes)
        var close = SshWriter()
        close.byte(97)
        close.uint32(channel)
        try send(close.bytes)
        try expect(97)
    }

    /// KEXINIT gönderildikten sonra istemciden gelen, değişime ait olmayan iletiler (§9: geçerlidir, sonra işlenir).
    private var pending: [[UInt8]] = []

    private func next() throws -> [UInt8] {
        pending.isEmpty ? try receive() : pending.removeFirst()
    }

    @discardableResult
    private func expect(_ type: UInt8) throws -> [UInt8] {
        let message = try next()
        guard message.first == type else { throw Failure(description: "\(type) beklenirken \(message.first ?? 0)") }
        return message
    }

    // MARK: Anahtar değişimi (sunucu tarafı)

    @discardableResult
    private func expectKex(_ type: UInt8) throws -> [UInt8] {
        let message = try receive()
        guard message.first == type else { throw Failure(description: "değişimde \(type) beklenirken \(message.first ?? 0)") }
        return message
    }

    private func keyExchange() throws {
        var kexInit = SshWriter()
        kexInit.byte(20)
        kexInit.bytes += [UInt8](repeating: 7, count: 16)
        kexInit.nameList(["curve25519-sha256", "curve25519-sha256@libssh.org"])
        kexInit.nameList(["ssh-ed25519"])
        kexInit.nameList(["aes128-ctr"])
        kexInit.nameList(["aes128-ctr"])
        kexInit.nameList(["hmac-sha2-256"])
        kexInit.nameList(["hmac-sha2-256"])
        kexInit.nameList(["none"])
        kexInit.nameList(["none"])
        kexInit.nameList([])
        kexInit.nameList([])
        kexInit.bool(false)
        kexInit.uint32(0)
        let serverInit = kexInit.bytes
        try send(serverInit)

        var clientInit: [UInt8] = []
        while clientInit.isEmpty {
            let message = try receive()
            switch message.first {
            case 20:
                clientInit = message
            case let type? where !(20...49).contains(type):
                pending.append(message)
            default:
                throw Failure(description: "KEXINIT beklenirken \(message.first ?? 0)")
            }
        }
        var initReader = SshReader(try expectKex(30))
        _ = try initReader.byte()
        let clientPublic = try initReader.string()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let serverPublic = Array(ephemeral.publicKey.rawRepresentation)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPublic))
            .withUnsafeBytes { Array($0) }

        var hostBlob = SshWriter()
        hostBlob.string("ssh-ed25519")
        hostBlob.string(Array(hostKey.publicKey.rawRepresentation))
        var exchange = SshWriter()
        exchange.string(clientVersion)
        exchange.string(serverVersion)
        exchange.string(clientInit)
        exchange.string(serverInit)
        exchange.string(hostBlob.bytes)
        exchange.string(clientPublic)
        exchange.string(serverPublic)
        exchange.mpint(shared)
        let hash = Array(SHA256.hash(data: exchange.bytes))
        if sessionId.isEmpty { sessionId = hash }

        var signature = SshWriter()
        signature.string("ssh-ed25519")
        signature.string(Array(try hostKey.signature(for: hash)))
        var reply = SshWriter()
        reply.byte(31)
        reply.string(hostBlob.bytes)
        reply.string(serverPublic)
        reply.string(signature.bytes)
        try send(reply.bytes)

        var sharedMpint = SshWriter()
        sharedMpint.mpint(shared)
        func derive(_ letter: Character, _ length: Int) -> [UInt8] {
            var key = Array(SHA256.hash(data: sharedMpint.bytes + hash + [letter.asciiValue!] + sessionId))
            while key.count < length { key += Array(SHA256.hash(data: sharedMpint.bytes + hash + key)) }
            return Array(key.prefix(length))
        }
        let mac = SshMac(name: "hmac-sha2-256")
        try send([21])
        outgoing.cipher = try AesCtr(key: derive("D", 16), iv: derive("B", 16))
        outgoing.mac = mac
        outgoing.macKey = derive("F", 32)
        try expectKex(21)
        incoming.cipher = try AesCtr(key: derive("C", 16), iv: derive("A", 16))
        incoming.mac = mac
        incoming.macKey = derive("E", 32)
        rekeys += 1
    }

    // MARK: Paketler (yalnız şifrele-sonra-değil MAC: hmac-sha2-256)

    private func send(_ payload: [UInt8]) throws {
        let block = outgoing.cipher == nil ? 8 : 16
        var padding = block - (5 + payload.count) % block
        if padding < 4 { padding += block }
        var header = SshWriter()
        header.uint32(UInt32(1 + payload.count + padding))
        let plain = header.bytes + [UInt8(padding)] + payload + [UInt8](repeating: 0, count: padding)
        var wire = outgoing.cipher?.apply(plain) ?? plain
        if let mac = outgoing.mac {
            var sequence = SshWriter()
            sequence.uint32(outgoing.sequence)
            wire += mac.compute(key: outgoing.macKey, sequence.bytes + plain)
        }
        outgoing.sequence &+= 1
        try write(wire)
    }

    private func receive() throws -> [UInt8] {
        let block = incoming.cipher == nil ? 8 : 16
        let first = try read(block)
        var plain = incoming.cipher?.apply(first) ?? first
        var lengthReader = SshReader(plain)
        let length = Int(try lengthReader.uint32())
        guard length >= 5, length < 512 * 1024 else { throw Failure(description: "bozuk uzunluk \(length)") }
        let rest = try read(4 + length - block)
        plain += incoming.cipher?.apply(rest) ?? rest
        if let mac = incoming.mac {
            var sequence = SshWriter()
            sequence.uint32(incoming.sequence)
            guard try read(mac.length) == mac.compute(key: incoming.macKey, sequence.bytes + plain) else { throw Failure(description: "MAC tutmadı") }
        }
        incoming.sequence &+= 1
        let padding = Int(plain[4])
        return Array(plain[5..<(plain.count - padding)])
    }

    private func read(_ count: Int) throws -> [UInt8] {
        while buffer.count < count {
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let got = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            guard got > 0 else { throw Failure(description: "istemci bağlantıyı kapattı") }
            buffer += chunk.prefix(got)
        }
        let result = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    private func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress! + offset, bytes.count - offset, 0) }
            guard sent > 0 else { throw Failure(description: "yazılamadı") }
            offset += sent
        }
    }
}
