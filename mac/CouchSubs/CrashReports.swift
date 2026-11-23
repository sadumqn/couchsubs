// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI

/// Önceki çalışmanın çökme raporu. macOS çöken her uygulama için ~/Library/Logs/DiagnosticReports klasörüne rapor
/// yazar; uygulama açılışta önceki açılıştan bu yana yazılmış CouchSubs raporu var mı diye bakar ve ana ekranda bir
/// kez bildirir (Windows'taki çökme kaydının karşılığı, windows/src/CouchSubs.Core/CrashRecords.cs). CouchSubs raporu
/// hiçbir yere göndermez: kullanıcı Finder'da görür ya da metnini kopyalar. Mac App Store sürümü (sandbox) bu klasörü
/// okuyamaz; orada bildirim çıkmaz.
enum CrashReports {
    static let lastLaunchKey = "crashReports.lastLaunch"

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    /// Çökme raporu mu: "CouchSubs-2026-11-21-031500.ips" (eski macOS'ta .crash). Takılma ve kaynak raporları
    /// (.hang, .diag, .spin) ile başka süreçlerin (ör. CouchSubsAppStore) raporları sayılmaz.
    static func isCrashReport(_ name: String, processName: String = "CouchSubs") -> Bool {
        (name.hasSuffix(".ips") || name.hasSuffix(".crash")) && name.hasPrefix(processName + "-")
    }

    /// `lastLaunch`'tan sonra yazılmış en yeni çökme raporu. Önceki açılış bilinmiyorsa (ilk açılış) nil: eski raporlar
    /// "geçen sefer" diye bildirilmez.
    static func pending(in directory: URL, since lastLaunch: Date?, fileManager: FileManager = .default) -> URL? {
        guard let lastLaunch else { return nil }
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey],
                                                         options: [.skipsHiddenFiles])) ?? []
        return files.compactMap { url -> (url: URL, created: Date)? in
            guard isCrashReport(url.lastPathComponent),
                  let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                  created > lastLaunch else { return nil }
            return (url, created)
        }
        .max { $0.created < $1.created }?.url
    }

    /// Açılışta bir kez çağrılır: önceki açılıştan bu yana yazılmış raporu döndürür ve bu açılışı kaydeder; aynı rapor
    /// sonraki açılışta yeniden bildirilmez.
    static func checkAtLaunch(defaults: UserDefaults = .standard, directory: URL = CrashReports.directory, now: Date = Date()) -> URL? {
        let lastLaunch = defaults.object(forKey: lastLaunchKey) as? Date
        defaults.set(now, forKey: lastLaunchKey)
        guard !Distribution.isAppStore else { return nil }
        return pending(in: directory, since: lastLaunch)
    }
}

/// Ana ekranda gösterilecek çökme raporu (yoksa nil).
@MainActor
final class CrashNotice: ObservableObject {
    static let shared = CrashNotice()

    @Published var report: URL?
    private var checked = false

    /// Uygulama açılışında bir kez bakar; testlerde bakmaz.
    func checkOnce() {
        guard !checked, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        checked = true
        report = CrashReports.checkAtLaunch()
    }
}

/// "CouchSubs geçen sefer beklenmedik biçimde kapandı": raporu Finder'da gösterir ya da metnini kopyalar.
struct CrashReportCard: View {
    @ObservedObject private var notice = CrashNotice.shared
    @State private var copied = false

    var body: some View {
        if let report = notice.report {
            Card {
                Label("CouchSubs closed unexpectedly last time.", systemImage: "exclamationmark.triangle")
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(Color.csWarning)
                HintText(text: "macOS saved a crash report on this Mac. CouchSubs does not send it anywhere; you can add it when you report the problem.")
                HStack(spacing: Theme.space("m")) {
                    Button("Show crash record") { NSWorkspace.shared.activateFileViewerSelecting([report]) }
                        .buttonStyle(.secondary)
                    Button(copied ? "Copied" : "Copy") {
                        guard let text = try? String(contentsOf: report, encoding: .utf8) else { return }
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.secondary)
                    Button("Close") { notice.report = nil }
                        .buttonStyle(.secondary)
                }
            }
        }
    }
}
