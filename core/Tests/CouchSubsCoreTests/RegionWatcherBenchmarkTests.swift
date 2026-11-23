// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import CouchSubsCore

/// Ek alanların işlemci yükü: 1920×1080 karede altyazı alanının ve köşe alanlarının gerçek yazı tanıma süresi
/// (Vision). Yalnız elle çalışır: COUCHSUBS_REGION_BENCH=1 swift test --filter RegionWatcherBenchmarkTests
final class RegionWatcherBenchmarkTests: XCTestCase {
    private func frame() -> CGImage {
        let width = 1920, height = 1080
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.15, green: 0.2, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CoreGraphics'te y aşağıdan yukarıdır.
        func draw(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat) {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
            context.textPosition = CGPoint(x: x, y: CGFloat(height) - top)
            CTLineDraw(line, context)
        }
        draw("You should have stayed in the village, Arthur.", x: 520, top: 940, size: 44)
        draw("Find the blacksmith", x: 1300, top: 90, size: 30)
        draw("Bring him three iron bars", x: 1300, top: 135, size: 26)
        draw("New message from Sadie", x: 1420, top: 700, size: 26)
        draw("Meet me at the barn tonight.", x: 1420, top: 745, size: 24)
        draw("Item added: Lantern", x: 60, top: 780, size: 26)
        return context.makeImage()!
    }

    private func milliseconds(_ runs: Int, _ work: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<runs { try work() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / Double(runs)
    }

    func testReadingCost() throws {
        guard ProcessInfo.processInfo.environment["COUCHSUBS_REGION_BENCH"] == "1" else { throw XCTSkip("COUCHSUBS_REGION_BENCH verilmedi") }
        let image = frame()
        let reader = VisionReader(language: "en")
        _ = try reader.readLines(RegionCropper.crop(image, to: CropRegion()), deep: false)
        let runs = 20
        let subtitle = RegionCropper.crop(image, to: CropRegion())
        let main = try milliseconds(runs) { _ = try reader.readLines(subtitle, deep: false) }
        var report = String(format: "altyazı alanı: %.1f ms/okuma", main)
        var extras = 0.0
        for preset in ExtraAreaPreset.allCases {
            let crop = RegionCropper.crop(image, to: preset.region)
            let text = try reader.readLines(crop, deep: false).text.replacingOccurrences(of: "\n", with: " / ")
            let ms = try milliseconds(runs) { _ = try reader.readLines(crop, deep: false) }
            extras += ms
            report += String(format: "\n%@: %.1f ms/okuma (\"%@\")", preset.rawValue, ms, text)
        }
        let signature = milliseconds(runs) {
            for preset in ExtraAreaPreset.allCases { _ = RegionCropper.signature(of: RegionCropper.crop(image, to: preset.region)) }
        }
        report += String(format: "\nüç alanın izi (her tur): %.2f ms", signature)
        // En kötü durum: üç alan da her saniye yeniden okunur (arkası kıpırdayan köşe yazısı).
        report += String(format: "\nen kötü yük: saniyede %.0f ms = bir çekirdeğin %%%.1f'i", extras + signature, (extras + signature) / 10)
        print(report)
        XCTContext.runActivity(named: report) { _ in }
    }
}
