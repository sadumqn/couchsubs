// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// Önceki çalışmanın çökme raporu: yalnız CouchSubs'ın, önceki açılıştan sonra yazılmış raporu bir kez bildirilir.
final class CrashReportsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("couchsubs-cokme-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func write(_ name: String, created: Date) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("{\"app_name\":\"CouchSubs\",\"bug_type\":\"309\"}\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        return url
    }

    func testOnlyCouchSubsCrashReportsCount() {
        XCTAssertTrue(CrashReports.isCrashReport("CouchSubs-2026-11-21-031500.ips"))
        XCTAssertTrue(CrashReports.isCrashReport("CouchSubs-2026-11-21-031500.crash"))
        XCTAssertFalse(CrashReports.isCrashReport("CouchSubs_2026-11-21-031500_Mac.cpu_resource.diag"))
        XCTAssertFalse(CrashReports.isCrashReport("CouchSubs-2026-11-21-031500.hang"))
        XCTAssertFalse(CrashReports.isCrashReport("CouchSubsAppStore-2026-11-21-031500.ips"))
        XCTAssertFalse(CrashReports.isCrashReport("dotnet-2026-11-21-004847.ips"))
    }

    func testNewestReportSinceTheLastLaunchIsPending() throws {
        let lastLaunch = Date(timeIntervalSince1970: 1_800_000_000)
        try write("CouchSubs-2026-11-19-120000.ips", created: lastLaunch.addingTimeInterval(-3600))
        try write("CouchSubs-2026-11-20-044644.ips", created: lastLaunch.addingTimeInterval(1800))
        let newest = try write("CouchSubs-2026-11-20-050000.ips", created: lastLaunch.addingTimeInterval(2400))
        try write("chronod-2026-11-20-051000.ips", created: lastLaunch.addingTimeInterval(3000))

        XCTAssertEqual(CrashReports.pending(in: folder, since: lastLaunch)?.lastPathComponent, newest.lastPathComponent)
        // Önceki açılış bilinmiyorsa eski raporlar "geçen sefer" diye bildirilmez.
        XCTAssertNil(CrashReports.pending(in: folder, since: nil))
        // Rapor yoksa ya da klasör okunamıyorsa bildirim yok.
        XCTAssertNil(CrashReports.pending(in: folder, since: lastLaunch.addingTimeInterval(7200)))
        XCTAssertNil(CrashReports.pending(in: folder.appendingPathComponent("yok"), since: lastLaunch))
    }

    func testReportIsOfferedOnceAtTheNextLaunch() throws {
        let defaults = UserDefaults.isolated()
        let firstLaunch = Date(timeIntervalSince1970: 1_800_000_000)
        try write("CouchSubs-2026-11-19-120000.ips", created: firstLaunch.addingTimeInterval(-3600))

        // İlk açılış: önceden kalan rapor bildirilmez.
        XCTAssertNil(CrashReports.checkAtLaunch(defaults: defaults, directory: folder, now: firstLaunch))
        // Uygulama çöktü; sonraki açılış raporu bildirir.
        try write("CouchSubs-2026-11-20-044644.ips", created: firstLaunch.addingTimeInterval(1800))
        let second = firstLaunch.addingTimeInterval(3600)
        XCTAssertEqual(CrashReports.checkAtLaunch(defaults: defaults, directory: folder, now: second)?.lastPathComponent,
                       "CouchSubs-2026-11-20-044644.ips")
        // Aynı rapor bir daha bildirilmez.
        XCTAssertNil(CrashReports.checkAtLaunch(defaults: defaults, directory: folder, now: second.addingTimeInterval(3600)))
    }
}
