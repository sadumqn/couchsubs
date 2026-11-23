// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import XCTest

/// Alan çerçevesinin tutamaçları, taşınması ve boyutlandırılması (Windows RegionEditTests ve Android ile aynı örnekler).
final class RegionEditTests: XCTestCase {
    private let area = CropRegion(top: 0.60, bottom: 0.90, left: 0.20, right: 0.80)
    private let grab = 0.02

    private func assertClose(_ expected: CropRegion, _ actual: CropRegion, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(expected.isClose(to: actual, tolerance: 1e-9), "\(expected) != \(actual)", file: file, line: line)
    }

    func testHandlesAreTheCornersAndEdgeMiddles() {
        XCTAssertEqual(RegionEdit.handle(at: 0.20, 0.60, in: area, grabX: grab, grabY: grab), [.left, .top])
        XCTAssertEqual(RegionEdit.handle(at: 0.50, 0.60, in: area, grabX: grab, grabY: grab), .top)
        XCTAssertEqual(RegionEdit.handle(at: 0.80, 0.75, in: area, grabX: grab, grabY: grab), .right)
        XCTAssertEqual(RegionEdit.handle(at: 0.81, 0.91, in: area, grabX: grab, grabY: grab), [.right, .bottom])
        XCTAssertEqual(RegionEdit.handle(at: 0.50, 0.75, in: area, grabX: grab, grabY: grab), .move)
    }

    func testFarOutsideIsNoHandleAndATinyFrameTakesTheNearerEdge() {
        XCTAssertNil(RegionEdit.handle(at: 0.10, 0.75, in: area, grabX: grab, grabY: grab))
        XCTAssertNil(RegionEdit.handle(at: 0.50, 0.30, in: area, grabX: grab, grabY: grab))
        let tiny = CropRegion(top: 0.50, bottom: 0.90, left: 0.50, right: 0.51)
        XCTAssertEqual(RegionEdit.handle(at: 0.512, 0.70, in: tiny, grabX: grab, grabY: grab), .right)
    }

    func testEightHandlesSitOnTheCornersAndEdgeMiddles() {
        let handles = RegionEdit.handles(area)
        XCTAssertEqual(handles.count, 8)
        XCTAssertTrue(handles.contains { $0.x == 0.50 && $0.y == 0.60 && $0.handle == .top })
        XCTAssertTrue(handles.contains { $0.x == 0.80 && $0.y == 0.75 && $0.handle == .right })
        XCTAssertTrue(handles.contains { $0.x == 0.20 && $0.y == 0.90 && $0.handle == [.left, .bottom] })
    }

    func testMovingKeepsTheSizeAndStaysInTheFrame() {
        assertClose(CropRegion(top: 0.65, bottom: 0.95, left: 0.10, right: 0.70),
                    RegionEdit.dragged(area, handle: .move, dx: -0.10, dy: 0.05, centered: true))
        assertClose(CropRegion(top: 0.70, bottom: 1.00, left: 0.40, right: 1.00),
                    RegionEdit.dragged(area, handle: .move, dx: 0.50, dy: 0.50, centered: false))
    }

    func testTheSubtitleAreaWidensFromTheMiddle() {
        assertClose(CropRegion(top: 0.60, bottom: 0.90, left: 0.10, right: 0.90),
                    RegionEdit.dragged(area, handle: .right, dx: 0.10, dy: 0, centered: true))
        assertClose(CropRegion(top: 0.60, bottom: 0.90, left: 0.30, right: 0.70),
                    RegionEdit.dragged(area, handle: .left, dx: 0.10, dy: 0, centered: true))
        assertClose(CropRegion(top: 0.60, bottom: 0.90, left: 0.00, right: 1.00),
                    RegionEdit.dragged(area, handle: .right, dx: 0.50, dy: 0, centered: true))
        assertClose(CropRegion(top: 0.60, bottom: 0.95, left: 0.15, right: 0.85),
                    RegionEdit.dragged(area, handle: [.right, .bottom], dx: 0.05, dy: 0.05, centered: true))
    }

    func testExtraAreasResizeFromTheDraggedEdgeOnly() {
        assertClose(CropRegion(top: 0.60, bottom: 0.90, left: 0.20, right: 0.90),
                    RegionEdit.dragged(area, handle: .right, dx: 0.10, dy: 0, centered: false))
        assertClose(CropRegion(top: 0.50, bottom: 0.90, left: 0.10, right: 0.80),
                    RegionEdit.dragged(area, handle: [.left, .top], dx: -0.10, dy: -0.10, centered: false))
    }

    func testWithoutKeepCenteredALeftAlignedSubtitleAreaKeepsItsLeftEdge() {
        // Sola yaslı altyazı: "Ortada tut" kapalıyken sağ kenar çekilince sol kenar yerinde kalır.
        let left = CropRegion(top: 0.80, bottom: 0.95, left: 0.05, right: 0.45)
        assertClose(CropRegion(top: 0.80, bottom: 0.95, left: 0.05, right: 0.55),
                    RegionEdit.dragged(left, handle: .right, dx: 0.10, dy: 0, centered: false))
        assertClose(CropRegion(top: 0.70, bottom: 0.95, left: 0.00, right: 0.45),
                    RegionEdit.dragged(left, handle: [.left, .top], dx: -0.05, dy: -0.10, centered: false))
        // Açıkken aynı sürükleme sol kenarı da oynatır ve karenin kenarına dayar.
        assertClose(CropRegion(top: 0.80, bottom: 0.95, left: 0.00, right: 0.50),
                    RegionEdit.dragged(left, handle: .right, dx: 0.10, dy: 0, centered: true))
    }

    func testAFrameNeverGetsSmallerThanTheMinimumOrFlips() {
        let narrow = RegionEdit.dragged(area, handle: .left, dx: 0.90, dy: 0, centered: false)
        XCTAssertEqual(narrow.left, area.right - RegionEdit.minimumSize, accuracy: 1e-9)
        let flat = RegionEdit.dragged(area, handle: .top, dx: 0, dy: 0.90, centered: false)
        XCTAssertEqual(flat.top, area.bottom - RegionEdit.minimumSize, accuracy: 1e-9)
        let centered = RegionEdit.dragged(area, handle: .right, dx: -0.90, dy: 0, centered: true)
        XCTAssertEqual(centered.right - centered.left, RegionEdit.minimumSize, accuracy: 1e-9)
        XCTAssertEqual((centered.left + centered.right) / 2, 0.50, accuracy: 1e-9)
    }

    /// GitHub #802: telefon ek alanı sürüklenirken ayar her harekette değil, bırakınca bir kez yazılır; kaydırma hep
    /// başlangıç çerçevesine göredir (taslak değiştikçe kaymaz).
    func testDragWritesTheSettingOnceWhenReleased() {
        let phone = ExtraAreaPreset.phone.region
        var saves: [CropRegion] = []
        var drag = RegionDrag(start: phone, handle: [.right, .bottom])
        for step in 1...60 {
            drag.move(dx: -0.002 * Double(step), dy: -0.003 * Double(step), centered: false)
            XCTAssertEqual(drag.start, phone)
        }
        if let result = drag.result { saves.append(result) }
        XCTAssertEqual(saves.count, 1)
        assertClose(CropRegion(top: 0.50, bottom: 0.77, left: 0.72, right: 0.86), saves[0])

        var moved = RegionDrag(start: phone, handle: .move)
        moved.move(dx: -0.10, dy: 0.20, centered: false)
        assertClose(CropRegion(top: 0.55, bottom: 1.00, left: 0.62, right: 0.88), moved.region)
    }

    func testDragThatEndsWhereItStartedWritesNothing() {
        var drag = RegionDrag(start: area, handle: .move)
        XCTAssertNil(drag.result)
        drag.move(dx: 0.05, dy: 0, centered: false)
        drag.move(dx: 0, dy: 0, centered: false)
        XCTAssertNil(drag.result)
    }
}
