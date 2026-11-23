// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest
@testable import CouchSubs

extension XCTestCase {
    /// Test başına UserDefaults alanı: test bitince alan ve plist dosyası silinir. Önceden testlerin açtığı
    /// `UserDefaults(suiteName: UUID)` alanları kalıyor, kullanıcının `defaults domains` listesi doluyordu.
    func scratchDefaults(_ prefix: String = "CouchSubsTests") -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { fatalError("UserDefaults alanı açılamadı: \(name)") }
        addTeardownBlock { Self.discardDefaults(defaults, name: name) }
        return defaults
    }

    /// Alanı ve diskteki plist dosyasını siler.
    static func discardDefaults(_ defaults: UserDefaults, name: String) {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: preferencesFile(name))
    }

    static func preferencesFile(_ name: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences", isDirectory: true).appendingPathComponent("\(name).plist")
    }
}

/// Testler kullanıcının gerçek kurulum günlüğüne ve TV anahtarlarına yazmaz; açtıkları UserDefaults alanları iz bırakmaz.
final class TestIsolationTests: XCTestCase {
    func testInstallLogAndKeysGoToATemporaryFolder() {
        XCTAssertTrue(TVPaths.isTesting)
        XCTAssertNotEqual(TVPaths.root, TVPaths.userRoot)
        XCTAssertFalse(InstallLog.shared.file.path.hasPrefix(TVPaths.userRoot.path), "Testler gerçek tvinstall.log'a yazmaz")
        XCTAssertTrue(InstallLog.shared.file.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertFalse(TVPaths.directory("lg").path.hasPrefix(TVPaths.userRoot.path), "LG anahtarları gerçek klasöre yazılmaz")
    }

    func testDiscardedDefaultsLeaveNoDomainBehind() {
        let name = "CouchSubsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: "written")
        defaults.synchronize()
        Self.discardDefaults(defaults, name: name)
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: name), "Test bitince UserDefaults alanı silinir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.preferencesFile(name).path))
    }
}
