// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Mac'teki altyazı penceresinin "Altyazıyı konumlandır" ile kaydedilen yeri: hangi ekranda olduğu (ekran kimliği ve
/// adı), o ekrana göre yeri, genişliği ve yazı boyundan hesaplanan yüksekliğe oranı. Ekranların dizilişi değişse de
/// pencere aynı ekranda aynı yerde açılır; ekran artık bağlı değilse kayıt kullanılmaz (Windows: OverlayPlacement).
public struct OverlayFrameMemory: Codable, Equatable, Sendable {
    /// Bağlı bir ekran: kimliği (CGDirectDisplayID), adı ve çerçevesi (macOS'un ekran düzleminde).
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let name: String
        public let frame: CGRect
        public init(id: UInt32, name: String, frame: CGRect) {
            self.id = id
            self.name = name
            self.frame = frame
        }
    }

    public var screenID: UInt32
    public var screenName: String
    /// Pencerenin sol alt köşesinin ekranın sol alt köşesine göre yeri.
    public var x: Double
    public var y: Double
    public var width: Double
    public var heightScale: Double

    public static let smallestWidth = 320.0
    public static let smallestHeightScale = 0.5
    public static let largestHeightScale = 3.0
    /// Pencerenin ekranda en az bu kadarı görünmüyorsa kayıt kullanılmaz.
    static let visiblePart = 80.0

    public static func clampHeightScale(_ scale: Double) -> Double {
        scale.isFinite && scale > 0 ? min(largestHeightScale, max(smallestHeightScale, scale)) : 1
    }

    /// Kenardan büyütülen ya da küçültülen pencerenin oranı.
    public static func heightScale(height: Double, baseHeight: Double) -> Double {
        height.isFinite && baseHeight.isFinite && baseHeight > 0 ? clampHeightScale(height / baseHeight) : 1
    }

    /// Pencerenin en çok üstünde kaldığı ekrana göre kayıt; hiçbir ekranda değilse nil.
    public init?(frame: CGRect, baseHeight: Double, displays: [Display]) {
        guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite, frame.width > 0,
              let display = displays.max(by: { Self.overlap(frame, $0.frame) < Self.overlap(frame, $1.frame) }),
              Self.overlap(frame, display.frame) > 0 else { return nil }
        screenID = display.id
        screenName = display.name
        x = (frame.minX - display.frame.minX).rounded()
        y = (frame.minY - display.frame.minY).rounded()
        width = frame.width.rounded()
        heightScale = (Self.heightScale(height: frame.height, baseHeight: baseHeight) * 1000).rounded() / 1000
    }

    /// Kayıtlı ekran bağlıysa (önce kimliğiyle, yoksa adıyla bulunur) penceresinin çerçevesi; ekran yoksa ya da pencere
    /// o ekranda yeterince görünmüyorsa nil.
    public func frame(baseHeight: Double, displays: [Display]) -> CGRect? {
        guard x.isFinite, y.isFinite, width.isFinite, width > 0, baseHeight.isFinite, baseHeight > 0,
              let display = displays.first(where: { $0.id == screenID }) ?? displays.first(where: { $0.name == screenName })
        else { return nil }
        let width = min(max(Self.smallestWidth, self.width), max(Self.smallestWidth, display.frame.width))
        let frame = CGRect(x: display.frame.minX + x, y: display.frame.minY + y, width: width,
                           height: (baseHeight * Self.clampHeightScale(heightScale)).rounded())
        let visible = frame.intersection(display.frame)
        guard !visible.isNull, visible.width >= min(Self.visiblePart, frame.width), visible.height >= min(Self.visiblePart, frame.height)
        else { return nil }
        return frame
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let both = a.intersection(b)
        return both.isNull ? 0 : both.width * both.height
    }
}
