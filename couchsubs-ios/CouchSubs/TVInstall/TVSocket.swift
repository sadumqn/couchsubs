// SPDX-License-Identifier: AGPL-3.0-only
// TV kurulumunun bağlantıları: Android'deki java.net.Socket gibi bloklayan TCP (BSD soketi) ve adb'nin kablosuz hata
// ayıklamasındaki TLS 1.3 (Network.framework). Kurulum kodu sıralı ve bloklayandır; arka plan iş parçacığında çalışır.

import Foundation
import Network
import Security

struct StreamClosed: Error, CustomStringConvertible {
    var description: String { String(localized: "The TV closed the connection") }
}

struct ConnectFailed: Error, CustomStringConvertible {
    let description: String
}

/// Bayt akışı: TCP ya da TLS.
protocol ByteStream: AnyObject {
    /// En az 1 bayt; akış kapandıysa `StreamClosed`.
    func read(max: Int) throws -> [UInt8]
    func write(_ bytes: [UInt8]) throws
    func close()
    var readTimeout: TimeInterval { get set }
}

/// Okunup bir kısmı kullanılmayan baytları tutan okuyucu.
final class StreamReader {
    let stream: ByteStream
    private var buffer: [UInt8] = []

    init(_ stream: ByteStream) { self.stream = stream }

    func readExactly(_ count: Int) throws -> [UInt8] {
        while buffer.count < count { buffer += try stream.read(max: max(65_536, count - buffer.count)) }
        let result = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    /// Önceden okunmuş ama kullanılmamış baytlar (TLS'e geçerken bırakılır).
    var leftover: [UInt8] { buffer }
}

/// Bloklayan TCP bağlantısı (BSD soketi).
final class PosixSocket: ByteStream {
    private var fd: Int32
    private let lock = NSLock()
    var readTimeout: TimeInterval = 120 { didSet { setTimeout(SO_RCVTIMEO, readTimeout) } }

    static func connect(host: String, port: UInt16, timeout: TimeInterval = 10) throws -> PosixSocket {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let info = result else {
            throw ConnectFailed(description: "\(host): adres çözülemedi")
        }
        defer { freeaddrinfo(result) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw ConnectFailed(description: "soket açılamadı") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var status = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if status != 0 && errno == EINPROGRESS {
            var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&poller, 1, Int32(timeout * 1000))
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
            status = ready > 0 && error == 0 ? 0 : -1
            if ready <= 0 { errno = ETIMEDOUT } else if error != 0 { errno = error }
        }
        guard status == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw ConnectFailed(description: "\(host):\(port): \(reason)")
        }
        _ = fcntl(fd, F_SETFL, flags)
        let socket = PosixSocket(fd: fd)
        socket.readTimeout = 120
        socket.setTimeout(SO_SNDTIMEO, 120)
        return socket
    }

    private init(fd: Int32) { self.fd = fd }

    deinit { close() }

    private func setTimeout(_ option: Int32, _ seconds: TimeInterval) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    func read(max: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: max)
        let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, max, 0) }
        if count > 0 { return Array(buffer.prefix(count)) }
        if count == 0 { throw StreamClosed() }
        if errno == EAGAIN || errno == EWOULDBLOCK { throw ConnectFailed(description: "zaman aşımı") }
        throw ConnectFailed(description: String(cString: strerror(errno)))
    }

    func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { send(fd, $0.baseAddress! + offset, bytes.count - offset, 0) }
            if sent <= 0 { throw ConnectFailed(description: "yazılamadı: \(String(cString: strerror(errno)))") }
            offset += sent
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
            fd = -1
        }
    }

    /// TCP portu açık mı (kısa süreli deneme)?
    static func isOpen(host: String, port: UInt16, timeout: TimeInterval = 0.7) -> Bool {
        guard let socket = try? connect(host: host, port: port, timeout: timeout) else { return false }
        socket.close()
        return true
    }
}

/// TLS 1.3 istemcisi (Network.framework): sunucu sertifikası denetlenmez (adb de denetlemez), istemci kendi kimliğini
/// gösterir. Bloklayan okuma/yazma, semaforlarla.
final class TLSStream: ByteStream {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "couchsubs.tls")
    var readTimeout: TimeInterval = 120

    init(host: String, port: UInt16, identity: SecIdentity, timeout: TimeInterval = 15) throws {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity) { sec_protocol_options_set_local_identity(options, local) }
        sec_protocol_options_set_challenge_block(options, { _, complete in complete(sec_identity_create(identity)) }, queue)
        sec_protocol_options_set_verify_block(options, { _, _, complete in complete(true) }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        let ready = DispatchSemaphore(value: 0)
        var failure: String?
        var signalled = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !signalled { signalled = true; ready.signal() }
            case .failed(let error), .waiting(let error):
                if !signalled { signalled = true; failure = "\(error)"; ready.signal() }
            case .cancelled:
                if !signalled { signalled = true; failure = "iptal"; ready.signal() }
            default: break
            }
        }
        connection.start(queue: queue)
        if ready.wait(timeout: .now() + timeout) == .timedOut {
            connection.cancel()
            throw ConnectFailed(description: "TLS zaman aşımı")
        }
        if let failure {
            connection.cancel()
            throw ConnectFailed(description: "TLS: \(failure)")
        }
    }

    /// RFC 8446 dışa aktarıcı (eşleştirme şifresinin TLS parçası).
    func exportKeyingMaterial(label: [UInt8], length: Int) -> [UInt8]? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        let secret = label.withUnsafeBufferPointer { pointer in
            pointer.withMemoryRebound(to: CChar.self) {
                sec_protocol_metadata_create_secret(metadata.securityProtocolMetadata, label.count, $0.baseAddress!, length)
            }
        }
        guard let secret else { return nil }
        let data = secret as DispatchData
        return [UInt8](data)
    }

    func read(max: Int) throws -> [UInt8] {
        let done = DispatchSemaphore(value: 0)
        var result: [UInt8] = []
        var failure: Error?
        connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, complete, error in
            if let data, !data.isEmpty { result = [UInt8](data) } else if let error { failure = error } else if complete { failure = StreamClosed() }
            done.signal()
        }
        if done.wait(timeout: .now() + readTimeout) == .timedOut { throw ConnectFailed(description: "zaman aşımı") }
        if let failure { throw failure }
        if result.isEmpty { throw StreamClosed() }
        return result
    }

    func write(_ bytes: [UInt8]) throws {
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            failure = error
            done.signal()
        })
        if done.wait(timeout: .now() + 120) == .timedOut { throw ConnectFailed(description: "yazma zaman aşımı") }
        if let failure { throw failure }
    }

    func close() { connection.cancel() }
}

/// Açık bir TCP bağlantısını yerel bir porta aktarır: Network.framework var olan bağlantıda TLS'e geçemez (adb'nin
/// STLS'i), TLS bu yerel porta açılır, baytlar TV bağlantısına olduğu gibi gider.
final class LoopbackRelay {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "couchsubs.relay")
    private let upstream: ByteStream
    private var accepted: NWConnection?
    private(set) var port: UInt16 = 0

    init(upstream: ByteStream, leftover: [UInt8]) throws {
        self.upstream = upstream
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        let queue = self.queue
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.accepted == nil else { connection.cancel(); return }
            self.accepted = connection
            connection.start(queue: queue)
            if !leftover.isEmpty { connection.send(content: Data(leftover), completion: .idempotent) }
            self.pumpDown(connection)
            self.pumpUp(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let value = listener.port?.rawValue else {
            listener.cancel()
            throw ConnectFailed(description: "yerel aktarma açılamadı")
        }
        port = value
    }

    /// TV → yerel TLS.
    private func pumpDown(_ connection: NWConnection) {
        let upstream = self.upstream
        Thread.detachNewThread {
            upstream.readTimeout = 600
            while true {
                guard let bytes = try? upstream.read(max: 65_536) else { break }
                let sent = DispatchSemaphore(value: 0)
                connection.send(content: Data(bytes), completion: .contentProcessed { _ in sent.signal() })
                sent.wait()
            }
            connection.cancel()
        }
    }

    /// Yerel TLS → TV.
    private func pumpUp(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty, (try? self.upstream.write([UInt8](data))) != nil {
                self.pumpUp(connection)
            } else if complete || error != nil || data == nil {
                self.upstream.close()
            }
        }
    }

    func close() {
        listener.cancel()
        accepted?.cancel()
        upstream.close()
    }
}

/// adb'nin TLS'i için kimlik: adb anahtarı ve onun kendinden imzalı sertifikası Anahtarlık'a eklenir, oradan kimlik
/// (SecIdentity) olarak okunur (iOS'ta anahtar ve sertifikadan kimlik ancak böyle kurulur).
enum TLSIdentity {
    static func make(key: RsaKey, certificateFile: URL) throws -> SecIdentity {
        let der: Data
        if let saved = try? Data(contentsOf: certificateFile), SecCertificateCreateWithData(nil, saved as CFData) != nil {
            der = saved
        } else {
            der = try SelfSigned.certificate(key: key)
            try? der.write(to: certificateFile, options: .atomic)
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw TVCryptoError("sertifika üretilemedi") }
        let label = "CouchSubs adb"
        let tag = Data("com.couchsubs.adb.\(certificateFile.lastPathComponent)".utf8)
        let keyQuery: [CFString: Any] = [kSecClass: kSecClassKey, kSecValueRef: key.privateKey, kSecAttrApplicationTag: tag,
                                         kSecAttrLabel: label, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let keyStatus = SecItemAdd(keyQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else { throw TVCryptoError("anahtar Anahtarlık'a eklenemedi (\(keyStatus))") }
        let certificateQuery: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: label]
        let certificateStatus = SecItemAdd(certificateQuery as CFDictionary, nil)
        guard certificateStatus == errSecSuccess || certificateStatus == errSecDuplicateItem else {
            throw TVCryptoError("sertifika Anahtarlık'a eklenemedi (\(certificateStatus))")
        }
        let query: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess, let identities = items as? [SecIdentity] else {
            throw TVCryptoError("kimlik bulunamadı")
        }
        for identity in identities {
            var found: SecCertificate?
            if SecIdentityCopyCertificate(identity, &found) == errSecSuccess, let found, SecCertificateCopyData(found) as Data == der {
                return identity
            }
        }
        throw TVCryptoError("kimlik bulunamadı")
    }
}
