// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

public struct PhoneTextStyle: Equatable, Sendable {
    public let background: String
    public let foreground: String

    public init(background: String, foreground: String) {
        self.background = background
        self.foreground = foreground
    }
}

enum GamePhonePalette {
    static let neutral = PhoneTextStyle(background: "#24272A", foreground: "#FFFFFF")

    private struct RGB {
        let r: Int, g: Int, b: Int
        var tone: Int { 77*r + 150*g + 29*b }
        func near(_ other: Self, _ tolerance: Int) -> Bool {
            abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
        }
        func quantized(shift: Int = 0) -> Self {
            func channel(_ n: Int) -> Int { min(255, (min(255, max(0, n + shift)) + 4) / 8 * 8) }
            return Self(r: channel(r), g: channel(g), b: channel(b))
        }
        var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
        var luminance: Double {
            func linear(_ n: Int) -> Double {
                let s = Double(n) / 255
                return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(_ other: Self) -> Double {
            let a = luminance, b = other.luminance
            return (max(a,b) + 0.05) / (min(a,b) + 0.05)
        }
    }

    static func sample(_ frame: CGImage, box: TextBox) -> PhoneTextStyle {
        let rect = GamePhonePixels.rect(box, in: frame)
        guard rect.width > 0, rect.height > 0, let pixels = GamePhonePixels(frame, in: rect),
              pixels.width >= 3, pixels.height >= 2 else { return neutral }
        var colors: [RGB] = []
        colors.reserveCapacity(45)
        for row in 0..<5 {
            let y = (2 * row + 1) * pixels.height / 10
            for col in 0..<9 {
                let x = (4 * col + 1 + 2 * (row % 2)) * pixels.width / 36
                let p = (y * pixels.width + x) * 4
                colors.append(RGB(r: Int(pixels.bytes[p]), g: Int(pixels.bytes[p+1]), b: Int(pixels.bytes[p+2])))
            }
        }
        var center = colors[0], most = 0
        for candidate in colors {
            let count = colors.reduce(0) { $0 + (candidate.near($1, 20) ? 1 : 0) }
            if count > most { most = count; center = candidate }
        }
        guard most * 100 >= colors.count * 45 else { return neutral }
        var r = 0, g = 0, b = 0
        for pixel in colors where center.near(pixel, 20) {
            r += pixel.r; g += pixel.g; b += pixel.b
        }
        let surface = RGB(r: r / most, g: g / most, b: b / most)
        colors.sort { $0.tone < $1.tone }
        let dark = colors[2], light = colors[colors.count - 3]
        let ink = surface.tone - dark.tone > light.tone - surface.tone ? dark : light
        if most * 5 < colors.count * 3 && !twoColorSurface(colors, surface, ink) { return neutral }
        var background = surface.quantized(), foreground = ink.quantized()
        let black = RGB(r: 0, g: 0, b: 0), white = RGB(r: 255, g: 255, b: 255)
        if colors.filter({ ink.near($0, 24) }).count < 3 || background.contrast(foreground) < 4.5 {
            let lightInk = ink.tone > surface.tone
            foreground = lightInk ? white : black
            if background.contrast(foreground) < 4.5 {
                let adjusted = surface.quantized(shift: lightInk ? -8 : 8)
                if adjusted.contrast(foreground) >= 4.5 { background = adjusted }
                else { foreground = lightInk ? black : white }
            }
        }
        return PhoneTextStyle(background: background.hex, foreground: foreground.hex)
    }

    private static func twoColorSurface(_ colors: [RGB], _ surface: RGB, _ ink: RGB) -> Bool {
        let r = ink.r - surface.r, g = ink.g - surface.g, b = ink.b - surface.b
        let length = r*r + g*g + b*b
        guard length > 0 else { return false }
        let matching = colors.filter { c in
            let cr = c.r - surface.r, cg = c.g - surface.g, cb = c.b - surface.b
            let t = min(1, max(0, Double(cr*r + cg*g + cb*b) / Double(length)))
            return abs(Double(cr) - t * Double(r)) <= 24 && abs(Double(cg) - t * Double(g)) <= 24
                && abs(Double(cb) - t * Double(b)) <= 24
        }
        return matching.count * 5 >= colors.count * 4
    }
}
