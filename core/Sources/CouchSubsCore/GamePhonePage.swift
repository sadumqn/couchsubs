// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics

/// Sample the glyphs rather than the moving video behind a phone, including while a translation is pending.
struct GamePhonePage: Sendable {
    private struct Patch: Sendable {
        let box: TextBox, columns: Int, rows: Int, samples: [UInt8]
    }
    private let patches: [Patch]

    init(frame: CGImage, region: CropRegion, reading: Reading) {
        let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        var boxes = reading.lines.compactMap(\.box)
        if boxes.isEmpty { boxes = [TextBox(left: 0, top: 0, right: 1, bottom: 1)] }
        patches = boxes.compactMap { relative in
            let rect = GamePhonePixels.rect(relative.placed(in: place), in: frame)
            guard let pixels = GamePhonePixels(frame, in: rect) else { return nil }
            let columns = min(128, max(1, Int(ceil(rect.width))))
            let rows = min(12, max(1, Int(ceil(rect.height))))
            var samples: [UInt8] = []
            samples.reserveCapacity(rows * columns)
            for row in 0..<rows {
                for column in 0..<columns {
                    let p = Self.pixel(rect, column, row, columns, rows, pixels)
                    samples.append(Self.tone(pixels, p))
                }
            }
            return Patch(box: relative, columns: columns, rows: rows, samples: samples)
        }
    }

    func changed(_ frame: CGImage, region: CropRegion) -> Bool {
        guard !patches.isEmpty else { return true }
        let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
        for patch in patches {
            let rect = GamePhonePixels.rect(patch.box.placed(in: place), in: frame)
            guard let pixels = GamePhonePixels(frame, in: rect) else { return true }
            var first: Int?
            for row in 0..<patch.rows {
                for col in 0..<patch.columns {
                    let p = Self.pixel(rect, col, row, patch.columns, patch.rows, pixels)
                    let delta = Int(Self.tone(pixels, p)) - Int(patch.samples[row * patch.columns + col])
                    if abs(delta) > ReadScheduler.defaultChangeThreshold {
                        if let first, first != p { return true }
                        first = p
                    }
                }
            }
        }
        return false
    }

    private static func pixel(_ rect: CGRect, _ col: Int, _ row: Int, _ cols: Int, _ rows: Int, _ pixels: GamePhonePixels) -> Int {
        pixels.offset(Int(rect.minX + (Double(col) + 0.5) * rect.width / Double(cols)),
                      Int(rect.minY + (Double(row) + 0.5) * rect.height / Double(rows)))
    }

    private static func tone(_ pixels: GamePhonePixels, _ i: Int) -> UInt8 {
        UInt8((Int(pixels.bytes[i]) + 2 * Int(pixels.bytes[i+1]) + Int(pixels.bytes[i+2])) / 4)
    }
}
