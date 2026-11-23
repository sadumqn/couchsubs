// SPDX-License-Identifier: AGPL-3.0-only
// Microsoft girişi ve Xbox jeton zinciri: Windows köprüsünün kullandığı xal-node `Msal` yolunun birebir karşılığı
// (Android: xbox/XboxAuth.kt). SISU ve imzalı istek bu yolda yoktur.

import Foundation

public struct XboxHTTPResponse {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
    public var ok: Bool { (200...299).contains(status) }
    public var text: String { String(decoding: body, as: UTF8.self) }
}

/// Xbox ve Microsoft uçlarına HTTPS isteği (testlerde sahtesi verilir).
public protocol XboxHTTP: Sendable {
    func request(_ method: String, _ url: String, headers: [String: String], body: String?) async throws -> XboxHTTPResponse
}

public struct URLSessionXboxHTTP: XboxHTTP {
    public init() {}
    public func request(_ method: String, _ url: String, headers: [String: String], body: String?) async throws -> XboxHTTPResponse {
        guard let address = URL(string: url) else { throw XboxError(.service, "Geçersiz adres: \(url)") }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body.map { Data($0.utf8) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return XboxHTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw XboxError(.network, "Xbox hizmetine ulaşılamadı: \(error.localizedDescription)")
        }
    }
}

func formBody(_ pairs: [(String, String)]) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._*")
    func encode(_ text: String) -> String {
        (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text).replacingOccurrences(of: "%20", with: "+")
    }
    return pairs.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&")
}

/// Jetonlar bellekte tutulur, süresi dolmadan (60 sn pay) yenilenir; kalıcı olan yalnız kullanıcı jetonudur, her
/// değiştiğinde `onUserToken` çağrılır (çağıran Anahtar Zinciri'ne yazar).
public actor XboxAuth {
    public static let clientId = "1f907974-e22b-4810-a9de-d9647380c97e"
    public static let scope = "xboxlive.signin openid profile offline_access"
    public static let transferScope = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
    public static let rpXboxLive = "http://xboxlive.com"
    public static let rpGssv = "http://gssv.xboxlive.com/"
    private static let margin = 60
    private static let login = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    private static let form = "application/x-www-form-urlencoded"
    private static let browserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    /// XSTS 401 XErr: Xbox profili yok (…233), ülke (…235), yetişkin onayı/çocuk hesabı (…236-238).
    private static let noAccountXErr: Set<Int64> = [2148916233, 2148916235, 2148916236, 2148916237, 2148916238]

    private let http: XboxHTTP
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (Int) async throws -> Void
    private let onUserToken: @Sendable (XboxUserToken?) -> Void
    public private(set) var userToken: XboxUserToken?
    private var xblUser: XboxXstsToken?
    private var xsts: [String: XboxXstsToken] = [:]
    private var home: XboxHomeEndpoint?

    public init(http: XboxHTTP = URLSessionXboxHTTP(), clock: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) },
         userToken: XboxUserToken? = nil, onUserToken: @escaping @Sendable (XboxUserToken?) -> Void = { _ in }) {
        self.http = http
        self.clock = clock
        self.sleep = sleep
        self.userToken = userToken
        self.onUserToken = onUserToken
    }

    public var signedIn: Bool { userToken != nil }

    public func startDeviceCode() async throws -> XboxDeviceCode {
        let response = try await http.request("POST", "\(Self.login)/devicecode", headers: ["Content-Type": Self.form],
                                              body: formBody([("client_id", Self.clientId), ("scope", Self.scope)]))
        return try XboxDeviceCode.parse(json(response, "Microsoft cihaz kodu"))
    }

    /// Kullanıcı kodu onaylayana kadar bekler; görev iptal edilirse CancellationError.
    public func pollDeviceCode(_ code: XboxDeviceCode) async throws -> XboxUserToken {
        let deadline = clock().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = code.interval * 1000
        while true {
            try Task.checkCancellation()
            // Ağ hatası girişi bitirmez: kullanıcı kodu Safari'de yazarken uygulama arka plandadır ve istek kesilir
            // (Android'de de aynı). Kodun süresi dolana kadar sorulmaya devam edilir.
            let response: XboxHTTPResponse
            do {
                response = try await http.request("POST", "\(Self.login)/token", headers: ["Content-Type": Self.form], body: formBody([
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"), ("client_id", Self.clientId), ("device_code", code.deviceCode)]))
            } catch let failure as XboxError where failure.kind == .network && clock() < deadline {
                try await sleep(interval)
                continue
            }
            if response.ok {
                let token = try XboxUserToken.fromResponse(try parseJSON(response.body), now: clock())
                reset()
                userToken = token
                onUserToken(token)
                return token
            }
            switch DeviceCodePoll.classify(status: response.status, body: response.body) {
            case .pending: break
            case .slowDown: interval += 5000
            case .expired: throw XboxError(.codeExpired, "Microsoft kodunun süresi doldu")
            case .declined: throw XboxError(.signInDeclined, "Microsoft girişi reddedildi")
            case .failed: throw XboxError(.service, "Microsoft girişi: HTTP \(response.status) \(response.text.prefix(200))")
            }
            if clock() >= deadline { throw XboxError(.codeExpired, "Microsoft kodunun süresi doldu") }
            try await sleep(interval)
        }
    }

    public func signOut() {
        reset()
        userToken = nil
        onUserToken(nil)
    }

    private func reset() {
        xblUser = nil
        xsts = [:]
        home = nil
    }

    /// Ev yayını hizmeti jetonu süresinden önce reddedildi (HTTP 401): bellekteki jetonlar bırakılır, sonraki istek
    /// yenilerini alır. Kullanıcı jetonu (yenileme jetonu) korunur; eskiden önbellekteki geçersiz jetonla her yeniden
    /// deneme 401 alıyor ve "yeniden giriş yapın" deyip duruyordu.
    public func invalidateHomeToken() {
        xblUser = nil
        xsts = [:]
        home = nil
    }

    /// Microsoft erişim jetonu; 60 sn'den az kaldıysa yenilenir.
    public func userAccessToken() async throws -> String {
        guard let current = userToken else { throw XboxError(.signInRequired, "Microsoft girişi gerekiyor") }
        if current.secondsValid(now: clock()) > Self.margin { return current.accessToken }
        guard !current.refreshToken.isEmpty else { throw XboxError(.signInRequired, "Microsoft girişi gerekiyor") }
        let response = try await http.request("POST", "\(Self.login)/token",
                                              headers: ["Content-Type": Self.form, "Cache-Control": "no-store, must-revalidate, no-cache"],
                                              body: formBody([("client_id", Self.clientId), ("grant_type", "refresh_token"),
                                                              ("refresh_token", current.refreshToken), ("scope", Self.scope)]))
        if response.status == 400 { throw XboxError(.signInRequired, "Microsoft girişinin süresi doldu") }
        let token = try XboxUserToken.fromResponse(json(response, "Microsoft jeton yenileme"), now: clock(), previous: current)
        userToken = token
        onUserToken(token)
        return token.accessToken
    }

    private func xblUserToken() async throws -> XboxXstsToken {
        if let xblUser, xblUser.secondsValid(now: clock()) > Self.margin { return xblUser }
        let access = try await userAccessToken()
        let body: JSON = ["Properties": ["AuthMethod": "RPS", "RpsTicket": "d=\(access)", "SiteName": "user.auth.xboxlive.com"],
                          "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"]
        let response = try await http.request("POST", "https://user.auth.xboxlive.com/user/authenticate", headers: [
            "x-xbl-contract-version": "1", "Cache-Control": "no-cache", "Content-Type": "application/json",
            "Origin": "https://www.xbox.com", "Referer": "https://www.xbox.com/"], body: jsonText(body))
        if response.status == 401 { throw XboxError(.signInRequired, "Xbox Live girişi kabul etmedi") }
        let token = try XboxXstsToken.parse(json(response, "Xbox Live kullanıcı jetonu"))
        xblUser = token
        return token
    }

    func xsts(_ relyingParty: String) async throws -> XboxXstsToken {
        if let cached = xsts[relyingParty], cached.secondsValid(now: clock()) > Self.margin { return cached }
        let user = try await xblUserToken()
        let body: JSON = ["Properties": ["SandboxId": "RETAIL", "UserTokens": [user.token]], "RelyingParty": relyingParty, "TokenType": "JWT"]
        let response = try await http.request("POST", "https://xsts.auth.xboxlive.com/xsts/authorize", headers: [
            "x-xbl-contract-version": "1", "Cache-Control": "no-cache", "Content-Type": "application/json",
            "Origin": "https://www.xbox.com", "Referer": "https://www.xbox.com/", "Accept": "*/*", "ms-cv": "0",
            "User-Agent": Self.browserAgent], body: jsonText(body))
        if response.status == 401 {
            let xerr = ((try? parseJSON(response.body))?["XErr"] as? NSNumber)?.int64Value ?? 0
            if Self.noAccountXErr.contains(xerr) { throw XboxError(.noXboxAccount, "Bu Microsoft hesabının Xbox profili yok (XErr \(xerr))") }
            throw XboxError(.signInRequired, "Xbox yetkisi verilmedi (XErr \(xerr))")
        }
        let token = try XboxXstsToken.parse(json(response, "XSTS"))
        xsts[relyingParty] = token
        return token
    }

    func homeEndpoint() async throws -> XboxHomeEndpoint {
        if let home, home.expiresAt > clock().addingTimeInterval(TimeInterval(Self.margin)) { return home }
        let gssv = try await xsts(Self.rpGssv)
        let response = try await http.request("POST", "https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", headers: [
            "Content-Type": "application/json", "Cache-Control": "no-store, must-revalidate, no-cache", "x-gssv-client": "XboxComBrowser"],
            body: jsonText(["token": gssv.token, "offeringId": "xhome"]))
        let endpoint = try XboxHomeEndpoint.parse(json(response, "Xbox ev yayını girişi"), now: clock())
        home = endpoint
        return endpoint
    }

    /// Konsola aktarım jetonu (`connect` için).
    public func transferToken() async throws -> String {
        _ = try await userAccessToken()
        guard let refresh = userToken?.refreshToken else { throw XboxError(.signInRequired, "Microsoft girişi gerekiyor") }
        let response = try await http.request("POST", "https://login.live.com/oauth20_token.srf", headers: ["Content-Type": Self.form], body: formBody([
            ("client_id", Self.clientId), ("scope", Self.transferScope), ("grant_type", "refresh_token"), ("refresh_token", refresh)]))
        if response.status == 400 { throw XboxError(.signInRequired, "Microsoft girişinin süresi doldu") }
        guard let lpt = try json(response, "Konsol aktarım jetonu")["access_token"] as? String, !lpt.isEmpty else {
            throw XboxError(.service, "Konsol aktarım jetonu gelmedi")
        }
        return lpt
    }

    private func json(_ response: XboxHTTPResponse, _ what: String) throws -> JSON {
        guard response.ok else { throw XboxError(.service, "\(what): HTTP \(response.status) \(response.text.prefix(300))") }
        return try parseJSON(response.body)
    }
}
