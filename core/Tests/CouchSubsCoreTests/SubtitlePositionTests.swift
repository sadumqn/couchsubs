// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// "Altyazıyı konumlandır" (Mac penceresi) ve "Bu telefonda" ekranındaki parmakla yer ve yazı boyu.
final class SubtitlePositionTests: XCTestCase {
    private let main = OverlayFrameMemory.Display(id: 1, name: "Yerleşik Retina Ekran", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    private let second = OverlayFrameMemory.Display(id: 7, name: "DELL U2723QE", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

    func testRemembersTheScreenAndPlaceOnIt() throws {
        let memory = try XCTUnwrap(OverlayFrameMemory(frame: CGRect(x: 1712.4, y: 100, width: 1400, height: 600), baseHeight: 400, displays: [main, second]))
        XCTAssertEqual(memory.screenID, 7)
        XCTAssertEqual(memory.screenName, "DELL U2723QE")
        XCTAssertEqual(memory.x, 200)
        XCTAssertEqual(memory.heightScale, 1.5)
        XCTAssertEqual(memory.frame(baseHeight: 400, displays: [main, second]), CGRect(x: 1712, y: 100, width: 1400, height: 600))
    }

    /// Ekranlar yer değiştirdi ya da kimlik değişti (yeniden başlatma): aynı ekran adıyla bulunur, ona göre yerleşir.
    func testFollowsTheScreenWhenItMovesOrItsIDChanges() throws {
        let memory = try XCTUnwrap(OverlayFrameMemory(frame: CGRect(x: 1712, y: 100, width: 1400, height: 400), baseHeight: 400, displays: [main, second]))
        let moved = OverlayFrameMemory.Display(id: 9, name: "DELL U2723QE", frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440))
        XCTAssertEqual(memory.frame(baseHeight: 400, displays: [main, moved])?.minX, -2360)
        // Yazı boyu büyüdü: oran korunur.
        XCTAssertEqual(memory.frame(baseHeight: 500, displays: [main, moved])?.height, 500)
    }

    func testMissingScreenOrBrokenSaveIsNotUsed() throws {
        let memory = try XCTUnwrap(OverlayFrameMemory(frame: CGRect(x: 1712, y: 100, width: 1400, height: 400), baseHeight: 400, displays: [main, second]))
        XCTAssertNil(memory.frame(baseHeight: 400, displays: [main]))
        var broken = memory
        broken.x = .nan
        XCTAssertNil(broken.frame(baseHeight: 400, displays: [main, second]))
        broken = memory
        broken.x = 5000
        XCTAssertNil(broken.frame(baseHeight: 400, displays: [main, second]))
        XCTAssertNil(OverlayFrameMemory(frame: CGRect(x: 9000, y: 9000, width: 100, height: 100), baseHeight: 400, displays: [main]))
        let decoded = try JSONDecoder().decode(OverlayFrameMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
    }

    func testHeightScaleIsClamped() {
        XCTAssertEqual(OverlayFrameMemory.heightScale(height: 10, baseHeight: 400), OverlayFrameMemory.smallestHeightScale)
        XCTAssertEqual(OverlayFrameMemory.heightScale(height: 99_999, baseHeight: 400), OverlayFrameMemory.largestHeightScale)
        XCTAssertEqual(OverlayFrameMemory.heightScale(height: .nan, baseHeight: 400), 1)
        XCTAssertEqual(OverlayFrameMemory.clampHeightScale(0), 1)
    }

    /// Telefon: sürükleme ekran yüksekliğine oranla kaydırır, iki parmak yazı boyunu çarpar; ikisi de sınırda kalır.
    func testPhoneDragAndPinchStayInBounds() {
        XCTAssertEqual(PhoneSubtitleLayout.offset(from: 0, moved: -200, height: 1000), -0.2, accuracy: 1e-9)
        XCTAssertEqual(PhoneSubtitleLayout.offset(from: -0.3, moved: -500, height: 1000), -PhoneSubtitleLayout.largestOffset)
        XCTAssertEqual(PhoneSubtitleLayout.offset(from: 0.1, moved: 50, height: 0), 0.1)
        XCTAssertEqual(PhoneSubtitleLayout.clampOffset(.nan), 0)
        XCTAssertEqual(PhoneSubtitleLayout.scale(from: 1, magnification: 1.5), 1.5)
        XCTAssertEqual(PhoneSubtitleLayout.scale(from: 1.5, magnification: 4), PhoneSubtitleLayout.largestScale)
        XCTAssertEqual(PhoneSubtitleLayout.scale(from: 1, magnification: 0.1), PhoneSubtitleLayout.smallestScale)
        XCTAssertEqual(PhoneSubtitleLayout.scale(from: 1.2, magnification: .nan), 1.2)
        XCTAssertEqual(PhoneSubtitleLayout.clampScale(-1), 1)
    }
}
