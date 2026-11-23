// SPDX-License-Identifier: AGPL-3.0-only

import CoreFoundation
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct GamePackImportPreview: Sendable {
    public let suggestedTitle: String?
    public let entries: [String: String]
    public let invalidCount: Int
    public let duplicateCount: Int
    public let conflictCount: Int
}

public enum GamePackImporter {
    public enum ImportError: Error, Equatable {
        case unsupportedFileType, invalidUTF8, invalidJSON, unsupportedPackFormat
        case blankTitle, emptyPack, destinationExists, sourceIsDestination, fileTooLarge
    }

    /// Içe aktarılan çeviri dosyası için üst sınır (bellek taşmasını önler).
    public static let maxFileBytes = 64 * 1024 * 1024

    /// URL'den en çok `maxFileBytes` okur; sağlayıcı boyut bildirmese veya dosya okuma sırasında büyüse de belleği sınırlar.
    public static func read(fileAt url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        while true {
            let remaining = maxFileBytes - data.count + 1
            let chunk = try handle.read(upToCount: min(64 * 1024, remaining))
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maxFileBytes else { throw ImportError.fileTooLarge }
        }
        return data
    }

    public static func parse(_ data: Data, fileName: String) throws -> GamePackImportPreview {
        guard data.count <= maxFileBytes else { throw ImportError.fileTooLarge }
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data
        guard let source = String(data: bytes, encoding: .utf8) else { throw ImportError.invalidUTF8 }

        var pairs = Pairs()
        var title: String?
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "json":
            title = try parseJSON(bytes, into: &pairs)
        case "txt":
            parseText(lines(source), into: &pairs)
        case "srt":
            parseSRT(lines(source), into: &pairs)
        default:
            throw ImportError.unsupportedFileType
        }
        return GamePackImportPreview(suggestedTitle: title, entries: pairs.entries, invalidCount: pairs.invalidCount,
                                     duplicateCount: pairs.duplicateCount, conflictCount: pairs.conflicts.count)
    }

    public static func makeID(title: String) -> String {
        var slug: [UInt8] = []
        var gap = false
        for byte in title.utf8 {
            let letter: UInt8
            switch byte {
            case 65...90: letter = byte + 32
            case 97...122, 48...57: letter = byte
            default:
                gap = !slug.isEmpty
                continue
            }
            if slug.count + (gap ? 2 : 1) > 80 { break }
            if gap { slug.append(45) }
            slug.append(letter)
            gap = false
        }
        return "community-" + (slug.isEmpty ? "game" : String(decoding: slug, as: UTF8.self))
    }

    @discardableResult
    public static func install(_ preview: GamePackImportPreview, title: String, directory: URL, replacing: Bool,
                               sourceURL: URL? = nil) throws -> URL {
        guard let title = nonblank(title) else { throw ImportError.blankTitle }
        guard !preview.entries.isEmpty else { throw ImportError.emptyPack }
        let id = makeID(title: title)
        let destination = directory.appendingPathComponent(id + ".json")
        if let sourceURL, sameFile(sourceURL, destination) { throw ImportError.sourceIsDestination }
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let pack = InstalledPack(id: id, title: title, entries: preview.entries)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        try JSONEncoder().encode(pack).write(to: temporary, options: .withoutOverwriting)
        // A link publishes the complete file and fails if the name already exists.
        // rename publishes the complete file while replacing the old name atomically.
        let failure = temporary.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { return EINVAL }
                let result = replacing ? rename(source, target) : link(source, target)
                return result == 0 ? 0 : errno
            }
        }
        if !replacing, failure == EEXIST { throw ImportError.destinationExists }
        if failure != 0 { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
        return destination
    }

    private static func sameFile(_ source: URL, _ destination: URL) -> Bool {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        if source.path == destination.path { return true }
        // The same file may have a different spelling on a case-insensitive volume.
        guard let sourceID = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let destinationID = try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else {
            return false
        }
        return sourceID.isEqual(destinationID)
    }

    private struct InstalledPack: Encodable {
        let format = 1
        let id: String
        let title: String
        let entries: [String: String]
    }

    private struct Pairs {
        var entries: [String: String] = [:]
        var invalidCount = 0
        var duplicateCount = 0
        // Retain every distinct target for conflicted keys to count subsequent repeats.
        var conflicts: [String: Set<Data>] = [:]

        mutating func add(key: String?, target: String?) {
            guard let key, let target = GamePackImporter.nonblank(target) else {
                invalidCount += 1
                return
            }
            if conflicts[key] != nil {
                if !conflicts[key, default: []].insert(Data(target.utf8)).inserted { duplicateCount += 1 }
            } else if let earlier = entries[key] {
                if earlier.utf8.elementsEqual(target.utf8) {
                    duplicateCount += 1
                } else {
                    conflicts[key] = [Data(earlier.utf8), Data(target.utf8)]
                    entries[key] = nil
                }
            } else {
                entries[key] = target
            }
        }
    }

    private static func nonblank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func parseJSON(_ data: Data, into pairs: inout Pairs) throws -> String? {
        let object = try OrderedJSONObject.decode(data)
        let format = object["format"] as? NSNumber
        if let format, CFGetTypeID(format) != CFBooleanGetTypeID() {
            guard format == 1 else { throw ImportError.unsupportedPackFormat }
            guard let entries = OrderedJSONObject(object["entries"]) else { throw ImportError.invalidJSON }
            for (key, target) in entries.members { pairs.add(key: hashedKey(key), target: target as? String) }
            return nonblank(object["title"] as? String) ?? nonblank(object["game"] as? String)
        }
        if OrderedJSONObject(object["entries"]) != nil { throw ImportError.unsupportedPackFormat }
        if let subtitles = OrderedJSONObject(object["subtitles"]) {
            for (source, target) in subtitles.members { pairs.add(key: PackKey.key(source), target: target as? String) }
            return nonblank(object["game"] as? String) ?? nonblank(object["title"] as? String)
        }
        for (source, target) in object.members { pairs.add(key: PackKey.key(source), target: target as? String) }
        return nil
    }

    private struct OrderedJSONObject {
        let members: [(name: String, value: Any)]

        init?(_ value: Any?) {
            guard let list = value as? [Any], list.first as? Bool == true, list.count % 2 == 1 else { return nil }
            members = stride(from: 1, to: list.count, by: 2).compactMap { index in
                guard let name = list[index] as? String else { return nil }
                return (name, list[index + 1])
            }
        }

        subscript(_ name: String) -> Any? {
            members.last { $0.name == name }?.value
        }

        static func decode(_ data: Data) throws -> Self {
            // First validate the original syntax, including colons and commas.
            // Foundation decodes objects as dictionaries. Decode a second time
            // with each object represented as [true, key, value, ...] to retain
            // every member. Input arrays carry a false tag so they stay distinct.
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any],
                  let value = try? JSONSerialization.jsonObject(with: orderedRepresentation(data)),
                  let object = Self(value) else {
                throw ImportError.invalidJSON
            }
            return object
        }

        private static func orderedRepresentation(_ data: Data) -> Data {
            var result = Data()
            result.reserveCapacity(data.count)
            var inString = false
            var escaped = false
            var afterTag = false
            for byte in data {
                if inString {
                    result.append(byte)
                    if escaped { escaped = false }
                    else if byte == UInt8(ascii: "\\") { escaped = true }
                    else if byte == UInt8(ascii: "\"") { inString = false }
                    continue
                }
                if afterTag {
                    switch byte {
                    case 0x20, 0x09, 0x0a, 0x0d: continue
                    case UInt8(ascii: "}"), UInt8(ascii: "]"): break
                    default: result.append(UInt8(ascii: ","))
                    }
                    afterTag = false
                }
                switch byte {
                case UInt8(ascii: "{"):
                    result.append(contentsOf: "[true".utf8)
                    afterTag = true
                case UInt8(ascii: "["):
                    result.append(contentsOf: "[false".utf8)
                    afterTag = true
                case UInt8(ascii: "}"): result.append(UInt8(ascii: "]"))
                case UInt8(ascii: ":"): result.append(UInt8(ascii: ","))
                case UInt8(ascii: "\""):
                    inString = true
                    result.append(byte)
                default: result.append(byte)
                }
            }
            return result
        }
    }

    private static func hashedKey(_ key: String) -> String? {
        guard key.utf8.count == 16,
              key.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return key.lowercased()
    }

    private static func lines(_ source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func parseText(_ lines: [String], into pairs: inout Pairs) {
        for line in lines {
            guard let trimmed = nonblank(line), !trimmed.hasPrefix("#") else { continue }
            let tabFields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if tabFields.count == 2 {
                pairs.add(key: PackKey.key(String(tabFields[0])), target: String(tabFields[1]))
            } else if tabFields.count == 1, let delimiter = line.range(of: " = ") {
                pairs.add(key: PackKey.key(String(line[..<delimiter.lowerBound])), target: String(line[delimiter.upperBound...]))
            } else {
                pairs.invalidCount += 1
            }
        }
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"\A[0-9]{2}:[0-5][0-9]:[0-5][0-9],[0-9]{3}\z"#)

    private static func validTiming(_ line: String) -> Bool {
        let times = line.components(separatedBy: " --> ")
        // Fixed widths make the chronological order the same as the string order.
        return times.count == 2 && times[0] < times[1] && times.allSatisfy {
            timestamp.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
        }
    }

    private static func parseSRT(_ lines: [String], into pairs: inout Pairs) {
        var cue: [String] = []
        func finishCue() {
            guard !cue.isEmpty else { return }
            defer { cue.removeAll(keepingCapacity: true) }
            guard cue.count == 4, cue[0].utf8.allSatisfy({ (48...57).contains($0) }), validTiming(cue[1]) else {
                pairs.invalidCount += 1
                return
            }
            pairs.add(key: PackKey.key(cue[2]), target: cue[3])
        }
        for line in lines {
            if let text = nonblank(line) { cue.append(text) } else { finishCue() }
        }
        finishCue()
    }
}
