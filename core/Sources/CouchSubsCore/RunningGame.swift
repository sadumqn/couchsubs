// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// PS5'te o an çalışan oyun: keşif yanıtındaki `running-app-titleid` ve `running-app-name`. Ortak havuza giden satıra
/// eklenir; yeni bir oyun (ör. GTA 6) çıkınca o oyunun satırları ayrı toplanıp hızla paket yapılır. Yalnız oyunun kimliği
/// ve adı gider, kullanıcıya dair bir şey gitmez. Windows'taki CouchSubs.Core/RunningGame.cs ve Android'deki
/// RunningGame.kt ile aynı kurallar (sunucu da aynısını doğrular: server/pool/src/index.js).
/// PS5 çoğu zaman çalışan oyunu bildirmiyor; o zaman oyun uygulamanın paketten tanıdığı ya da kullanıcının seçtiği addır
/// (`GameSense`): kimlik yoktur, yalnız ad gider.
public struct RunningGame: Codable, Equatable, Hashable, Sendable {
    /// "PPSA01234" ya da "CUSA00419_00" (büyük harf); oyun paketten ya da kullanıcının seçiminden geldiyse çoğu zaman nil.
    public let titleId: String?
    /// PS5'in bildirdiği, paketin ya da kullanıcının verdiği ad; en çok 120 karakter.
    public let name: String?

    public static let maxName = 120

    /// Kimlik PS5 biçiminde değilse nil (ana ekran ya da sistem uygulaması da kimlik bildirebilir; biçim tutmazsa alınmaz).
    public init?(titleId: String?, name: String?) {
        guard let id = Self.normalizedTitleId(titleId) else { return nil }
        self.titleId = id
        self.name = Self.normalizedName(name)
    }

    /// Yalnız adıyla bilinen oyun (paketten tanındı ya da kullanıcı seçti); ad boşsa nil. Kimlik geçerliyse o da tutulur.
    public init?(name: String?, titleId: String? = nil) {
        guard let name = Self.normalizedName(name) else { return nil }
        self.titleId = Self.normalizedTitleId(titleId)
        self.name = name
    }

    /// Dört harf, beş rakam, isteğe bağlı "_00" eki.
    static func normalizedTitleId(_ value: String?) -> String? {
        guard let value else { return nil }
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scalars = Array(id.unicodeScalars)
        guard scalars.count == 9 || scalars.count == 12 else { return nil }
        let isLetter: (Unicode.Scalar) -> Bool = { $0.value >= 65 && $0.value <= 90 }
        let isDigit: (Unicode.Scalar) -> Bool = { $0.value >= 48 && $0.value <= 57 }
        guard scalars[0..<4].allSatisfy(isLetter), scalars[4..<9].allSatisfy(isDigit) else { return nil }
        if scalars.count == 12 {
            guard scalars[9] == "_", isDigit(scalars[10]), isDigit(scalars[11]) else { return nil }
        }
        return id
    }

    /// Denetim karakterleri ve fazla boşluk atılır; boşsa nil.
    static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = String(String.UnicodeScalarView(value.unicodeScalars.map {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format ? " " : $0
        }))
        let words = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = String(words.prefix(maxName)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
