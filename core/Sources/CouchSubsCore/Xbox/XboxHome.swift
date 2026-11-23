// SPDX-License-Identifier: AGPL-3.0-only
// Xbox konsol listesi ve ev yayını uçları: Windows köprüsündeki istekler birebir (Android: xbox/XboxHome.kt).

import Foundation

public struct XboxIceCandidate: Equatable {
    public var candidate: String
    public var sdpMid: String?
    public var sdpMLineIndex: Int32

    public init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }

    var json: JSON { ["candidate": candidate, "sdpMLineIndex": sdpMLineIndex, "sdpMid": sdpMid ?? NSNull()] }

    /// libwebrtc'ye verilecek satır: "a=" öneki ve sondaki boşluk atılır; "end-of-candidates" için nil.
    public var sdpLine: String? {
        var line = candidate.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("a=") { line.removeFirst(2) }
        return line.hasPrefix("candidate:") ? line : nil
    }

    static func parse(_ o: JSON) -> XboxIceCandidate {
        XboxIceCandidate(candidate: o["candidate"] as? String ?? "", sdpMid: o["sdpMid"] as? String,
                         sdpMLineIndex: (o["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0)
    }
}

public struct XboxSessionStatus {
    public let state: String
    public let errorDetails: String?
}

/// Teredo adresinden (2001:0::/32) istemcinin IPv4 adresi ve UDP bağlantı noktası (ip-address `inspectTeredo`).
enum Teredo {
    static func inspect(_ address: String) -> (client4: String, udpPort: Int)? {
        guard let groups = parseIPv6(address) else { return nil }
        let port = ~groups[5] & 0xffff
        let client = ~((UInt32(groups[6]) << 16) | UInt32(groups[7]))
        let ip = [24, 16, 8, 0].map { String((client >> UInt32($0)) & 0xff) }.joined(separator: ".")
        return (ip, port)
    }

    static func parseIPv6(_ address: String) -> [Int]? {
        var text = address.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") { text.removeFirst() }
        if text.hasSuffix("]") { text.removeLast() }
        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
        guard !text.isEmpty, text.filter({ $0 == ":" }).count >= 2 else { return nil }
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String) -> [Int]? {
            if part.isEmpty { return [] }
            var out: [Int] = []
            for g in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(g.count), let value = Int(g, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }
        guard let head = groups(halves[0]) else { return nil }
        let tail = halves.count == 2 ? groups(halves[1]) : []
        guard let tail else { return nil }
        let missing = 8 - head.count - tail.count
        if halves.count == 1 && missing != 0 { return nil }
        if halves.count == 2 && missing < 1 { return nil }
        return head + Array(repeating: 0, count: max(0, missing)) + tail
    }
}

public final class XboxHome: Sendable {
    /// Xbox yalnız tarayıcı/Windows istemcisini kabul ediyor; köprüdeki X-MS-Device-Info birebir.
    public static let deviceInfo = "{\"appInfo\":{\"env\":{\"clientAppId\":\"Microsoft.GamingApp\",\"clientAppType\":\"native\","
        + "\"clientAppVersion\":\"2203.1001.4.0\",\"clientSdkVersion\":\"8.5.2\",\"httpEnvironment\":\"prod\",\"sdkInstallId\":\"\"}},"
        + "\"dev\":{\"hw\":{\"make\":\"Microsoft\",\"model\":\"Surface Pro\",\"sdktype\":\"native\"},"
        + "\"os\":{\"name\":\"Windows 11\",\"ver\":\"22631.2715\",\"platform\":\"desktop\"},"
        + "\"displayInfo\":{\"dimensions\":{\"widthInPixels\":1920,\"heightInPixels\":1080},\"pixelDensity\":{\"dpiX\":1,\"dpiY\":1}}}}"
    /// SDP/ICE yanıtı ilk 5 sn 250 ms'de bir, sonra saniyede bir, toplam 30 sn sorulur. Eskiden 7,5 sn'de bırakılıyordu:
    /// Wi-Fi'daki Xbox yanıtı geç verince oturum Xbox'ta "uzaktan oynatma başladı"dan birkaç saniye sonra kapanıyordu.
    public static let exchangeFastAttempts = 20
    public static let exchangeIntervalMs = 250
    public static let exchangeSlowIntervalMs = 1000
    public static let exchangeAttempts = exchangeFastAttempts + 25

    static func exchangeDelayMs(attempt: Int) -> Int { attempt < exchangeFastAttempts ? exchangeIntervalMs : exchangeSlowIntervalMs }

    private let auth: XboxAuth
    private let http: XboxHTTP
    private let sleep: @Sendable (Int) async throws -> Void

    public init(auth: XboxAuth, http: XboxHTTP = URLSessionXboxHTTP(),
         sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }) {
        self.auth = auth
        self.http = http
        self.sleep = sleep
    }

    static func playBody(consoleId: String, timezoneOffsetMinutes: Int) -> JSON {
        ["clientSessionId": "", "titleId": "", "systemUpdateGroup": "", "serverId": consoleId, "fallbackRegionNames": [String](),
         "settings": ["nanoVersion": "V3;WebrtcTransport.dll", "enableOptionalDataCollection": false, "enableTextToSpeech": false,
                      "highContrast": 0, "locale": "en-US", "useIceConnection": false, "timezoneOffsetMinutes": timezoneOffsetMinutes,
                      "sdkType": "web", "osName": "windows"] as JSON]
    }

    static func sdpBody(_ sdp: String) -> JSON {
        func range(_ min: Int, _ max: Int) -> JSON { ["minVersion": min, "maxVersion": max] }
        return ["messageType": "offer", "sdp": sdp, "configuration": [
            "chatConfiguration": ["bytesPerSample": 2, "expectedClipDurationMs": 20, "format": ["codec": "opus", "container": "webm"],
                                  "numChannels": 1, "sampleFrequencyHz": 24000] as JSON,
            "chat": range(1, 1), "control": range(1, 3), "input": range(1, 8), "message": range(1, 1)] as JSON]
    }

    static func sessionId(_ play: JSON) -> String? {
        guard let path = play["sessionPath"] as? String, let last = path.split(separator: "/").last, !last.isEmpty else { return nil }
        return String(last)
    }

    /// Köprüdeki gibi: "2001" ile başlayan adresten Teredo'nun IPv4 adayları (9002 ve Teredo bağlantı noktası) öne eklenir.
    public static func expandCandidates(_ candidates: [XboxIceCandidate]) -> [XboxIceCandidate] {
        var expanded: [XboxIceCandidate] = []
        for item in candidates {
            let parts = item.candidate.components(separatedBy: " ")
            if parts.count > 4, parts[4].hasPrefix("2001"), let teredo = Teredo.inspect(parts[4]) {
                for port in [9002, teredo.udpPort] {
                    var copy = item
                    copy.candidate = "a=candidate:10 1 UDP 1 \(teredo.client4) \(port) typ host "
                    expanded.append(copy)
                }
            }
            expanded.append(item)
        }
        return expanded
    }

    public static var timezoneOffsetMinutes: Int { TimeZone.current.secondsFromGMT() / 60 }

    public func consoles() async throws -> [XboxConsole] {
        let token = try await auth.xsts(XboxAuth.rpXboxLive)
        let response = try await http.request("GET", "https://xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true", headers: [
            "Accept-Language": "en-US", "Accept": "application/json", "x-xbl-contract-version": "4", "Content-Type": "application/json",
            "skillplatform": "RemoteManagement", "Authorization": "XBL3.0 x=\(token.userHash);\(token.token)"], body: nil)
        guard response.ok else { throw XboxError(.service, "Xbox listesi: HTTP \(response.status) \(response.text.prefix(300))") }
        return XboxConsole.parseList(try parseJSON(response.body))
    }

    @discardableResult
    func api(_ path: String, method: String = "GET", data: JSON? = nil) async throws -> JSON? {
        var response = try await send(path, method: method, data: data)
        // Hizmet jetonu süresinden önce reddedildi: jeton bir kez yenilenip istek yinelenir.
        if response.status == 401 {
            await auth.invalidateHomeToken()
            response = try await send(path, method: method, data: data)
        }
        guard response.ok else { throw Self.serviceError(response) }
        if response.status == 204 || response.body.isEmpty { return nil }
        return try parseJSON(response.body)
    }

    private func send(_ path: String, method: String, data: JSON?) async throws -> XboxHTTPResponse {
        let endpoint = try await auth.homeEndpoint()
        return try await http.request(method, endpoint.baseURL + path, headers: [
            "Accept": "application/json", "Content-Type": "application/json", "Authorization": "Bearer \(endpoint.token)",
            "X-Gssv-Client": "XboxComBrowser", "X-MS-Device-Info": Self.deviceInfo], body: data.map(jsonText))
    }

    public static func serviceError(_ response: XboxHTTPResponse) -> XboxError {
        let detail = String(response.text.prefix(500))
        let kind: XboxErrorKind
        if response.status == 401 || response.status == 403 { kind = .signInRequired }
        else if detail.range(of: "InUse", options: .caseInsensitive) != nil || detail.range(of: "Busy", options: .caseInsensitive) != nil { kind = .busy }
        else if response.status == 404 || detail.range(of: "NotFound", options: .caseInsensitive) != nil
                    || detail.range(of: "Offline", options: .caseInsensitive) != nil { kind = .consoleUnavailable }
        else { kind = .service }
        return XboxError(kind, "Xbox service HTTP \(response.status): \(detail)")
    }

    public func play(consoleId: String) async throws -> String {
        let result = try await api("/v5/sessions/home/play", method: "POST",
                                   data: Self.playBody(consoleId: consoleId, timezoneOffsetMinutes: Self.timezoneOffsetMinutes))
        guard let id = result.flatMap(Self.sessionId) else { throw XboxError(.service, "Xbox did not return a stream session") }
        return id
    }

    public func state(_ sessionId: String) async throws -> XboxSessionStatus {
        let status = try await api("/v5/sessions/home/\(sessionId)/state") ?? [:]
        let details = status["errorDetails"].flatMap { $0 is NSNull ? nil : ($0 as? String ?? jsonText($0)) }
        return XboxSessionStatus(state: status["state"] as? String ?? "", errorDetails: details)
    }

    public func connect(_ sessionId: String) async throws {
        let lpt = try await auth.transferToken()
        try await api("/v5/sessions/home/\(sessionId)/connect", method: "POST", data: ["userToken": lpt])
    }

    private func exchange(_ path: String, _ payload: JSON) async throws -> String {
        try await api(path, method: "POST", data: payload)
        for attempt in 0..<Self.exchangeAttempts {
            if let text = try await api(path)?["exchangeResponse"] as? String, !text.isEmpty { return text }
            try await sleep(Self.exchangeDelayMs(attempt: attempt))
        }
        throw XboxError(.timeout, "Xbox WebRTC exchange timed out (\(path.hasSuffix("/ice") ? "ICE" : "SDP"), 30 sn)")
    }

    public func sdp(_ sessionId: String, offer: String) async throws -> String {
        let answer = try parseJSON(try await exchange("/v5/sessions/home/\(sessionId)/sdp", Self.sdpBody(offer)))
        guard let sdp = answer["sdp"] as? String, !sdp.isEmpty else { throw XboxError(.service, "Xbox SDP yanıtı boş") }
        return sdp
    }

    public func ice(_ sessionId: String, candidates: [XboxIceCandidate]) async throws -> [XboxIceCandidate] {
        let text = try await exchange("/v5/sessions/home/\(sessionId)/ice", ["messageType": "iceCandidate", "candidate": candidates.map(\.json)])
        guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [JSON] else {
            throw XboxError(.service, "Xbox ICE yanıtı okunamadı")
        }
        return Self.expandCandidates(array.map(XboxIceCandidate.parse))
    }

    public func keepalive(_ sessionId: String) async throws {
        try await api("/v5/sessions/home/\(sessionId)/keepalive", method: "POST", data: [:])
    }

    public func stop(_ sessionId: String) async throws {
        try await api("/v5/sessions/home/\(sessionId)", method: "DELETE")
    }

    /// Oturumu kapatır; olmazsa `XboxSessionClose.delaysMs` aralıklarıyla yineler. Oturum Xbox hizmetinde zaten yoksa
    /// (404/410) kapanmış sayılır. Dönen değer: kapandı mı, olmadıysa son hata.
    public func close(_ sessionId: String) async -> (closed: Bool, error: String?) {
        var last: String?
        for delay in XboxSessionClose.delaysMs {
            if delay > 0 { try? await sleep(delay) }
            do {
                try await stop(sessionId)
                return (true, nil)
            } catch {
                let message = (error as? XboxError)?.message ?? error.localizedDescription
                if XboxKeepalive.sessionGone(message) { return (true, nil) }
                last = message
            }
        }
        return (false, last)
    }
}
