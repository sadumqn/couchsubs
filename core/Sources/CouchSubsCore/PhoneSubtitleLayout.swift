// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// "Bu telefonda" altyazı ekranında parmakla verilen yer ve yazı boyu (kalıcı; TV'nin yazı boyuna dokunmaz). Yer, altyazının
/// varsayılan yerinden ekran yüksekliğine oranla kaydırmadır (negatif: yukarı). Android: PhoneSubtitleLayout.kt.
public enum PhoneSubtitleLayout {
    public static let smallestScale = 0.6
    public static let largestScale = 2.0
    /// Altyazı ekranın en çok bu oranı kadar yukarı ya da aşağı kaydırılır (yazı ekrandan çıkmaz).
    public static let largestOffset = 0.4

    public static func clampScale(_ scale: Double) -> Double {
        scale.isFinite && scale > 0 ? min(largestScale, max(smallestScale, scale)) : 1
    }

    public static func clampOffset(_ offset: Double) -> Double {
        offset.isFinite ? min(largestOffset, max(-largestOffset, offset)) : 0
    }

    /// Sürükleme bitince yeni yer: `moved` parmağın gittiği yol (nokta), `height` ekran yüksekliği.
    public static func offset(from start: Double, moved: Double, height: Double) -> Double {
        guard height.isFinite, height > 0, moved.isFinite else { return clampOffset(start) }
        return clampOffset(start + moved / height)
    }

    /// İki parmakla büyütüp küçültme: `magnification` hareketin çarpanı (1: değişmedi).
    public static func scale(from start: Double, magnification: Double) -> Double {
        guard magnification.isFinite, magnification > 0 else { return clampScale(start) }
        return clampScale(start * magnification)
    }
}
