// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation

/// Android TV'de CouchSubs TV'yi Mac'in adresiyle açar (ADB açıksa; gömülü yardımcının `android-open` komutu). Ne zaman
/// açılacağı `AndroidTVOpenRule`'dadır: bu çeviride bağlanmış uygulama bir daha açılmaz, hiç bağlanmadıysa en çok üç kez,
/// 30 sn arayla; TV'de zaten çalışıyorsa (ekranı ya da katmanı) yardımcı `am start` göndermez. iPhone'daki AndroidTVKeeper,
/// Windows'taki AndroidTvKeeper ve Android telefondaki keepAndroidTvOpen ile aynı kural.
///
/// Eskiden Mac Android TV'ye hiç dokunmuyordu: çeviri başlayınca TV uygulaması kendiliğinden açılmıyor, kullanıcı TV'den
/// açması gerektiğini bilmiyordu. ADB kapalıysa ya da TV bu Mac'i onaylamadıysa sessizce geçilir (onay sorusu beklenmez);
/// nedeni ana ekranda söylenir. Yalnız sunucu adresi gider, TV yine ekrandaki kodun onayıyla (/pair) eşleşir.
final class AndroidTVKeeper: KeeperControlling, @unchecked Sendable {
    private let host: String
    private let launchParams: String?
    private let appConnected: @Sendable () -> Bool
    private let open: @Sendable (String, String?) async throws -> String
    private let onOpenResult: @Sendable (TVOpenProblem?) -> Void
    private let lock = NSLock()
    private var loop: Task<Void, Never>?
    private var rule: AndroidTVOpenRule
    private let origin = ContinuousClock.now
    private var lastResult: String?

    init(host: String, server: String, appConnected: @escaping @Sendable () -> Bool, relaunchInterval: Duration = .seconds(30),
         maxOpens: Int = AndroidTVOpenRule.defaultMaxOpens,
         open: @escaping @Sendable (String, String?) async throws -> String = AndroidTVKeeper.openWithHelper,
         onOpenResult: @escaping @Sendable (TVOpenProblem?) -> Void = { _ in }) {
        self.host = host
        launchParams = Self.launchParams(server: server)
        self.appConnected = appConnected
        rule = AndroidTVOpenRule(maxOpens: maxOpens, interval: Self.seconds(relaunchInterval))
        self.open = open
        self.onOpenResult = onOpenResult
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Yalnız sunucu adresi gider; erişim anahtarı gitmez (Android TV kullanıcı onaylı eşleştirmeyle bağlanır).
    static func launchParams(server: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["server": server], options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Kurulu uygulamayı gömülü yardımcıyla açar; TV onay sorarsa beklenmez (NotApproved), ADB kapalıysa Unreachable.
    /// Uygulama TV'de zaten çalışıyorsa yardımcı `am start` göndermez, `AndroidTVApp.alreadyRunning` döner.
    static let openWithHelper: @Sendable (String, String?) async throws -> String = { host, params in
        let result = try await TVHelper.run(["android-open", "--host", host,
                                             "--key-dir", TVHelper.dataDirectory.appendingPathComponent("adb").path]
                                            + (params.map { ["--params", $0] } ?? []))
        return result.version ?? ""
    }

    /// Açılamamanın nedeni: TV hata ayıklama iznini onaylamadıysa ayrı, gerisi "ulaşılamıyor".
    static func problem(_ error: Error) -> TVOpenProblem {
        (error as? DevModeFailure)?.error == .notApproved ? .debugNotApproved : .debugOff
    }

    /// Bir kontrol: `AndroidTVOpenRule` izin verirse açmayı dener.
    func tick(now: ContinuousClock.Instant = .now) async {
        guard !host.isEmpty else { return }
        let connected = appConnected()
        let elapsed = Self.seconds(now - origin)
        let due: Bool = lock.withLock { rule.shouldTry(connected: connected, now: elapsed) }
        guard due else { return }
        let result: String
        do {
            let output = try await open(host, launchParams)
            // Uygulama TV'de çalışırken bulunduysa `am start` gönderilmedi: açılış sayılmaz.
            if output != AndroidTVApp.alreadyRunning { lock.withLock { rule.opened() } }
            result = "açıldı: \(output)"
            onOpenResult(nil)
        } catch {
            result = "açılamadı: \(error)"
            onOpenResult(Self.problem(error))
        }
        // Aynı sonuç her denemede yeniden yazılmaz.
        let changed: Bool = lock.withLock {
            defer { lastResult = result }
            return lastResult != result
        }
        if changed { TVInstallLog.write("Android TV (\(host)) Mac'in adresiyle \(result)") }
    }

    func start(interval: Duration) {
        stop()
        loop = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Uykudan dönüşte ya da "Otomatik açmayı dene"de: sayaç sıfırlanır, sonraki kontrol beklemeden dener (uygulama bağlıysa
    /// ya da TV'de çalışıyorsa yine açılmaz).
    func reconnect() {
        lock.withLock { rule.reset() }
    }

    deinit { loop?.cancel() }
}
