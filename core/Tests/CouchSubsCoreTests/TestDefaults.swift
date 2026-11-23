// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest

/// Testlerin açtığı UserDefaults alanları. Önceden her test `UserDefaults(suiteName: "…-<UUID>")` açıp bırakıyordu;
/// geliştiricinin Mac'inde `defaults domains` onlarca artık alanla doluyordu. Burada açılan her alan test paketi bitince
/// silinir: `removePersistentDomain` ve ~/Library/Preferences'taki plist dosyası.
enum TestDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String] = []
    nonisolated(unsafe) private static var observing = false

    static func make(_ prefix: String) -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        let register = lock.withLock { () -> Bool in
            names.append(name)
            defer { observing = true }
            return !observing
        }
        if register { XCTestObservationCenter.shared.addTestObserver(Cleaner()) }
        return UserDefaults(suiteName: name)!
    }

    /// Açılan bütün alanları siler (paket sonunda kendiliğinden çağrılır).
    static func cleanUp() {
        let all = lock.withLock { () -> [String] in
            defer { names = [] }
            return names
        }
        for name in all { remove(name) }
    }

    static func remove(_ name: String) {
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        UserDefaults.standard.removePersistentDomain(forName: name)
        // cfprefsd boş alanı da dosyaya yazar; önce yazdırılır, sonra dosya silinir.
        defaults?.synchronize()
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(at: plist(name))
    }

    static func plist(_ name: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(name).plist")
    }

    static var openNames: [String] { lock.withLock { names } }

    private final class Cleaner: NSObject, XCTestObservation {
        func testBundleDidFinish(_ testBundle: Bundle) { TestDefaults.cleanUp() }
    }
}

final class TestDefaultsTests: XCTestCase {
    func testOpenedDomainIsRemoved() throws {
        let defaults = TestDefaults.make("couchsubs-defaults-check")
        defaults.set(1, forKey: "x")
        let name = try XCTUnwrap(TestDefaults.openNames.last)
        TestDefaults.remove(name)
        XCTAssertTrue((UserDefaults.standard.persistentDomain(forName: name) ?? [:]).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: TestDefaults.plist(name).path))
    }

    /// Hiçbir test kendi başına kalıcı UserDefaults alanı açmaz; hepsi `TestDefaults.make` ile açılır ve silinir.
    func testNoTestOpensUnmanagedDefaultsSuite() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "TestDefaults.swift" }
        let offenders = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("UserDefaults(suiteName:") }
        XCTAssertEqual(offenders.map(\.lastPathComponent), [])
    }
}
