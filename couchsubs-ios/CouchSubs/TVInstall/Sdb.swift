// SPDX-License-Identifier: AGPL-3.0-only
// sdb protokolü TizenSdb.Core'dan (MIT, Patrick Stel) taşındı: https://github.com/PatrickSt1991/tizen-sdb
// (Android'deki Sdb.kt'nin Swift karşılığı). ADB ile aynı çerçeve biçimi; AdbConnection da bu çerçeveyi kullanır.

import CouchSubsCore
import Foundation

/// sdb/adb çerçevesi: 24 baytlık küçük-endian başlık ve veri.
struct WireFrame {
    static let cnxn: UInt32 = 0x4E58_4E43
    static let auth: UInt32 = 0x4854_5541
    static let open: UInt32 = 0x4E45_504F
    static let okay: UInt32 = 0x5941_4B4F
    static let wrte: UInt32 = 0x4554_5257
    static let clse: UInt32 = 0x4553_4C43
    static let stls: UInt32 = 0x534C_5453
    static let header = 24

    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    var payload: [UInt8] = []

    static func checksum(_ payload: [UInt8]) -> UInt32 { payload.reduce(UInt32(0)) { $0 &+ UInt32($1) } }

    func encoded() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(WireFrame.header + payload.count)
        for value in [command, arg0, arg1, UInt32(payload.count), WireFrame.checksum(payload), command ^ 0xFFFF_FFFF] {
            out += le32(value)
        }
        return out + payload
    }

    /// Çerçeve okur. `checkSum`: sdb toplamı denetler; yeni adbd'ler toplamı 0 gönderir.
    static func read(_ reader: StreamReader, checkSum: Bool, maxPayload: Int = 16 * 1024 * 1024) throws -> WireFrame {
        let head = try reader.readExactly(header)
        let command = readLE32(head, 0), arg0 = readLE32(head, 4), arg1 = readLE32(head, 8)
        let length = Int(readLE32(head, 12)), sum = readLE32(head, 16), magic = readLE32(head, 20)
        guard length >= 0, length <= maxPayload else { throw ConnectFailed(description: "geçersiz uzunluk \(length)") }
        let payload = length > 0 ? try reader.readExactly(length) : []
        guard magic == command ^ 0xFFFF_FFFF else { throw ConnectFailed(description: String(format: "geçersiz çerçeve (komut %08X)", command)) }
        if checkSum, sum != checksum(payload) { throw ConnectFailed(description: "denetim toplamı tutmuyor") }
        return WireFrame(command: command, arg0: arg0, arg1: arg1, payload: payload)
    }
}

func le32(_ value: UInt32) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)] }
func readLE32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
}
func be32(_ value: UInt32) -> [UInt8] { le32(value).reversed() }

/// sync: alt protokolünün paketi: 4 harfli kimlik, küçük-endian uzunluk, veri.
func syncPacket(_ id: String, _ payload: ArraySlice<UInt8>) -> [UInt8] { Array(id.utf8) + le32(UInt32(payload.count)) + payload }

/// sdb ile adb'nin ortak kanal mantığı: bir anda tek kanal açıktır, çerçeveler çağıranın iş parçacığında okunur.
class WireConnection {
    let stream: ByteStream
    var reader: StreamReader
    var output: ByteStream
    let checkSum: Bool
    var maxData = 4096
    private var nextLocalId: UInt32

    init(stream: ByteStream, checkSum: Bool, firstLocalId: UInt32) {
        self.stream = stream
        reader = StreamReader(stream)
        output = stream
        self.checkSum = checkSum
        nextLocalId = firstLocalId
    }

    func send(_ frame: WireFrame) throws { try output.write(frame.encoded()) }
    func readFrame() throws -> WireFrame { try WireFrame.read(reader, checkSum: checkSum) }

    final class Channel {
        let localId: UInt32
        var remoteId: UInt32 = 0
        fileprivate var pending: [[UInt8]] = []
        fileprivate var acked = false
        private(set) var closed = false
        private unowned let owner: WireConnection

        fileprivate init(localId: UInt32, owner: WireConnection) {
            self.localId = localId
            self.owner = owner
        }

        /// TV'nin gönderdiği bir sonraki parça; kanal kapandıysa nil.
        func read() throws -> [UInt8]? {
            while pending.isEmpty {
                if closed { return nil }
                try pump()
            }
            return pending.removeFirst()
        }

        func readAll() throws -> [UInt8] {
            var all: [UInt8] = []
            while let chunk = try read() { all += chunk }
            return all
        }

        func readExactly(_ size: Int) throws -> [UInt8] {
            var result: [UInt8] = []
            while result.count < size {
                guard let chunk = try read() else { throw StreamClosed() }
                let need = size - result.count
                if chunk.count <= need {
                    result += chunk
                } else {
                    result += chunk.prefix(need)
                    pending.insert(Array(chunk[need...]), at: 0)
                }
            }
            return result
        }

        /// Veriyi `maxData`'lık parçalarla yazar; TV her parçayı OKAY ile onaylar. Kanal kapanırsa hata.
        func write(_ data: [UInt8]) throws {
            var offset = 0
            while offset < data.count {
                if closed { throw ConnectFailed(description: "TV kanalı kapattı") }
                let size = min(owner.maxData, data.count - offset)
                acked = false
                try owner.send(WireFrame(command: WireFrame.wrte, arg0: localId, arg1: remoteId, payload: Array(data[offset..<offset + size])))
                while !acked {
                    if closed { throw ConnectFailed(description: "TV kanalı kapattı") }
                    try pump()
                }
                offset += size
            }
        }

        func pump() throws {
            let frame = try owner.readFrame()
            switch frame.command {
            case WireFrame.okay:
                if frame.arg1 == localId { if remoteId == 0 { remoteId = frame.arg0 } else { acked = true } }
            case WireFrame.wrte:
                if frame.arg1 == localId {
                    if remoteId == 0 { remoteId = frame.arg0 }
                    pending.append(frame.payload)
                    try owner.send(WireFrame(command: WireFrame.okay, arg0: localId, arg1: frame.arg0))
                } else {
                    try owner.send(WireFrame(command: WireFrame.clse, arg0: frame.arg1, arg1: frame.arg0))
                }
            case WireFrame.clse:
                if frame.arg1 == localId || frame.arg1 == 0 {
                    closed = true
                    try? owner.send(WireFrame(command: WireFrame.clse, arg0: localId, arg1: frame.arg0))
                }
            case WireFrame.open:
                try owner.send(WireFrame(command: WireFrame.clse, arg0: frame.arg1, arg1: frame.arg0))
            default:
                break
            }
        }

        func close() {
            if closed { return }
            closed = true
            try? owner.send(WireFrame(command: WireFrame.clse, arg0: localId, arg1: remoteId))
        }
    }

    /// Kanal açar ve TV'nin onayını (OKAY) bekler.
    func open(_ service: String) throws -> Channel {
        nextLocalId += 1
        let channel = Channel(localId: nextLocalId, owner: self)
        try send(WireFrame(command: WireFrame.open, arg0: channel.localId, arg1: 0, payload: Array(service.utf8) + [0]))
        while channel.remoteId == 0 {
            if channel.closed { throw ConnectFailed(description: "TV hizmeti açmadı (\(service))") }
            try channel.pump()
        }
        return channel
    }

    /// Hizmeti açar, varsa girdiyi gönderir ve hizmet kapanana kadar bütün çıktıyı döner.
    func run(_ service: String, input: [UInt8]? = nil) throws -> String {
        let channel = try open(service)
        defer { channel.close() }
        if let input { try channel.write(input) }
        return String(decoding: try channel.readAll(), as: UTF8.self)
    }

    func close() { stream.close() }
}

/// sdb istemcisi (Samsung TV'nin geliştirici modu, port 26101).
final class SdbConnection: WireConnection {
    static let port: UInt16 = 26101
    private(set) var banner = ""

    /// Samsung'un sdbd'si yeni açılmış bağlantıyı bazen el sıkışmanın ortasında kapatır; üç kez denenir.
    static func connect(host: String, key: AdbKey, port: UInt16 = port, timeout: TimeInterval = 10) throws -> SdbConnection {
        var last: Error = ConnectFailed(description: "sdb bağlantısı kurulamadı")
        for attempt in 0..<3 {
            do {
                let socket = try PosixSocket.connect(host: host, port: port, timeout: timeout)
                let connection = SdbConnection(stream: socket, checkSum: true, firstLocalId: UInt32(Character("a").asciiValue!))
                do {
                    try connection.handshake(key)
                    return connection
                } catch {
                    socket.close()
                    throw error
                }
            } catch {
                last = error
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
            }
        }
        throw last
    }

    private func handshake(_ key: AdbKey) throws {
        try send(WireFrame(command: WireFrame.cnxn, arg0: 0x0100_0000, arg1: UInt32(maxData), payload: Array("host::sdb-net-client".utf8)))
        while true {
            let reply = try readFrame()
            switch reply.command {
            case WireFrame.cnxn:
                if reply.arg1 > 0 { maxData = min(maxData, Int(reply.arg1)) }
                banner = String(decoding: reply.payload, as: UTF8.self)
                return
            case WireFrame.auth:
                switch reply.arg0 {
                case 1: try send(WireFrame(command: WireFrame.auth, arg0: 2, arg1: 0, payload: try key.sign(reply.payload)))
                case 3: try send(WireFrame(command: WireFrame.auth, arg0: 3, arg1: 0, payload: Array((key.publicKeyLine("couchsubs@iphone") + "\u{0}").utf8)))
                default: throw ConnectFailed(description: "sdb: bilinmeyen AUTH türü \(reply.arg0)")
                }
            default:
                throw ConnectFailed(description: "sdb: CNXN ya da AUTH bekleniyordu")
            }
        }
    }

    /// Kabuk komutu (sdb'nin `shell:` hizmeti).
    func shell(_ command: String) throws -> String { try run("shell:\(command)") }

    /// `capability:` yanıtı: ilk iki bayt uzunluk, sonra `anahtar:değer` satırları.
    func capability() throws -> [String: String] { Self.parseCapability(Array(try run("capability:").utf8)) }

    static func parseCapability(_ bytes: [UInt8]) -> [String: String] {
        guard bytes.count >= 2 else { return [:] }
        var result: [String: String] = [:]
        for line in String(decoding: bytes[2...], as: UTF8.self).deviceLines where !line.isEmpty {
            let parts = line.split(separator: ":").map(String.init).filter { !$0.isEmpty }
            if parts.count == 2, result[parts[0]] == nil { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// Dosyayı TV'ye gönderir (sync: SEND, DATA…, DONE; TV OKAY ya da FAIL döner).
    func push(_ data: [UInt8], to remotePath: String) throws {
        let channel = try open("sync:")
        defer { channel.close() }
        try channel.write(syncPacket("SEND", ArraySlice(Array(remotePath.utf8))))
        var offset = 0
        while offset < data.count {
            let size = min(64 * 1024, data.count - offset)
            try channel.write(syncPacket("DATA", data[offset..<offset + size]))
            offset += size
        }
        try channel.write(syncPacket("DONE", ArraySlice(le32(UInt32(Date().timeIntervalSince1970)))))
        while true {
            let header = try channel.readExactly(8)
            let id = String(decoding: header.prefix(4), as: UTF8.self)
            let length = Int(readLE32(header, 4))
            let payload = length > 0 ? try channel.readExactly(length) : []
            if id == "OKAY" { return }
            if id == "FAIL" {
                let text = String(decoding: payload, as: UTF8.self)
                throw ConnectFailed(description: "sdb sync: FAIL: \(text.isEmpty ? "unknown" : text)")
            }
        }
    }
}

/// sdb ve adb'nin kimlik doğrulama anahtarı: 2048 bit RSA (Android'deki AdbKey).
final class AdbKey {
    let key: RsaKey
    /// adb'nin TLS'i (kablosuz hata ayıklama) için sertifikanın saklandığı dosya.
    let certificateFile: URL

    init(key: RsaKey, certificateFile: URL) {
        self.key = key
        self.certificateFile = certificateFile
    }

    static func loadOrCreate(_ file: URL) throws -> AdbKey {
        AdbKey(key: try RsaKey.loadOrCreate(file), certificateFile: file.appendingPathExtension("cer"))
    }

    /// Android'in RSAPublicKey yapısı: sözcük sayısı, n0inv, modül ve R² (küçük-endian 256 bayt), üs.
    func encodedPublicKey() -> [UInt8] {
        let size = 256
        let (modulusBytes, exponentBytes) = key.modulusAndExponent
        let n = BigUInt(bigEndian: modulusBytes)
        let n0 = n.low32
        var inverse: UInt32 = n0
        for _ in 0..<5 { inverse = inverse &* (2 &- n0 &* inverse) }
        let n0inv = 0 &- inverse
        let rr = (BigUInt(1) << (size * 8 * 2)) % n
        let exponent = BigUInt(bigEndian: exponentBytes).low32
        return le32(UInt32(size / 4)) + le32(n0inv) + n.littleEndianBytes(size) + rr.littleEndianBytes(size) + le32(exponent)
    }

    /// adb'nin açık anahtar satırı: Android biçimindeki anahtarın base64'ü ve "kullanıcı@cihaz".
    func publicKeyLine(_ name: String) -> String { Data(encodedPublicKey()).base64EncodedString() + " " + name }

    /// Samsung'un sdbd'si: jeton SHA-1 ile özetlenip imzalanır.
    func sign(_ token: [UInt8]) throws -> [UInt8] { Array(try key.sign(.rsaSignatureMessagePKCS1v15SHA1, Data(token))) }

    /// adbd: TV'nin 20 baytlık jetonu SHA-1 özeti yerine geçer, yeniden özetlenmez.
    func signAdbToken(_ token: [UInt8]) throws -> [UInt8] { Array(try key.sign(.rsaSignatureDigestPKCS1v15SHA1, Data(token))) }
}
