// SPDX-License-Identifier: AGPL-3.0-only
// LG geliştirici modunun SSH'si (9922) için en küçük SSH-2 istemcisi (RFC 4253, 4252, 4254): Android'deki jsch'in
// (mwiede/jsch 0.2.x, JschShell.kt) LG TV'lerle anlaştığı algoritmalar, yalnız tek "exec" kanalı. Anahtar değişimi,
// imzalar ve şifreler CryptoKit, Security ve CommonCrypto ile; dış kütüphane yok.
//
// Algoritmalar jsch'in varsayılan sırasıyla, Android'de LG için açılan eskiler sonda:
//   anahtar değişimi: curve25519-sha256(@libssh.org), ecdh-sha2-nistp256/384/521, diffie-hellman-group14-sha256,
//                     diffie-hellman-group14-sha1, diffie-hellman-group1-sha1
//   TV anahtarı: ssh-ed25519, ecdsa-sha2-nistp256/384/521, rsa-sha2-512, rsa-sha2-256, ssh-rsa
//   şifre: aes128-ctr, aes192-ctr, aes256-ctr
//   bütünlük: hmac-sha2-256-etm, hmac-sha2-512-etm, hmac-sha1-etm (@openssh.com), hmac-sha2-256, hmac-sha2-512, hmac-sha1
//   kimlik: RSA anahtarı; rsa-sha2-512, rsa-sha2-256, ssh-rsa
// TV'nin anahtarı denetlenmez (jsch'teki StrictHostKeyChecking=no); imzası yine doğrulanır.

import CommonCrypto
import CryptoKit
import Foundation
import Security

struct SshError: Error, CustomStringConvertible {
    enum Kind { case connect, auth, broken }
    let kind: Kind
    let description: String
    init(_ kind: Kind, _ description: String) {
        self.kind = kind
        self.description = description
    }
}

// MARK: - Kodlama

struct SshWriter {
    var bytes: [UInt8] = []

    mutating func byte(_ value: UInt8) { bytes.append(value) }
    mutating func bool(_ value: Bool) { bytes.append(value ? 1 : 0) }
    mutating func uint32(_ value: UInt32) { bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    mutating func string(_ value: [UInt8]) {
        uint32(UInt32(value.count))
        bytes += value
    }
    mutating func string(_ value: String) { string(Array(value.utf8)) }
    mutating func nameList(_ names: [String]) { string(names.joined(separator: ",")) }

    /// İşaretsiz büyük-endian sayıyı mpint olarak yazar.
    mutating func mpint(_ magnitude: [UInt8]) {
        var value = Array(magnitude.drop { $0 == 0 })
        if let first = value.first, first & 0x80 != 0 { value.insert(0, at: 0) }
        string(value)
    }
}

struct SshReader {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { offset >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw SshError(.broken, "kısa ileti") }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func bool() throws -> Bool { try byte() != 0 }

    mutating func uint32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw SshError(.broken, "kısa ileti") }
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    mutating func string() throws -> [UInt8] {
        let count = Int(try uint32())
        guard offset + count <= bytes.count else { throw SshError(.broken, "kısa ileti") }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func text() throws -> String { String(decoding: try string(), as: UTF8.self) }
    mutating func nameList() throws -> [String] { try text().split(separator: ",").map(String.init) }

    /// mpint'in işaretsiz büyüklüğü (baştaki sıfırlar atılmış).
    mutating func mpint() throws -> [UInt8] { Array(try string().drop { $0 == 0 }) }
}

private func randomBytes(_ count: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    return bytes
}

// MARK: - Algoritmalar

private enum SshHash {
    case sha1, sha256, sha384, sha512

    func digest(_ data: [UInt8]) -> [UInt8] {
        switch self {
        case .sha1: Array(Insecure.SHA1.hash(data: data))
        case .sha256: Array(SHA256.hash(data: data))
        case .sha384: Array(SHA384.hash(data: data))
        case .sha512: Array(SHA512.hash(data: data))
        }
    }
}

private enum SshKex: String, CaseIterable {
    case curve25519 = "curve25519-sha256"
    case curve25519Libssh = "curve25519-sha256@libssh.org"
    case nistp256 = "ecdh-sha2-nistp256"
    case nistp384 = "ecdh-sha2-nistp384"
    case nistp521 = "ecdh-sha2-nistp521"
    case group14sha256 = "diffie-hellman-group14-sha256"
    case group14sha1 = "diffie-hellman-group14-sha1"
    case group1sha1 = "diffie-hellman-group1-sha1"

    var hash: SshHash {
        switch self {
        case .curve25519, .curve25519Libssh, .nistp256, .group14sha256: .sha256
        case .nistp384: .sha384
        case .nistp521: .sha512
        case .group14sha1, .group1sha1: .sha1
        }
    }
}

private let hostKeyAlgorithms = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
                                 "rsa-sha2-512", "rsa-sha2-256", "ssh-rsa"]
private let cipherAlgorithms = ["aes128-ctr", "aes192-ctr", "aes256-ctr"]
private let macAlgorithms = ["hmac-sha2-256-etm@openssh.com", "hmac-sha2-512-etm@openssh.com", "hmac-sha1-etm@openssh.com",
                             "hmac-sha2-256", "hmac-sha2-512", "hmac-sha1"]

struct SshMac {
    let name: String
    var etm: Bool { name.hasSuffix("-etm@openssh.com") }
    var length: Int { name.hasPrefix("hmac-sha2-512") ? 64 : name.hasPrefix("hmac-sha2-256") ? 32 : 20 }

    func compute(key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        let symmetric = SymmetricKey(data: key)
        if name.hasPrefix("hmac-sha2-512") { return Array(HMAC<SHA512>.authenticationCode(for: data, using: symmetric)) }
        if name.hasPrefix("hmac-sha2-256") { return Array(HMAC<SHA256>.authenticationCode(for: data, using: symmetric)) }
        return Array(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetric))
    }
}

/// AES-CTR akışı (CommonCrypto); şifreleme ve çözme aynı işlemdir.
final class AesCtr {
    private var cryptor: CCCryptorRef?

    init(key: [UInt8], iv: [UInt8]) throws {
        let status = CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                                             iv, key, key.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
        guard status == kCCSuccess else { throw SshError(.broken, "AES-CTR açılamadı (\(status))") }
    }

    deinit { if let cryptor { CCCryptorRelease(cryptor) } }

    func apply(_ data: [UInt8]) -> [UInt8] {
        guard !data.isEmpty else { return [] }
        var output = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        _ = CCCryptorUpdate(cryptor, data, data.count, &output, output.count, &moved)
        return output
    }
}

private struct Direction {
    var cipher: AesCtr?
    var mac: SshMac?
    var macKey: [UInt8] = []
    var sequence: UInt32 = 0
    var blockSize: Int { cipher == nil ? 8 : 16 }
}

// MARK: - Diffie-Hellman (Montgomery çarpımıyla üs alma)

private enum ModpGroup {
    static let group14 = BigUInt(hex: "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF")
    static let group1 = BigUInt(hex: "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381FFFFFFFFFFFFFFFF")
}

/// base^exponent mod modulus (modulus tek sayı). BigUInt'in bit bit kalanı 2048 bitte çok yavaş olduğu için.
func montgomeryPower(_ base: BigUInt, _ exponent: BigUInt, modulus: BigUInt) -> BigUInt {
    let n = modulus.limbs
    let size = n.count
    func padded(_ value: BigUInt) -> [UInt32] { value.limbs + [UInt32](repeating: 0, count: max(0, size - value.limbs.count)) }
    var inverse: UInt32 = 1
    for _ in 0..<5 { inverse = inverse &* (2 &- n[0] &* inverse) }
    let nPrime = 0 &- inverse

    func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var t = [UInt32](repeating: 0, count: size + 2)
        for i in 0..<size {
            var carry: UInt64 = 0
            let bi = UInt64(b[i])
            for j in 0..<size {
                let value = UInt64(t[j]) + UInt64(a[j]) * bi + carry
                t[j] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            var value = UInt64(t[size]) + carry
            t[size] = UInt32(truncatingIfNeeded: value)
            t[size + 1] = UInt32(value >> 32)
            let m = UInt64(t[0] &* nPrime)
            value = UInt64(t[0]) + m * UInt64(n[0])
            carry = value >> 32
            for j in 1..<size {
                value = UInt64(t[j]) + m * UInt64(n[j]) + carry
                t[j - 1] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            value = UInt64(t[size]) + carry
            t[size - 1] = UInt32(truncatingIfNeeded: value)
            t[size] = t[size + 1] &+ UInt32(value >> 32)
        }
        let result = BigUInt(limbs: Array(t.prefix(size + 1)))
        return padded(result >= modulus ? result - modulus : result)
    }

    let r2 = padded((BigUInt(1) << (64 * size)) % modulus)
    var accumulator = multiply(padded(BigUInt(1)), r2)
    let montBase = multiply(padded(base % modulus), r2)
    for index in stride(from: exponent.bitWidth - 1, through: 0, by: -1) {
        accumulator = multiply(accumulator, accumulator)
        if exponent.bit(index) { accumulator = multiply(accumulator, montBase) }
    }
    var one = [UInt32](repeating: 0, count: size)
    one[0] = 1
    return BigUInt(limbs: multiply(accumulator, one))
}

// MARK: - Oturum

/// Tek bağlantı: anahtar değişimi, RSA anahtarıyla giriş, sonra `exec`. Bloklayan; arka plan iş parçacığında çalışır.
final class SshSession {
    static let clientVersion = "SSH-2.0-CouchSubs_1.0"

    private let socket: PosixSocket
    private let reader: StreamReader
    private var outgoing = Direction()
    private var incoming = Direction()
    private var sessionId: [UInt8] = []
    private var serverSigAlgs: [String]?
    private(set) var serverVersion = ""

    private init(socket: PosixSocket) {
        self.socket = socket
        reader = StreamReader(socket)
    }

    deinit { socket.close() }

    /// Bağlanır, anahtar değiştirir ve `user` olarak `key` ile giriş yapar.
    static func connect(host: String, port: UInt16, user: String, key: RsaKey, timeout: TimeInterval) throws -> SshSession {
        let socket: PosixSocket
        do {
            socket = try PosixSocket.connect(host: host, port: port, timeout: timeout)
        } catch {
            throw SshError(.connect, "\(error)")
        }
        socket.readTimeout = max(timeout, 10)
        let session = SshSession(socket: socket)
        do {
            try session.handshake()
        } catch let error as SshError {
            socket.close()
            throw error.kind == .auth ? error : SshError(.connect, error.description)
        } catch {
            socket.close()
            throw SshError(.connect, "\(error)")
        }
        do {
            try session.authenticate(user: user, key: key)
        } catch let error as SshError {
            socket.close()
            throw error
        } catch {
            socket.close()
            throw SshError(.connect, "\(error)")
        }
        return session
    }

    func close() {
        var message = SshWriter()
        message.byte(1)
        message.uint32(11) // SSH_DISCONNECT_BY_APPLICATION
        message.string("")
        message.string("")
        try? sendPacket(message.bytes)
        socket.close()
    }

    // MARK: Paketler

    private func sendPacket(_ payload: [UInt8]) throws {
        let block = outgoing.blockSize
        let etm = outgoing.mac?.etm == true
        let base = (etm ? 1 : 5) + payload.count
        var padding = block - base % block
        if padding < 4 { padding += block }
        let length = UInt32(1 + payload.count + padding)
        var header = SshWriter()
        header.uint32(length)
        let body = [UInt8(padding)] + payload + randomBytes(padding)
        var wire: [UInt8]
        var sequence = SshWriter()
        sequence.uint32(outgoing.sequence)
        if etm, let mac = outgoing.mac {
            wire = header.bytes + (outgoing.cipher?.apply(body) ?? body)
            wire += mac.compute(key: outgoing.macKey, sequence.bytes + wire)
        } else {
            let plain = header.bytes + body
            wire = outgoing.cipher?.apply(plain) ?? plain
            if let mac = outgoing.mac { wire += mac.compute(key: outgoing.macKey, sequence.bytes + plain) }
        }
        outgoing.sequence &+= 1
        try socket.write(wire)
    }

    private func readPacket() throws -> [UInt8] {
        var sequence = SshWriter()
        sequence.uint32(incoming.sequence)
        let plain: [UInt8]
        if let mac = incoming.mac, mac.etm {
            let lengthBytes = try reader.readExactly(4)
            let length = Int(try SshReader(lengthBytes).uint32Value())
            guard length >= 5, length < 512 * 1024 else { throw SshError(.broken, "bozuk paket uzunluğu \(length)") }
            let body = try reader.readExactly(length)
            let received = try reader.readExactly(mac.length)
            guard mac.compute(key: incoming.macKey, sequence.bytes + lengthBytes + body) == received else { throw SshError(.broken, "MAC tutmadı") }
            plain = lengthBytes + (incoming.cipher?.apply(body) ?? body)
        } else {
            let block = incoming.blockSize
            let first = try reader.readExactly(block)
            var decrypted = incoming.cipher?.apply(first) ?? first
            let length = Int(try SshReader(decrypted).uint32Value())
            guard length >= 5, length < 512 * 1024, (4 + length) >= block else { throw SshError(.broken, "bozuk paket uzunluğu \(length)") }
            let rest = try reader.readExactly(4 + length - block)
            decrypted += incoming.cipher?.apply(rest) ?? rest
            if let mac = incoming.mac {
                let received = try reader.readExactly(mac.length)
                guard mac.compute(key: incoming.macKey, sequence.bytes + decrypted) == received else { throw SshError(.broken, "MAC tutmadı") }
            }
            plain = decrypted
        }
        incoming.sequence &+= 1
        let padding = Int(plain[4])
        guard 5 + padding <= plain.count else { throw SshError(.broken, "bozuk dolgu") }
        return Array(plain[5..<(plain.count - padding)])
    }

    /// Bağlantının genel iletilerini (yoksay, hata ayıklama, karşılama, ext-info, genel istek) karşılar; kalanı döner.
    private func nextMessage() throws -> [UInt8] {
        while true {
            let payload = try readPacket()
            guard let type = payload.first else { continue }
            switch type {
            case 1:
                var reader = SshReader(payload)
                _ = try reader.byte()
                _ = try reader.uint32()
                throw SshError(.broken, "TV bağlantıyı kapattı: \((try? reader.text()) ?? "")")
            case 2, 3, 4, 53:
                continue
            case 7:
                var reader = SshReader(payload)
                _ = try reader.byte()
                let count = try reader.uint32()
                for _ in 0..<count {
                    let name = try reader.text()
                    let value = try reader.text()
                    if name == "server-sig-algs" { serverSigAlgs = value.split(separator: ",").map(String.init) }
                }
            case 80:
                var reader = SshReader(payload)
                _ = try reader.byte()
                _ = try reader.string()
                if try reader.bool() { try sendPacket([82]) }
            case 20:
                // TV bağlantı sırasında anahtarları yeniden değiştirmek isteyebilir (RFC 4253 §9; dropbear ve OpenSSH
                // süre ya da veri sınırında kendiliğinden başlatır). Değişim bitince akış kaldığı yerden sürer.
                try keyExchange(serverInit: payload)
            default:
                return payload
            }
        }
    }

    // MARK: Anahtar değişimi

    private func handshake() throws {
        try socket.write(Array((Self.clientVersion + "\r\n").utf8))
        // Sunucu sürüm satırından önce başka satırlar da yollayabilir.
        var line: [UInt8] = []
        for _ in 0..<64 {
            line = []
            while true {
                let byte = try reader.readExactly(1)[0]
                if byte == 0x0A { break }
                line.append(byte)
                if line.count > 1024 { throw SshError(.broken, "sürüm satırı çok uzun") }
            }
            if line.last == 0x0D { line.removeLast() }
            if line.starts(with: Array("SSH-".utf8)) { break }
        }
        serverVersion = String(decoding: line, as: UTF8.self)
        guard serverVersion.hasPrefix("SSH-2.0-") || serverVersion.hasPrefix("SSH-1.99-") else {
            throw SshError(.broken, "SSH sürümü desteklenmiyor: \(serverVersion)")
        }
        try keyExchange(serverInit: nil)
    }

    /// Anahtar değişimi (RFC 4253 §7-8). `serverInit` verilirse TV başlatmıştır (yeniden değişim, §9): KEXINIT'i zaten
    /// okunmuştur. Oturum kimliği ilk değişimin özeti olarak kalır; paket sıra numaraları sıfırlanmaz.
    private func keyExchange(serverInit received: [UInt8]?) throws {
        let first = sessionId.isEmpty
        var kexInit = SshWriter()
        kexInit.byte(20)
        kexInit.bytes += randomBytes(16)
        // ext-info-c yalnız ilk KEXINIT'te yazılır (RFC 8308 §2.1).
        kexInit.nameList(SshKex.allCases.map(\.rawValue) + (first ? ["ext-info-c"] : []))
        kexInit.nameList(hostKeyAlgorithms)
        kexInit.nameList(cipherAlgorithms)
        kexInit.nameList(cipherAlgorithms)
        kexInit.nameList(macAlgorithms)
        kexInit.nameList(macAlgorithms)
        kexInit.nameList(["none"])
        kexInit.nameList(["none"])
        kexInit.nameList([])
        kexInit.nameList([])
        kexInit.bool(false)
        kexInit.uint32(0)
        let clientInit = kexInit.bytes
        try sendPacket(clientInit)

        // Sunucunun ilk KEXINIT'i de anahtar değişimi iletisidir; genel ileti döngüsünden (nextMessage) okunmaz, yoksa
        // yeniden değişim sanılır (#483).
        let serverInit = try received ?? kexMessage()
        guard serverInit.first == 20 else { throw SshError(.broken, "KEXINIT beklenirken \(serverInit.first ?? 0)") }
        var parse = SshReader(serverInit)
        _ = try parse.byte()
        _ = try parse.bytesSkip(16)
        let serverKex = try parse.nameList()
        let serverHostKeys = try parse.nameList()
        let serverCipherOut = try parse.nameList()
        let serverCipherIn = try parse.nameList()
        let serverMacOut = try parse.nameList()
        let serverMacIn = try parse.nameList()
        let serverCompressionOut = try parse.nameList()
        let serverCompressionIn = try parse.nameList()
        _ = try parse.nameList()
        _ = try parse.nameList()
        let guessFollows = try parse.bool()

        func pick(_ client: [String], _ server: [String], _ what: String) throws -> String {
            guard let found = client.first(where: server.contains) else {
                throw SshError(.broken, "ortak \(what) yok (TV: \(server.joined(separator: ",")))")
            }
            return found
        }
        guard let kex = SshKex(rawValue: try pick(SshKex.allCases.map(\.rawValue), serverKex, "anahtar değişimi")) else {
            throw SshError(.broken, "anahtar değişimi")
        }
        _ = try pick(hostKeyAlgorithms, serverHostKeys, "TV anahtarı türü")
        let cipherOut = try pick(cipherAlgorithms, serverCipherOut, "şifre")
        let cipherIn = try pick(cipherAlgorithms, serverCipherIn, "şifre")
        let macOut = try pick(macAlgorithms, serverMacOut, "MAC")
        let macIn = try pick(macAlgorithms, serverMacIn, "MAC")
        guard serverCompressionOut.contains("none"), serverCompressionIn.contains("none") else { throw SshError(.broken, "sıkıştırmasız bağlantı yok") }
        if guessFollows, serverKex.first != kex.rawValue { _ = try kexMessage() } // Yanlış tahminin paketi atılır.

        // Anahtar değişimi.
        var exchange = SshWriter()
        exchange.string(Self.clientVersion)
        exchange.string(serverVersion)
        exchange.string(clientInit)
        exchange.string(serverInit)
        let hostKey: [UInt8]
        let signature: [UInt8]
        let shared: [UInt8]
        switch kex {
        case .curve25519, .curve25519Libssh, .nistp256, .nistp384, .nistp521:
            let clientPublic: [UInt8]
            let agree: ([UInt8]) throws -> [UInt8]
            switch kex {
            case .nistp256:
                let key = P256.KeyAgreement.PrivateKey()
                clientPublic = Array(key.publicKey.x963Representation)
                agree = { try Self.secret(key.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: $0))) }
            case .nistp384:
                let key = P384.KeyAgreement.PrivateKey()
                clientPublic = Array(key.publicKey.x963Representation)
                agree = { try Self.secret(key.sharedSecretFromKeyAgreement(with: P384.KeyAgreement.PublicKey(x963Representation: $0))) }
            case .nistp521:
                let key = P521.KeyAgreement.PrivateKey()
                clientPublic = Array(key.publicKey.x963Representation)
                agree = { try Self.secret(key.sharedSecretFromKeyAgreement(with: P521.KeyAgreement.PublicKey(x963Representation: $0))) }
            default:
                let key = Curve25519.KeyAgreement.PrivateKey()
                clientPublic = Array(key.publicKey.rawRepresentation)
                agree = { try Self.secret(key.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0))) }
            }
            var initMessage = SshWriter()
            initMessage.byte(30)
            initMessage.string(clientPublic)
            try sendPacket(initMessage.bytes)
            let reply = try kexMessage()
            guard reply.first == 31 else { throw SshError(.broken, "KEX yanıtı beklenirken \(reply.first ?? 0)") }
            var reader = SshReader(reply)
            _ = try reader.byte()
            hostKey = try reader.string()
            let serverPublic = try reader.string()
            signature = try reader.string()
            do {
                shared = try agree(serverPublic)
            } catch {
                throw SshError(.broken, "TV'nin açık anahtarı geçersiz")
            }
            if kex == .curve25519 || kex == .curve25519Libssh, shared.allSatisfy({ $0 == 0 }) { throw SshError(.broken, "geçersiz ortak sır") }
            exchange.string(hostKey)
            exchange.string(clientPublic)
            exchange.string(serverPublic)
        case .group14sha256, .group14sha1, .group1sha1:
            let prime = kex == .group1sha1 ? ModpGroup.group1 : ModpGroup.group14
            let byteCount = (prime.bitWidth + 7) / 8
            let secret = BigUInt(bigEndian: randomBytes(64)) + BigUInt(2)
            let e = montgomeryPower(BigUInt(2), secret, modulus: prime)
            let eBytes = e.bigEndianBytes(byteCount)
            var initMessage = SshWriter()
            initMessage.byte(30)
            initMessage.mpint(eBytes)
            try sendPacket(initMessage.bytes)
            let reply = try kexMessage()
            guard reply.first == 31 else { throw SshError(.broken, "KEX yanıtı beklenirken \(reply.first ?? 0)") }
            var reader = SshReader(reply)
            _ = try reader.byte()
            hostKey = try reader.string()
            let fBytes = try reader.mpint()
            signature = try reader.string()
            let f = BigUInt(bigEndian: fBytes)
            guard BigUInt(1) < f, f < prime - BigUInt(1) else { throw SshError(.broken, "TV'nin DH değeri geçersiz") }
            shared = montgomeryPower(f, secret, modulus: prime).bigEndianBytes(byteCount)
            exchange.string(hostKey)
            exchange.mpint(eBytes)
            exchange.mpint(fBytes)
        }
        exchange.mpint(shared)
        let hash = kex.hash.digest(exchange.bytes)
        try Self.verifyHostSignature(hostKey: hostKey, signature: signature, data: hash)

        if first { sessionId = hash }

        var sharedMpint = SshWriter()
        sharedMpint.mpint(shared)
        func derive(_ letter: Character, _ length: Int) -> [UInt8] {
            var key = kex.hash.digest(sharedMpint.bytes + hash + [letter.asciiValue!] + sessionId)
            while key.count < length { key += kex.hash.digest(sharedMpint.bytes + hash + key) }
            return Array(key.prefix(length))
        }
        func keyLength(_ cipher: String) -> Int { cipher.hasPrefix("aes256") ? 32 : cipher.hasPrefix("aes192") ? 24 : 16 }
        let outMac = SshMac(name: macOut)
        let inMac = SshMac(name: macIn)
        let outCipher = try AesCtr(key: derive("C", keyLength(cipherOut)), iv: derive("A", 16))
        let inCipher = try AesCtr(key: derive("D", keyLength(cipherIn)), iv: derive("B", 16))
        // Giden yön NEWKEYS gönderilir gönderilmez, gelen yön TV'nin NEWKEYS'inden sonra yeni anahtarlara geçer (§7.3).
        try sendPacket([21])
        outgoing.cipher = outCipher
        outgoing.mac = outMac
        outgoing.macKey = derive("E", outMac.length)
        let newKeys = try kexMessage()
        guard newKeys.first == 21 else { throw SshError(.broken, "NEWKEYS beklenirken \(newKeys.first ?? 0)") }
        incoming.cipher = inCipher
        incoming.mac = inMac
        incoming.macKey = derive("F", inMac.length)
    }

    /// Anahtar değişimi sürerken gelen ileti: kapatma hata olur, yoksay ve hata ayıklama atlanır, kalanı döner.
    private func kexMessage() throws -> [UInt8] {
        while true {
            let payload = try readPacket()
            switch payload.first {
            case nil, 2, 3, 4:
                continue
            case 1:
                var reader = SshReader(payload)
                _ = try reader.byte()
                _ = try reader.uint32()
                throw SshError(.broken, "TV bağlantıyı kapattı: \((try? reader.text()) ?? "")")
            default:
                return payload
            }
        }
    }

    private static func secret(_ value: SharedSecret) -> [UInt8] { value.withUnsafeBytes { Array($0) } }

    /// TV'nin anahtar değişimi özetine attığı imzayı doğrular (anahtarın kendisi denetlenmez).
    private static func verifyHostSignature(hostKey: [UInt8], signature: [UInt8], data: [UInt8]) throws {
        var key = SshReader(hostKey)
        let type = try key.text()
        var sig = SshReader(signature)
        let algorithm = try sig.text()
        let blob = try sig.string()
        var valid = false
        switch type {
        case "ssh-ed25519":
            let raw = try key.string()
            valid = (try? Curve25519.Signing.PublicKey(rawRepresentation: raw).isValidSignature(blob, for: data)) == true
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try key.string()
            let point = try key.string()
            var parts = SshReader(blob)
            let r = try parts.mpint()
            let s = try parts.mpint()
            func fixed(_ value: [UInt8], _ size: Int) -> [UInt8] { [UInt8](repeating: 0, count: max(0, size - value.count)) + value.suffix(size) }
            switch type {
            case "ecdsa-sha2-nistp256":
                if let signature = try? P256.Signing.ECDSASignature(rawRepresentation: fixed(r, 32) + fixed(s, 32)),
                   let publicKey = try? P256.Signing.PublicKey(x963Representation: point) { valid = publicKey.isValidSignature(signature, for: data) }
            case "ecdsa-sha2-nistp384":
                if let signature = try? P384.Signing.ECDSASignature(rawRepresentation: fixed(r, 48) + fixed(s, 48)),
                   let publicKey = try? P384.Signing.PublicKey(x963Representation: point) { valid = publicKey.isValidSignature(signature, for: data) }
            default:
                if let signature = try? P521.Signing.ECDSASignature(rawRepresentation: fixed(r, 66) + fixed(s, 66)),
                   let publicKey = try? P521.Signing.PublicKey(x963Representation: point) { valid = publicKey.isValidSignature(signature, for: data) }
            }
        case "ssh-rsa":
            let exponent = try key.mpint()
            let modulus = try key.mpint()
            let der = Der.sequence(Der.integer(bytes: modulus), Der.integer(bytes: exponent))
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
            guard let publicKey = SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, nil) else {
                throw SshError(.broken, "TV'nin RSA anahtarı okunamadı")
            }
            let method: SecKeyAlgorithm = switch algorithm {
            case "rsa-sha2-512": .rsaSignatureMessagePKCS1v15SHA512
            case "rsa-sha2-256": .rsaSignatureMessagePKCS1v15SHA256
            default: .rsaSignatureMessagePKCS1v15SHA1
            }
            valid = SecKeyVerifySignature(publicKey, method, Data(data) as CFData, Data(blob) as CFData, nil)
        default:
            throw SshError(.broken, "TV anahtarı türü desteklenmiyor: \(type)")
        }
        guard valid else { throw SshError(.broken, "TV'nin imzası doğrulanamadı (\(algorithm))") }
    }

    // MARK: Giriş

    private func authenticate(user: String, key: RsaKey) throws {
        var request = SshWriter()
        request.byte(5)
        request.string("ssh-userauth")
        try sendPacket(request.bytes)
        let accept = try nextMessage()
        guard accept.first == 6 else { throw SshError(.broken, "ssh-userauth kabul edilmedi (\(accept.first ?? 0))") }

        let parts = key.modulusAndExponent
        var blob = SshWriter()
        blob.string("ssh-rsa")
        blob.mpint(parts.exponent)
        blob.mpint(parts.modulus)
        let all: [(String, SecKeyAlgorithm)] = [("rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512),
                                                ("rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256),
                                                ("ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1)]
        // TV hangi imzaları kabul ettiğini söylediyse yalnız onlar; söylemediyse (eski sunucu) sırayla hepsi.
        var candidates = all.filter { serverSigAlgs?.contains($0.0) ?? true }
        if candidates.isEmpty { candidates = all }
        var lastMethods = ""
        for (name, algorithm) in candidates {
            var signed = SshWriter()
            signed.string(sessionId)
            signed.byte(50)
            signed.string(user)
            signed.string("ssh-connection")
            signed.string("publickey")
            signed.bool(true)
            signed.string(name)
            signed.string(blob.bytes)
            let signature: Data
            do {
                signature = try key.sign(algorithm, Data(signed.bytes))
            } catch {
                throw SshError(.auth, "\(error)")
            }
            var sigBlob = SshWriter()
            sigBlob.string(name)
            sigBlob.string(Array(signature))
            var message = SshWriter()
            message.byte(50)
            message.string(user)
            message.string("ssh-connection")
            message.string("publickey")
            message.bool(true)
            message.string(name)
            message.string(blob.bytes)
            message.string(sigBlob.bytes)
            try sendPacket(message.bytes)
            let reply = try nextMessage()
            if reply.first == 52 { return }
            guard reply.first == 51 else { throw SshError(.broken, "giriş yanıtı beklenirken \(reply.first ?? 0)") }
            var reader = SshReader(reply)
            _ = try reader.byte()
            lastMethods = (try? reader.text()) ?? ""
        }
        throw SshError(.auth, "USERAUTH fail (\(lastMethods))")
    }

    // MARK: Komut

    struct ExecResult {
        var status: Int
        var stdout: [UInt8]
        var stderr: [UInt8]
    }

    /// Komutu çalıştırır; `input` verilirse girişine yazılır ve giriş kapatılır ("cat > dosya" bittiğini böyle anlar).
    func exec(_ command: String, input: [UInt8]?, timeout: TimeInterval) throws -> ExecResult {
        socket.readTimeout = timeout
        let deadline = Date().addingTimeInterval(timeout)
        let localWindow: UInt32 = 2 * 1024 * 1024
        var open = SshWriter()
        open.byte(90)
        open.string("session")
        open.uint32(0)
        open.uint32(localWindow)
        open.uint32(32_768)
        try sendPacket(open.bytes)

        var remoteId: UInt32 = 0
        var remoteWindow: UInt64 = 0
        var remoteMaxPacket = 32_768
        var consumed: UInt32 = 0
        var result = ExecResult(status: -1, stdout: [], stderr: [])
        var closed = false
        var requestReply: Bool?

        func handle(_ message: [UInt8]) throws {
            var reader = SshReader(message)
            let type = try reader.byte()
            switch type {
            case 93:
                _ = try reader.uint32()
                remoteWindow += UInt64(try reader.uint32())
            case 94, 95:
                _ = try reader.uint32()
                if type == 95 { _ = try reader.uint32() }
                let data = try reader.string()
                if type == 94 { result.stdout += data } else { result.stderr += data }
                consumed += UInt32(data.count)
                if consumed > localWindow / 2 {
                    var adjust = SshWriter()
                    adjust.byte(93)
                    adjust.uint32(remoteId)
                    adjust.uint32(consumed)
                    try sendPacket(adjust.bytes)
                    consumed = 0
                }
            case 96:
                break
            case 97:
                closed = true
            case 98:
                _ = try reader.uint32()
                let name = try reader.text()
                let wantReply = try reader.bool()
                if name == "exit-status" {
                    result.status = Int(try reader.uint32())
                } else if name == "exit-signal" {
                    result.status = 255
                    result.stderr += Array("sinyal: \((try? reader.text()) ?? "?")\n".utf8)
                }
                if wantReply {
                    var failure = SshWriter()
                    failure.byte(100)
                    failure.uint32(remoteId)
                    try sendPacket(failure.bytes)
                }
            case 99:
                requestReply = true
            case 100:
                requestReply = false
            default:
                break
            }
        }

        func next() throws {
            if Date() > deadline { throw SshError(.broken, "komut \(Int(timeout)) saniyede bitmedi") }
            try handle(try nextMessage())
        }

        let confirm = try nextMessage()
        var reader = SshReader(confirm)
        switch try reader.byte() {
        case 91:
            _ = try reader.uint32()
            remoteId = try reader.uint32()
            remoteWindow = UInt64(try reader.uint32())
            remoteMaxPacket = Int(try reader.uint32())
        case 92:
            throw SshError(.broken, "TV kanal açmadı")
        default:
            throw SshError(.broken, "kanal yanıtı beklenirken \(confirm.first ?? 0)")
        }

        var request = SshWriter()
        request.byte(98)
        request.uint32(remoteId)
        request.string("exec")
        request.bool(true)
        request.string(command)
        try sendPacket(request.bytes)
        while requestReply == nil, !closed { try next() }
        guard requestReply == true else { throw SshError(.broken, "TV komutu çalıştırmadı") }

        if let input {
            let chunk = max(512, min(remoteMaxPacket, 32_768) - 128)
            var offset = 0
            while offset < input.count, !closed {
                while remoteWindow == 0, !closed { try next() }
                if closed { break }
                let count = min(input.count - offset, chunk, Int(remoteWindow))
                var data = SshWriter()
                data.byte(94)
                data.uint32(remoteId)
                data.string(Array(input[offset..<offset + count]))
                try sendPacket(data.bytes)
                remoteWindow -= UInt64(count)
                offset += count
            }
        }
        if !closed {
            var eof = SshWriter()
            eof.byte(96)
            eof.uint32(remoteId)
            try sendPacket(eof.bytes)
        }
        while !closed { try next() }
        var close = SshWriter()
        close.byte(97)
        close.uint32(remoteId)
        try? sendPacket(close.bytes)
        return result
    }
}

private extension SshReader {
    func uint32Value() throws -> UInt32 {
        var copy = self
        return try copy.uint32()
    }

    mutating func bytesSkip(_ count: Int) throws -> Int {
        for _ in 0..<count { _ = try byte() }
        return count
    }
}
