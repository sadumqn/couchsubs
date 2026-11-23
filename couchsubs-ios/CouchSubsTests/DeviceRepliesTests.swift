// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubs

/// TV yanıtları CRLF, LF ya da CR ile gelebilir; Swift'te "\r\n" tek Character olduğundan ayrıca denenir.
final class DeviceRepliesTests: XCTestCase {
    func testDuidIsReadFromCrlfLfAndCrReplies() {
        XCTAssertEqual(SamsungInstaller.duid(fromGetduid: "XTCK7KNUEHTUM\r\nXTCK7KNUEHTUM"), "XTCK7KNUEHTUM")
        XCTAssertEqual(SamsungInstaller.duid(fromGetduid: "XTCK7KNUEHTUM\nXTCK7KNUEHTUM\n"), "XTCK7KNUEHTUM")
        XCTAssertEqual(SamsungInstaller.duid(fromGetduid: "XTCK7KNUEHTUM\rXTCK7KNUEHTUM\r"), "XTCK7KNUEHTUM")
        XCTAssertEqual(SamsungInstaller.duid(fromGetduid: "\r\nXTCK7KNUEHTUM\r\n"), "XTCK7KNUEHTUM")
        XCTAssertNil(SamsungInstaller.duid(fromGetduid: ""))
        XCTAssertNil(SamsungInstaller.duid(fromGetduid: "error: closed\r\n"))
    }

    func testPlayStoreIsFoundInCrlfPackageList() {
        XCTAssertTrue(AndroidTvInstaller.hasPlayStore("package:com.google.android.tvlauncher\r\npackage:com.android.vending\r\n"))
        XCTAssertTrue(AndroidTvInstaller.hasPlayStore("package:com.android.vending\n"))
        XCTAssertFalse(AndroidTvInstaller.hasPlayStore("package:com.google.android.tvlauncher\r\n"))
    }

    func testCapabilityAndSummaryReadCrlf() {
        let capability = SdbConnection.parseCapability([0, 0] + Array("secure_protocol:enabled\r\nsdbd_rootperm:disabled\r\n".utf8))
        XCTAssertEqual(capability["secure_protocol"], "enabled")
        XCTAssertEqual(capability["sdbd_rootperm"], "disabled")
        XCTAssertEqual(SamsungDiagnostics.summary("ok\r\ninstall failed\r\nreason: space\r\n"), "install failed | reason: space")
    }
}
