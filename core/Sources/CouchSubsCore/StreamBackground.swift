// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// "Yayın penceresi"nin ve OBS sayfasının (`/obs?bg=green`) düz zemin rengi. Şeffaflık tanımayan yayın programları
/// (TikTok LIVE Studio, pencere yakalama) pencereyi yakalar, zemini chroma key ile siler. Windows karşılığı aynı adları
/// ve renkleri kullanır.
public enum StreamBackground: String, CaseIterable, Codable, Sendable {
    case green, black, magenta

    /// 0-255 RGB; chroma key'in varsayılanlarıyla (yeşil #00FF00, mor #FF00FF) aynı.
    public var rgb: (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .green: (0x00, 0xFF, 0x00)
        case .black: (0x00, 0x00, 0x00)
        case .magenta: (0xFF, 0x00, 0xFF)
        }
    }

    /// Kayıtlı değer okunamazsa yeşil (chroma key'in en yaygın rengi).
    public init(stored: String?) {
        self = stored.flatMap(StreamBackground.init(rawValue:)) ?? .green
    }

    /// Düz zeminde yarı saydam altyazı kutusu zeminle karışır ve chroma key'i bozar: kutu ya tam koyu ya hiç yoktur.
    public static func boxOpacity(background percent: Int) -> Double {
        percent > 0 ? 1 : 0
    }
}
