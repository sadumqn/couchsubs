// SPDX-License-Identifier: AGPL-3.0-only
@testable import CouchSubsCore
import XCTest

/// Cihaz yanıtı satırları: Swift'te "\r\n" tek Character, `split(separator: "\n")` onu bölmez (X'ten gelen Samsung
/// hatası: "TV kimliği (DUID) okunamadı; TV'nin yanıtı: XTCK7KNUEHTUM XTCK7KNUEHTUM").
final class DeviceLinesTests: XCTestCase {
    func testCrlfLfAndCrAllSplitTheDuidReply() {
        XCTAssertEqual("XTCK7KNUEHTUM\r\nXTCK7KNUEHTUM".deviceLines, ["XTCK7KNUEHTUM", "XTCK7KNUEHTUM"])
        XCTAssertEqual("XTCK7KNUEHTUM\nXTCK7KNUEHTUM\n".deviceLines, ["XTCK7KNUEHTUM", "XTCK7KNUEHTUM", ""])
        XCTAssertEqual("XTCK7KNUEHTUM\rXTCK7KNUEHTUM\r".deviceLines, ["XTCK7KNUEHTUM", "XTCK7KNUEHTUM", ""])
        XCTAssertEqual("\r\n\r\nXTCK7KNUEHTUM\r\n".deviceLines.first { !$0.isEmpty }, "XTCK7KNUEHTUM")
        // Eski yol CRLF'yi bölmüyordu; bu satır o farkı belgeler.
        XCTAssertEqual("A\r\nB".split(separator: "\n").count, 1)
    }

    func testCrlfPackageListSplitsIntoPackages() {
        let output = "package:com.google.android.tvlauncher\r\npackage:com.android.vending\r\n"
        XCTAssertEqual(output.deviceLines, ["package:com.google.android.tvlauncher", "package:com.android.vending", ""])
    }

    func testCrlfLunaRepliesAreReadLikeLf() {
        let progress = "{\"returnValue\":true,\"subscribed\":true}\r\n{\"details\":{\"state\":\"installing\"},\"returnValue\":true}\r\n"
        XCTAssertEqual(DevModeInstaller.parseInstallReplies(progress), .init())
        XCTAssertTrue(DevModeInstaller.parseInstallReplies(progress + "{\"details\":{\"state\":\"installed\"},\"returnValue\":true}\r\n").installed)
        XCTAssertTrue(DevModeInstaller.parseInstallReplies("Error: something\r\n{\"details\":\r\n{\"state\":\"installed\"}}\r\n").installed)
    }
}
