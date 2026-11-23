// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import Foundation

/// Üst çubuktaki "Günlüğü Kopyala": ~/Library/Logs/CouchSubs içindeki güncel günlükler (altyazi.log, remoteplay.log,
/// tvinstall.log ve diğer .log dosyaları, varsa .1 yedekleri) maskelenerek (LogShare.redact: hesap kimliği, jeton,
/// anahtar, parola, passphrase) tek zip'e konur; zip dosyası panoya dosya olarak kopyalanır (GitHub, Mail, X'e yapışır).
/// Çok büyük günlüğün yalnız son 2 MB'ı alınır.
enum LogArchive {
    /// Her günlükten alınan en çok bayt (dosyanın sonu).
    static let maxBytesPerLog = 2_000_000
    /// Bu kadar günden eski günlük alınmaz.
    static let maxAge: TimeInterval = 14 * 24 * 3600

    static var logsFolder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/CouchSubs", isDirectory: true)
    }

    /// "CouchSubs-gunluk-20261122-1830.zip"
    static func fileName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "CouchSubs-gunluk-\(formatter.string(from: date)).zip"
    }

    /// Günlükleri maskeleyip `folder` içine zip olarak yazar; zip'in adresini döner.
    static func make(from source: URL = logsFolder, into folder: URL = FileManager.default.temporaryDirectory,
                     header: String, now: Date = Date()) throws -> URL {
        let manager = FileManager.default
        let staging = folder.appendingPathComponent("CouchSubs-gunluk-\(UUID().uuidString)", isDirectory: true)
        let content = staging.appendingPathComponent("CouchSubs-gunluk", isDirectory: true)
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        try Data((header + "\n").utf8).write(to: content.appendingPathComponent("bilgi.txt"))
        for file in logs(in: source, now: now) {
            guard let text = tail(file) else { continue }
            try Data(LogShare.redact(text).utf8).write(to: content.appendingPathComponent(file.lastPathComponent))
        }
        let target = folder.appendingPathComponent(fileName(now))
        try? manager.removeItem(at: target)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", content.path, target.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0, manager.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return target
    }

    /// Güncel günlük dosyaları (.log ve .log.1), ada göre sıralı.
    static func logs(in folder: URL, now: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { file in
            let name = file.lastPathComponent
            guard name.hasSuffix(".log") || name.hasSuffix(".log.1") else { return false }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return false }
            return now.timeIntervalSince(values?.contentModificationDate ?? .distantPast) <= maxAge
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Dosyanın son `maxBytesPerLog` baytı; kesilen ilk satır atılır.
    static func tail(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytesPerLog) ? size - UInt64(maxBytesPerLog) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return text
    }

    /// Zip dosyasını panoya dosya olarak koyar.
    static func copyToPasteboard(_ file: URL, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
    }
}
