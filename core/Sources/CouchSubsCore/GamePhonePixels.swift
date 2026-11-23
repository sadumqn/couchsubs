// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Consistent, top-origin RGBA samples for Core Graphics images, including VideoToolbox frames.
/// Crop before drawing: a message bubble must not require a full-screen conversion.
struct GamePhonePixels {
    let width: Int
    let height: Int
    let x: Int
    let y: Int
    let bytes: [UInt8]

    init?(_ image: CGImage, in rect: CGRect? = nil, width outputWidth: Int? = nil, height outputHeight: Int? = nil) {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let frame = (rect ?? extent).integral.intersection(extent)
        guard !frame.isEmpty else { return nil }
        let source: CGImage
        if frame == extent { source = image }
        else if let cropped = image.cropping(to: frame) { source = cropped }
        else { return nil }
        x = Int(frame.minX)
        y = Int(frame.minY)
        let w = outputWidth ?? Int(frame.width), h = outputHeight ?? Int(frame.height)
        guard w > 0, h > 0 else { return nil }
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        var storage = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = storage.withUnsafeMutableBytes { buffer -> Bool in
            func make(_ space: CGColorSpace) -> CGContext? {
                CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: space, bitmapInfo: info)
            }
            guard let surface = make(space) ?? make(CGColorSpaceCreateDeviceRGB()) else { return false }
            surface.setBlendMode(.copy)
            surface.interpolationQuality = .none
            surface.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        bytes = storage
    }

    /// Native-scale crop only; the rect uses the same pixel coordinates as the source.
    func offset(_ px: Int, _ py: Int) -> Int {
        (min(height - 1, max(0, py - y)) * width + min(width - 1, max(0, px - x))) * 4
    }

    static func rect(_ box: TextBox, in image: CGImage) -> CGRect {
        CGRect(x: box.left * Double(image.width), y: box.top * Double(image.height),
               width: (box.right - box.left) * Double(image.width), height: (box.bottom - box.top) * Double(image.height))
    }
}
