// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kısayolla bir kez okunan alanın sonucunun gösterildiği yer (Windows: ResultTarget).
public enum ResultTarget: String, Codable, CaseIterable, Sendable {
    /// TV'de (ya da altyazının gösterildiği yerde).
    case tv
    /// Yalnız bu bilgisayarda, küçük sonuç penceresinde.
    case pc
    /// İkisinde de.
    case both

    /// Sonuç TV'ye gider mi.
    public var toTV: Bool { self != .pc }
    /// Sonuç bilgisayardaki sonuç penceresinde gösterilir mi.
    public var toComputer: Bool { self != .tv }
}

/// Altyazı alanının yanındaki ek alan (görev yazısı, telefon mesajı, bildirim). Dört platformda aynı model: adlı liste,
/// en çok `maxCount` (Windows: Contracts.cs ExtraArea, Android: Areas.kt ExtraArea). Sürekli okunan alanlar ana
/// altyazıdan ayrı ve daha seyrek okunur (bkz. `RegionWatcher`); çevirileri TV'de kendi yerlerinde küçük kutuda görünür.
/// Masaüstünde sıradaki alan kısayolla da bir kez okunur (1. alan "1. alanı çevir" …).
public struct ExtraArea: Codable, Equatable, Identifiable, Sendable {
    /// En çok bu kadar ek alan tanımlanır (her biri saniyede bir okunur; masaüstünde kısayolları Num 1-3).
    /// Eskiden 3 idi; yeni arayüzde sınır kaldırıldı (yalnız kayıt şişmesin diye üst sınır). İlk üçünün kısayolu var
    /// (Num 1–3), sonrakiler kısayolsuz.
    public static let maxCount = 50

    /// TV'deki kutunun kimliği; değişmez.
    public var id: String
    /// Kullanıcının verdiği ad ("Görev", "Telefon").
    public var name: String
    public var region: CropRegion
    /// "Bu alanı sürekli oku": çeviri sürerken saniyede bir okunur. Kapalıysa sürekli okunmaz, ayarı kalır; masaüstünde
    /// kısayolla yine bir kez okunur.
    public var enabled: Bool
    /// Kısayolla bir kez okununca sonucun gösterildiği yer (masaüstü). Telefonlarda sonuç her zaman TV'dedir; alan
    /// aynı modelle saklanır.
    public var target: ResultTarget = .tv
    /// Ekran yazısı olarak kendiliğinden bulunmuş geçici alan (`ScreenTextDetector`): gürültü yazısı (sayaç, etiket)
    /// çevrilmez, yazısız ya da gürültülü okuma `RegionWatcher.onAutoRejected` ile bildirilir; okuma aralığı en çok
    /// 500 ms. Ayarlara yazılmaz.
    public var auto = false
    /// Otomatik alan ekrandaki bir menüde (`ScreenTextDetector.inMenu`): kısa etiketler de çevrilir.
    public var menu = false

    public init(id: String = UUID().uuidString, name: String, region: CropRegion, enabled: Bool = true, target: ResultTarget = .tv,
                auto: Bool = false) {
        self.id = id
        self.name = name
        self.region = region
        self.enabled = enabled
        self.target = target
        self.auto = auto
    }

    private enum CodingKeys: String, CodingKey { case id, name, region, enabled, target }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        region = try values.decodeIfPresent(CropRegion.self, forKey: .region) ?? ExtraAreaPreset.quest.region
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Eski kayıtta yoktur; bilinmeyen değer de TV sayılır.
        target = (try? values.decodeIfPresent(ResultTarget.self, forKey: .target)) ?? .tv
    }

    /// Ekranda görünen ad: verilen ad, yoksa "Bölge 1" gibi sırasıyla (Windows: ExtraArea.DisplayName).
    public func displayName(_ number: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return name }
        switch number {
        case 1: return String(localized: "Area 1")
        case 2: return String(localized: "Area 2")
        default: return String(localized: "Area 3")
        }
    }
}

/// Ek alanın hazır seçimleri: oyunların çoğu bu yazıları ekranın köşelerinde gösterir.
public enum ExtraAreaPreset: String, CaseIterable, Sendable {
    /// Sağ üstteki görev yazısı.
    case quest
    /// Sol alttaki bildirim (eşya alındı, görev güncellendi).
    case notification
    /// Sağ alttaki telefon mesajı ya da e-posta.
    case phone

    public var region: CropRegion {
        switch self {
        case .quest: CropRegion(top: 0.03, bottom: 0.30, left: 0.66, right: 0.98)
        case .notification: CropRegion(top: 0.58, bottom: 0.88, left: 0.02, right: 0.30)
        case .phone: CropRegion(top: 0.50, bottom: 0.95, left: 0.72, right: 0.98)
        }
    }

    /// Bölge bir hazır seçimle aynıysa o.
    public static func matching(_ region: CropRegion) -> ExtraAreaPreset? {
        allCases.first { $0.region.isClose(to: region) }
    }
}

extension UserSettings {
    /// Okunacak ek alanlar (açık olanlar, en çok `ExtraArea.maxCount`). Altyazı alanı Tam ekranken hiçbiri okunmaz:
    /// ekranın tamamı zaten okunuyor, ek alanlar aynı yazıyı ikinci kez çevirirdi. Alanların açık/kapalı ayarı
    /// değişmez; başka bir alan seçilince eskisi gibi okunurlar (Windows: UserSettings.WatchedAreas, Android: watched).
    public var activeExtraAreas: [ExtraArea] {
        guard !extraAreasPausedByFullScreen else { return [] }
        return Array(extraAreas.filter(\.enabled).prefix(ExtraArea.maxCount))
    }

    /// Altyazı alanı Tam ekran: ek alanlar okunmuyor (ayarları korunur).
    public var extraAreasPausedByFullScreen: Bool { areaPreset == .full }

    /// Ek alan eklenebilir mi.
    public var canAddExtraArea: Bool { extraAreas.count < ExtraArea.maxCount }

    /// Hazır seçimle yeni ek alan ekler; sınır dolduysa bir şey yapmaz. Eklenen alanın kimliğini döner.
    @discardableResult
    public mutating func addExtraArea(_ preset: ExtraAreaPreset, name: String) -> String? {
        guard canAddExtraArea else { return nil }
        let area = ExtraArea(name: name, region: preset.region)
        extraAreas.append(area)
        return area.id
    }

    /// Kısayolun okuduğu ek alan: 1, 2 ya da 3. sıradaki; yoksa nil (Windows: ExtraAreaAt).
    public func extraArea(at number: Int) -> ExtraArea? {
        number >= 1 && number <= extraAreas.count ? extraAreas[number - 1] : nil
    }

    /// Ek alan silinir; arkasındakiler (ve kısayolları) bir sıra öne gelir.
    public mutating func removeExtraArea(id: String) {
        extraAreas.removeAll { $0.id == id }
    }

    /// Kimliği verilen ek alanı değiştirir (yoksa bir şey yapmaz).
    public mutating func updateExtraArea(id: String, _ change: (inout ExtraArea) -> Void) {
        guard let index = extraAreas.firstIndex(where: { $0.id == id }) else { return }
        change(&extraAreas[index])
    }
}
