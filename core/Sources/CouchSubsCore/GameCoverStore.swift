// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Oyun paketi kutularının kullanıcının seçtiği kapak resmi (Windows `GameCoverStore` ile aynı kural). Resim yalnız bu
/// bilgisayarın uygulama verisinde durur; hiçbir resim uygulamayla gelmez ya da internetten indirilmez.
public enum GameCoverStore {
    /// Her 128 piksellik PNG küçük resim en çok 2 MiB.
    public static let maxCoverBytes = 2 * 1024 * 1024

    /// ~/Library/Application Support/CouchSubs/covers
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CouchSubs", isDirectory: true).appendingPathComponent("covers", isDirectory: true)
    }

    /// Güvensiz ya da boş paket kimliği hiçbir zaman dosya yolu olmaz (yalnız a–z, 0–9 ve tire; tireyle başlamaz).
    public static func url(for packId: String?, in directory: URL = defaultDirectory) -> URL? {
        guard let packId, !packId.isEmpty, packId.count <= 120, packId.first != "-",
              packId.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { return nil }
        return directory.appendingPathComponent(packId + ".png")
    }

    public enum Failure: Error, Equatable { case invalidPackId, notPNG }

    /// Doğrulanmış PNG'yi atomik olarak yazar; hatalı girdi var olan kapağın yerine geçemez.
    public static func save(_ png: Data, for packId: String, in directory: URL = defaultDirectory) throws {
        guard let destination = url(for: packId, in: directory) else { throw Failure.invalidPackId }
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard png.count > signature.count, png.count <= maxCoverBytes, Array(png.prefix(signature.count)) == signature
        else { throw Failure.notPNG }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)
    }

    @discardableResult
    public static func remove(for packId: String, in directory: URL = defaultDirectory) -> Bool {
        guard let file = url(for: packId, in: directory), FileManager.default.fileExists(atPath: file.path) else { return false }
        return (try? FileManager.default.removeItem(at: file)) != nil
    }
}
