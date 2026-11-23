// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kullanım verisi (Ayarlar › Kullanım verisi, varsayılan açık): telefonlardaki Firebase Analytics olaylarının aynısı
/// Google Analytics 4 Measurement Protocol ile (HTTPS POST) gönderilir. Kimlik olarak kuruluma özgü rastgele bir UUID
/// (`usage-id` dosyası) kullanılır; altyazı metni, görüntü, PSN/Microsoft hesabı ve anahtarlar hiçbir olayda yoktur.
/// Ölçüm kimliği ve API sırrı derlemeden gelir (CI sırları `GA_MEASUREMENT_ID`, `GA_API_SECRET`); yoksa (`config` nil)
/// hiçbir şey kuyruğa girmez, hiçbir istek gitmez. Olaylar bellekte birikir, dakikada bir (ve uygulama kapanırken)
/// 25'lik parçalar hâlinde arka planda gönderilir; ağ hatasında sessizce sonraki tura kalır. `record` yalnız kilit altında
/// diziye ekler: çeviri hattını yavaşlatmaz. Kapatılınca kuyruk silinir.
/// Windows'taki CouchSubs.Core/UsageStats.cs ile aynı olaylar ve gövde (ortak deneme: Fixtures/usage-stats.json).
public final class UsageStats: @unchecked Sendable {
    public static let enabledByDefault = true
    public static let endpoint = "https://www.google-analytics.com/mp/collect"
    /// Measurement Protocol bir istekte en çok 25 olay alır.
    public static let batchSize = 25
    /// Gönderilemeyen olaylardan en çok bu kadarı bellekte bekler (en eskiler düşer).
    public static let maxQueue = 200
    public static let flushInterval: TimeInterval = 60

    /// Ölçüm kimliği (G-…) ve Measurement Protocol API sırrı; biri boşsa ölçüm kapalı.
    public struct Config: Equatable, Sendable {
        public let measurementID: String
        public let apiSecret: String

        public init?(measurementID: String?, apiSecret: String?) {
            let id = measurementID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let secret = apiSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Derleme ayarı verilmediyse Info.plist'te "$(GA_MEASUREMENT_ID)" gibi açılmamış değer kalabilir.
            guard !id.isEmpty, !secret.isEmpty, !id.contains("$("), !secret.contains("$(") else { return nil }
            self.measurementID = id
            self.apiSecret = secret
        }
    }

    public enum Value: Equatable, Sendable {
        case string(String)
        case number(Int)

        var json: Any {
            switch self {
            case .string(let value): value
            case .number(let value): value
            }
        }
    }

    /// Telefonlardaki olaylarla aynı adlar ve alanlar (Android Telemetry, iPhone AnalyticsEvent).
    public struct Event: Equatable, Sendable {
        public let name: String
        public let params: [String: Value]

        public init(name: String, params: [String: Value] = [:]) {
            self.name = name
            self.params = params
        }

        /// Açılan ekran. Firebase'in `screen_view` adı Measurement Protocol'de ayrılmış olduğundan web akışının
        /// "Sayfalar ve ekranlar" raporunu dolduran `page_view` gider; ekranın adı `screen_name` ve `page_title`'dadır.
        public static func screen(_ name: String) -> Event {
            Event(name: "page_view", params: ["screen_name": .string(name), "page_title": .string(name),
                                              "page_location": .string("app://couchsubs/" + name)])
        }

        /// Kurulum bitti; altyazının hedefi (tv, computer, both) ve konsol türü (ps5, xbox).
        public static func onboardingDone(target: String, console: String) -> Event {
            Event(name: "onboarding_done", params: ["target": .string(target), "console": .string(console)])
        }

        /// Çeviri başladı: hedef, çeviri motoru, paketler açık mı, konsol türü.
        public static func sessionStart(target: String, engine: String, packs: Bool, console: String) -> Event {
            Event(name: "subtitle_session_start", params: ["target": .string(target), "engine": .string(engine),
                                                           "packs": .string(packs ? "true" : "false"), "console": .string(console)])
        }

        /// Çeviri bitti: süre (saniye), gösterilen satır sayısı, bunlardan hazır paketten gelenler.
        public static func sessionStop(seconds: Int, lines: Int, packLines: Int) -> Event {
            Event(name: "subtitle_session_stop", params: ["seconds": .number(seconds), "lines": .number(lines),
                                                          "pack_lines": .number(packLines)])
        }

        /// TV uygulaması bağlandı: bağlı TV sayısı ve markası (lg, samsung, androidTV).
        public static func tvConnected(count: Int, brand: String) -> Event {
            Event(name: "tv_connected", params: ["count": .number(count), "brand": .string(brand)])
        }

        /// Oturumda ilk kez satır gelen oyun paketi (kimliği, ör. gta6).
        public static func packHit(_ pack: String) -> Event {
            Event(name: "pack_hit", params: ["pack": .string(pack)])
        }
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let config: Config?
    private let idFile: URL
    private let userProperties: [String: String]
    private let sessionID: String
    private let send: Send
    private let lock = NSLock()
    private var queue: [Event] = []
    private var enabled: Bool
    private var flushing = false
    private var clientID: String?

    /// - Parameters:
    ///   - config: nil ise (derlemede kimlik yok, Mac App Store, testler) hiçbir şey yapılmaz.
    ///   - idFile: kuruluma özgü rastgele kimliğin dosyası; ilk gönderimde oluşturulur.
    public init(config: Config?, enabled: Bool = UsageStats.enabledByDefault, idFile: URL, appVersion: String,
                osVersion: String, platform: String, now: Date = Date(),
                send: @escaping Send = { try await URLSession.shared.data(for: $0) }) {
        self.config = config
        self.enabled = enabled
        self.idFile = idFile
        userProperties = ["app_version": appVersion, "os_version": osVersion, "platform": platform]
        sessionID = String(Int(now.timeIntervalSince1970))
        self.send = send
    }

    /// Derlemede ölçüm kimliği var mı (yoksa ayar ve bilgi notu gösterilmez).
    public var isConfigured: Bool { config != nil }
    public var isEnabled: Bool { lock.withLock { enabled } }
    public var queued: [Event] { lock.withLock { queue } }

    /// Kapatılınca bekleyen olaylar da silinir: kullanıcı vazgeçtiyse hiçbir şey gitmez.
    public func setEnabled(_ value: Bool) {
        lock.withLock {
            enabled = value
            if !value { queue.removeAll() }
        }
    }

    /// Olayı kuyruğa ekler; kapalıysa ya da yapılandırılmadıysa bir şey yapmaz. Ağa çıkmaz.
    public func record(_ event: Event) {
        guard config != nil else { return }
        lock.withLock {
            guard enabled else { return }
            queue.append(event)
            if queue.count > Self.maxQueue { queue.removeFirst(queue.count - Self.maxQueue) }
        }
    }

    /// Kuyruğu 25'lik parçalar hâlinde gönderir. Ağ hatasında ya da 5xx'te kuyruk kalır; başka yanıtta parça atılır
    /// (Measurement Protocol hatalı olayı da 2xx ile yanıtlar, yeniden göndermek düzeltmez).
    public func flush() async {
        guard let config else { return }
        guard lock.withLock({ () -> Bool in
            guard !flushing else { return false }
            flushing = true
            return true
        }) else { return }
        defer { lock.withLock { flushing = false } }
        while true {
            let batch: [Event] = lock.withLock { enabled ? Array(queue.prefix(Self.batchSize)) : [] }
            guard !batch.isEmpty, let url = Self.url(config) else { return }
            let client = loadClientID()
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.payload(clientID: client, sessionID: sessionID, userProperties: userProperties, events: batch)
            guard let reply = try? await send(request), let http = reply.1 as? HTTPURLResponse, http.statusCode < 500 else { return }
            lock.withLock {
                // Bu arada kapatıldıysa kuyruk zaten boştur.
                let sent = min(batch.count, queue.count)
                if sent > 0, Array(queue.prefix(sent)) == Array(batch.prefix(sent)) { queue.removeFirst(sent) }
            }
        }
    }

    /// İsteğin adresi: ölçüm kimliği ve API sırrı sorgu dizesinde.
    public static func url(_ config: Config) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let id = config.measurementID.addingPercentEncoding(withAllowedCharacters: allowed),
              let secret = config.apiSecret.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(endpoint)?measurement_id=\(id)&api_secret=\(secret)")
    }

    /// Measurement Protocol gövdesi. Her olaya oturum kimliği (uygulamanın açıldığı an) ve etkileşim süresi eklenir; reklam
    /// kişiselleştirmesi ve reklam verisi her zaman reddedilir.
    public static func payload(clientID: String, sessionID: String, userProperties: [String: String], events: [Event]) -> Data {
        let body: [String: Any] = [
            "client_id": clientID,
            "non_personalized_ads": true,
            "consent": ["ad_user_data": "DENIED", "ad_personalization": "DENIED"],
            "user_properties": userProperties.mapValues { ["value": $0] },
            "events": events.map { event -> [String: Any] in
                var params = event.params.mapValues(\.json)
                params["session_id"] = sessionID
                params["engagement_time_msec"] = 100
                return ["name": event.name, "params": params]
            },
        ]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    private func loadClientID() -> String {
        if let clientID = lock.withLock({ self.clientID }) { return clientID }
        let saved = (try? String(contentsOf: idFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if let saved, UUID(uuidString: saved) != nil {
            id = saved
        } else {
            id = UUID().uuidString.lowercased()
            try? FileManager.default.createDirectory(at: idFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? id.write(to: idFile, atomically: true, encoding: .utf8)
        }
        lock.withLock { clientID = id }
        return id
    }
}
