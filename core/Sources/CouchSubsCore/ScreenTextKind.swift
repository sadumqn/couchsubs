// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Otomatik ekran yazısının türleri; Ayarlar'da her biri ayrı açılıp kapanır (kullanıcı isteği, X: "telefon, eylemler
/// çevirisini kullanmak istiyorum, menülerde olmasını istemiyorum"). Sıra ve adlar dört platformda aynıdır (Windows:
/// ScreenTextKind.cs, Android: ScreenTextKind.kt). "Ekranı çevir" (elle) türlerden etkilenmez, her şeyi çevirir.
public enum ScreenTextKind: String, CaseIterable, Sendable {
    /// GTA 6 telefonu (telefon okuyucusu) ve hazır mesaj kartı alanı.
    case phone
    /// Görev ve hedef yazısı (altyazıdan ayrılan görev satırı, `MissionLine`) ve haritada basılan görevin/konumun bilgi
    /// kartı (`MissionCard`; menüde açılsa da bu türdendir, ayrı anahtarı yoktur).
    case mission
    /// Yardım ve ipucu kutuları, eylemler: tuş ipuçları, etkileşim istemleri; hazır yardım kutusu alanı.
    case help
    /// Menüler (duraklatma, harita, ayarlar): dedektörün menü durumunda bulduğu alanlar.
    case menu
    /// Diğer ekran yazıları (kısa başlık, yer adı, bildirim).
    case other

    /// Alanın türü yerinden belli mi: hazır alanlar, görev satırı ve menü alanları. Kullanıcının kendi ek alanı nil
    /// (her zaman okunur); menü dışındaki otomatik alanın türü okunan yazıdan çıkar (`of(paragraphs:)`).
    public static func of(_ area: ExtraArea) -> ScreenTextKind? {
        switch area.id {
        case GameAreaPresets.phoneId: return .phone
        case GameAreaPresets.helpId: return .help
        case MissionLine.areaId: return .mission
        default: return area.auto && area.menu ? .menu : nil
        }
    }

    /// Pas turunda alan okunur mu: türü açık ya da yerinden belli değil. Menüler kapalıyken de kart boyundaki menü alanı
    /// (en çok `MissionCard.maxWidth` genişlik, ekranın yarısı yükseklik) "Görev ve hedef yazısı" açıksa okunur: haritada
    /// açılan görev kartı menü sayılan ekranda durur; kart değilse çizilmez (bkz. `RegionWatcher.kind`).
    public static func reads(_ area: ExtraArea, allows: (ScreenTextKind) -> Bool) -> Bool {
        guard let kind = of(area) else { return true }
        if allows(kind) { return true }
        let region = area.region
        return kind == .menu && allows(.mission)
            && region.right - region.left <= MissionCard.maxWidth && region.bottom - region.top <= 0.5
    }

    /// Kısa etiketten uzun sayılan yazı (yardım kutusu cümlesi) en az bu kadar sözcük.
    static let helpWords = 8

    /// Menü dışındaki otomatik alanın türü: tuş simgesi ya da tuş ipucu ("Press ✕ to jump", "R2 Aim") taşıyan, birden çok
    /// parçalı ya da uzun (en az `helpWords` sözcük) yazı yardım/eylemdir; noktalamayla biten kısa tek cümle ("Follow Paulie
    /// to the car.") görev/hedeftir; kısa başlık (yer adı) diğerdir.
    public static func of(paragraphs: [String]) -> ScreenTextKind {
        if paragraphs.contains(where: { $0.contains(ButtonIcons.marker) || ButtonPrompts.isPrompt(IconText.plain($0)) }) {
            return .help
        }
        let words = paragraphs.reduce(0) { $0 + IconText.plain($1).split(whereSeparator: \.isWhitespace).count }
        if paragraphs.count >= 2 || words >= helpWords { return .help }
        // Noktalamayla biten kısa tek cümle görev/hedef yazısıdır ("Follow Paulie to the car."), başlık değil.
        let last = IconText.plain(paragraphs.first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " \"'\u{201D}\u{2019}"))
        return words >= 2 && paragraphs.count == 1 && last.last.map { ".!?".contains($0) } == true ? .mission : .other
    }
}

extension UserSettings {
    /// Bu tür ekran yazısı çevrilir mi. "Ekran yazılarını otomatik çevir" kapalıyken türler uygulanmaz (hazır alanlar ve
    /// telefon kendi ayarlarıyla eskisi gibi çalışır).
    public func screenTextAllows(_ kind: ScreenTextKind) -> Bool {
        guard autoScreenText else { return true }
        switch kind {
        case .phone: return screenTextPhone
        case .mission: return screenTextMission
        case .help: return screenTextHelp
        case .menu: return screenTextMenus
        case .other: return screenTextOther
        }
    }

    /// GTA 6 telefonu okunur mu: kendi ayarı ("GTA 6 telefonunu otomatik çevir") ya da otomatik ekran yazısında Telefon
    /// türü açık.
    public var readsGamePhone: Bool { autoReadGamePhone || (autoScreenText && screenTextPhone) }
}
