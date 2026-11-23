// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Alan çerçevesinin fareyle/parmakla düzenlenmesi (Ayarlar › Alan önizlemesi): hangi tutamacın tutulduğu, taşıma ve
/// boyutlandırma. Çerçevenin sekiz tutamacı vardır (köşeler ve kenar ortaları). Altyazı alanında "Ortada tut" açıksa
/// (varsayılan, `UserSettings.keepAreaCentered`) yatay boyut ortadan değişir: sağ kenar çekilince sol kenar da aynı kadar
/// açılır, alan ortalı kalır (oyunların çoğu altyazıyı ortalar). Kapalıysa (sola yaslı ya da köşedeki altyazı) ve ek
/// alanlarda kenarlar serbesttir: yalnız tutulan kenar oynar. Windows'taki CouchSubs.Core/RegionEdit.cs ve Android'deki
/// RegionEdit.kt ile aynı kurallar.
public enum RegionEdit {
    public struct Handle: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let left = Handle(rawValue: 1)
        public static let top = Handle(rawValue: 2)
        public static let right = Handle(rawValue: 4)
        public static let bottom = Handle(rawValue: 8)
        /// Taşıma (çerçevenin içi).
        public static let move: Handle = []
    }

    /// Çerçeve düzenlenirken bir kenarın en küçük boyu (kenara oranla); tek satırlık küçük HUD yazıları için
    /// kaydırıcıların sınırından (`CropRegion.minimumSize`) küçüktür.
    public static let minimumSize = 0.03

    /// Önizlemedeki nokta (0–1) hangi tutamaçta: kenar ya da köşe; çerçevenin içinde ve kenarlardan uzaktaysa `.move`;
    /// çerçevenin dışındaysa nil. `grabX`/`grabY`: tutma payı (kenara oranla).
    public static func handle(at x: Double, _ y: Double, in region: CropRegion, grabX: Double, grabY: Double) -> Handle? {
        if x < region.left - grabX || x > region.right + grabX || y < region.top - grabY || y > region.bottom + grabY { return nil }
        var handle: Handle = []
        // Çok küçük bir çerçevede iki kenar üst üste gelirse daha yakın olan tutulur.
        let (left, right) = (abs(x - region.left), abs(x - region.right))
        if min(left, right) <= grabX { handle.insert(left <= right ? .left : .right) }
        let (top, bottom) = (abs(y - region.top), abs(y - region.bottom))
        if min(top, bottom) <= grabY { handle.insert(top <= bottom ? .top : .bottom) }
        if handle.isEmpty, x < region.left || x > region.right || y < region.top || y > region.bottom { return nil }
        return handle
    }

    /// `start` çerçevesi `handle`'dan (dx, dy) kadar sürüklendi. `.move` taşır; kenarlar boyutlandırır. `centered`: yatay
    /// boyut ortadan değişir. Çerçeve karenin dışına taşmaz ve her kenarda en az `minimumSize` kalır.
    public static func dragged(_ start: CropRegion, handle: Handle, dx: Double, dy: Double, centered: Bool) -> CropRegion {
        if handle.isEmpty {
            let width = start.right - start.left, height = start.bottom - start.top
            let left = clamp(start.left + dx, 0, 1 - width)
            let top = clamp(start.top + dy, 0, 1 - height)
            return CropRegion(top: top, bottom: top + height, left: left, right: left + width)
        }
        var (t, b, l, r) = (start.top, start.bottom, start.left, start.right)
        if handle.contains(.top) { t = clamp(start.top + dy, 0, start.bottom - minimumSize) }
        if handle.contains(.bottom) { b = clamp(start.bottom + dy, start.top + minimumSize, 1) }
        if centered, handle.contains(.left) || handle.contains(.right) {
            let center = (start.left + start.right) / 2
            var half = handle.contains(.right) ? start.right + dx - center : center - (start.left + dx)
            half = clamp(half, minimumSize / 2, max(minimumSize / 2, min(center, 1 - center)))
            (l, r) = (max(0, center - half), min(1, center + half))
        } else {
            if handle.contains(.left) { l = clamp(start.left + dx, 0, start.right - minimumSize) }
            if handle.contains(.right) { r = clamp(start.right + dx, start.left + minimumSize, 1) }
        }
        return CropRegion(top: t, bottom: b, left: l, right: r)
    }

    /// Sekiz tutamacın yeri (0–1) ve tutamacı: köşeler ve kenar ortaları, saat yönünde sol üstten.
    public static func handles(_ region: CropRegion) -> [(x: Double, y: Double, handle: Handle)] {
        let midX = (region.left + region.right) / 2, midY = (region.top + region.bottom) / 2
        return [
            (region.left, region.top, [.left, .top]), (midX, region.top, .top), (region.right, region.top, [.right, .top]),
            (region.right, midY, .right), (region.right, region.bottom, [.right, .bottom]), (midX, region.bottom, .bottom),
            (region.left, region.bottom, [.left, .bottom]), (region.left, midY, .left),
        ]
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }
}

/// Sürüklenen çerçevenin taslağı. Sürükleme boyunca yalnız taslak değişir, ayar bırakınca bir kez yazılır: her fare
/// hareketinde ayar yazılsaydı bütün Ayarlar sayfası yeniden çizilir, pencere titrerdi (GitHub #802). Kaydırma hep
/// sürüklemenin başladığı çerçeveye göre hesaplanır. Windows'ta RegionPicker, Android'de RegionPreview aynı kuralla çalışır.
public struct RegionDrag: Equatable, Sendable {
    /// Sürükleme başladığında çerçeve.
    public let start: CropRegion
    public let handle: RegionEdit.Handle
    /// Önizlemede gösterilen taslak.
    public private(set) var region: CropRegion

    public init(start: CropRegion, handle: RegionEdit.Handle) {
        self.start = start
        self.handle = handle
        region = start
    }

    /// Başlangıçtan (dx, dy) kadar (kenara oranla) sürüklendi.
    public mutating func move(dx: Double, dy: Double, centered: Bool) {
        region = RegionEdit.dragged(start, handle: handle, dx: dx, dy: dy, centered: centered)
    }

    /// Bırakınca yazılacak çerçeve; hiç değişmediyse nil (tıklamak ayar yazmaz).
    public var result: CropRegion? { region == start ? nil : region }
}
