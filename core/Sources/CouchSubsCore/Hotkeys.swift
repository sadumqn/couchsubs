// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Genel kısayolların yaptığı iş (Windows: CouchSubs.Shell/Hotkeys.cs HotkeyAction; aynı adlar, aynı sıra, aynı
/// varsayılanlar). Her işin iki tuşu var: sayı tuş takımındaki rakam ve sayı tuş takımı olmayan klavyeler için ⌃⇧rakam.
/// Kullanıcı ikisini de Ayarlar › Kısayollar'da değiştirebilir.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    /// Num 1 / ⌃⇧1: 1. ek alanı bir kez çevir.
    case extraRegion1 = "ExtraRegion1"
    /// Num 2 / ⌃⇧2: 2. ek alanı bir kez çevir.
    case extraRegion2 = "ExtraRegion2"
    /// Num 3 / ⌃⇧3: 3. ek alanı bir kez çevir.
    case extraRegion3 = "ExtraRegion3"
    /// Num 5 / ⌃⇧5: görüntüyü dondurup serbest alan seçtir.
    case freeArea = "FreeArea"
    /// Num 8 / ⌃⇧8: Ayarlar'daki görüntüyü oyunun şu anki görüntüsüyle yenile.
    case snapshot = "Snapshot"
    /// Num 0 / ⌃⇧0: canlı altyazı çevirisini duraklat / sürdür.
    case pauseSubtitles = "PauseSubtitles"
    /// Num 9 / ⌃⇧9: ekranın tamamını bir kez çevir; yeniden basınca çeviriler kalkar.
    case screen = "Screen"
    /// Num 7 / ⌃⇧7: bilgisayar ekranındaki altyazı penceresinde "Tıklamalar geçsin"i aç / kapat.
    case clickThrough = "ClickThrough"

    /// "N. alanı çevir" işleri, sırayla (1. alan, 2. alan, 3. alan).
    public static let areaActions: [HotkeyAction] = [.extraRegion1, .extraRegion2, .extraRegion3]

    /// "N. alanı çevir" işinin alan numarası (1-3); başka işse nil.
    public var areaNumber: Int? { Self.areaActions.firstIndex(of: self).map { $0 + 1 } }
}

/// Değiştirici tuşlar. Değerler Carbon'un `cmdKey`, `shiftKey`, `optionKey`, `controlKey` maskeleriyle aynıdır;
/// `RegisterEventHotKey`'e olduğu gibi verilir.
public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = HotkeyModifiers(rawValue: 0x0100)
    public static let shift = HotkeyModifiers(rawValue: 0x0200)
    public static let option = HotkeyModifiers(rawValue: 0x0800)
    public static let control = HotkeyModifiers(rawValue: 0x1000)
    /// Varsayılan ikinci tuşun değiştiricileri (Windows'taki Ctrl+Shift).
    public static let combo: HotkeyModifiers = [.control, .shift]

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self) & 0x1B00
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Bir tuş birleşimi: değiştiriciler ve Mac'in sanal tuş kodu (`kVK_*`).
public struct HotkeyKey: Codable, Hashable, Sendable {
    public var modifiers: HotkeyModifiers
    public var keyCode: UInt32

    public init(_ modifiers: HotkeyModifiers, _ keyCode: UInt32) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// Ekranda ve günlükte görünen ad (ör. "⌃⇧9", "⌥⌘T", "Num 9").
    public var label: String { HotkeyTable.label(self) }
}

/// Kullanıcının varsayılandan farklı seçtiği kısayol. `slot` 0 ya da 1 (her işin iki tuşu); `key` nil ise o tuş
/// kapalıdır. Ayarlarda yalnız varsayılandan farklı olanlar durur; böylece eski kayıtlar ve değiştirilmeyen tuşlar
/// varsayılanla açılır (Windows: HotkeyChoice).
public struct HotkeyChoice: Codable, Equatable, Sendable {
    public var action: HotkeyAction
    public var slot: Int
    public var key: HotkeyKey?

    public init(action: HotkeyAction, slot: Int, key: HotkeyKey?) {
        self.action = action
        self.slot = slot
        self.key = key
    }
}

/// Tutulacak bir kısayol: işi ve tuşu.
public struct HotkeyBinding: Equatable, Sendable {
    public var action: HotkeyAction
    public var key: HotkeyKey

    public init(action: HotkeyAction, key: HotkeyKey) {
        self.action = action
        self.key = key
    }
}

/// Seçilen tuş neden kullanılamaz.
public enum HotkeyProblem: Equatable, Sendable {
    case none
    /// Bu tuş kısayol olamaz (Esc, Sekme, Return, harf dışı simgeler …).
    case unsupportedKey
    /// Harf, rakam ve gezinme tuşları tek başına ya da tek değiştiriciyle diğer uygulamalarda yazıyı ve uygulama
    /// kısayollarını (⌘C, ⌃A) bozar.
    case needsModifier
    /// Yalnız ⌥ ya da ⌥⇧: macOS 15 bu kısayolları tuş dinleyicilerine karşı kısıtladı (kayıt hata dönmese de olay gelmeyebilir); ayrıca ⌥ özel
    /// karakter yazar (Windows'taki AltGr sorununun karşılığı).
    case optionOnly
    /// macOS'un kendi işi var (ekran görüntüsü ⌘⇧3/4/5, ekranı kilitle ⌃⌘Q).
    case reserved
}

/// Genel kısayol tablosu (Windows: HotkeyTable). Sayı tuş takımı dizüstü Mac'lerde yoksa aynı işler ⌃⇧ ile üst sıradaki
/// rakamlarla da yapılır. ⌃⇧rakam karakter yazmaz ve macOS'ta varsayılan bir işi yoktur (⌃rakam masaüstü değiştirir,
/// ⌘⇧rakam ekran görüntüsü alır).
public enum HotkeyTable {
    /// Her işin kaç tuşu var (0: sayı tuş takımı, 1: ⌃⇧rakam).
    public static let slotCount = 2

    /// İşlerin rakamı: sayı tuş takımındaki tuş da ⌃⇧ tuşu da bu rakamdır. Sıra kısayol kimliğini belirler.
    public static let digits: [(action: HotkeyAction, digit: Int)] = [
        (.extraRegion1, 1), (.extraRegion2, 2), (.extraRegion3, 3), (.freeArea, 5),
        (.snapshot, 8), (.pauseSubtitles, 0), (.screen, 9), (.clickThrough, 7),
    ]

    /// Ayarlar › Kısayollar'daki sıra: en çok kullanılandan aza (Windows: HotkeyText.Order).
    public static let order: [HotkeyAction] = [
        .screen, .freeArea, .extraRegion1, .extraRegion2, .extraRegion3, .pauseSubtitles, .clickThrough, .snapshot,
    ]

    /// Sayı tuş takımındaki rakamların tuş kodları (kVK_ANSI_Keypad0 … 9).
    static let keypadDigits: [UInt32] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
    /// Üst sıradaki rakamların tuş kodları (kVK_ANSI_0 … 9).
    static let rowDigits: [UInt32] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]

    /// Varsayılan tablo: önce bütün sayı tuş takımı tuşları, sonra ⌃⇧rakam tuşları.
    public static var bindings: [HotkeyBinding] { resolve(nil) }

    /// İşin varsayılan tuşu: 0. yuva sayı tuş takımındaki rakam, 1. yuva ⌃⇧rakam.
    public static func defaultKey(_ action: HotkeyAction, slot: Int) -> HotkeyKey {
        let digit = digits.first { $0.action == action }!.digit
        return slot == 0 ? HotkeyKey([], keypadDigits[digit]) : HotkeyKey(.combo, rowDigits[digit])
    }

    /// Kullanıcının seçimine göre işin o yuvadaki tuşu; kapatıldıysa nil.
    public static func key(_ choices: [HotkeyChoice]?, _ action: HotkeyAction, slot: Int) -> HotkeyKey? {
        guard let choice = choices?.last(where: { $0.action == action && $0.slot == slot }) else { return defaultKey(action, slot: slot) }
        return choice.key
    }

    /// Tutulacak kısayollar. Sıra varsayılan tablodaki gibidir (önce 0. yuvalar). Kapatılan, geçersiz (ayar dosyası elle
    /// değiştirildiyse) ya da başka bir işe zaten verilmiş tuşlar atlanır.
    public static func resolve(_ choices: [HotkeyChoice]?) -> [HotkeyBinding] {
        var result: [HotkeyBinding] = []
        var used = Set<HotkeyKey>()
        for slot in 0..<slotCount {
            for (action, _) in digits {
                guard let key = key(choices, action, slot: slot), validate(key) == .none, used.insert(key).inserted else { continue }
                result.append(HotkeyBinding(action: action, key: key))
            }
        }
        return result
    }

    /// İşin çalışan tuşları (kapatılanlar ve çakışanlar hariç), yuva sırasıyla.
    public static func keys(_ choices: [HotkeyChoice]?, _ action: HotkeyAction) -> [HotkeyKey] {
        resolve(choices).filter { $0.action == action }.map(\.key)
    }

    /// İşin o yuvasına tuşu verir (nil: kapatır). Tuş başka bir işte kullanılıyorsa oradan kaldırılır ve dönen
    /// `displaced` o iş olur. Dönen listede yalnız varsayılandan farklı yuvalar bulunur.
    public static func assign(_ choices: [HotkeyChoice]?, _ action: HotkeyAction, slot: Int,
                              key newKey: HotkeyKey?) -> (choices: [HotkeyChoice], displaced: HotkeyAction?) {
        var keys: [(action: HotkeyAction, slot: Int, key: HotkeyKey?)] = []
        for (each, _) in digits {
            for s in 0..<slotCount { keys.append((each, s, each == action && s == slot ? newKey : key(choices, each, slot: s))) }
        }
        var displaced: HotkeyAction?
        if let newKey {
            for index in keys.indices where !(keys[index].action == action && keys[index].slot == slot) && keys[index].key == newKey {
                keys[index].key = nil
                if keys[index].action != action { displaced = keys[index].action }
            }
        }
        let result = keys.filter { $0.key != defaultKey($0.action, slot: $0.slot) }
            .map { HotkeyChoice(action: $0.action, slot: $0.slot, key: $0.key) }
        return (result, displaced)
    }

    /// Tuş kısayol olabilir mi; olamıyorsa nedeni.
    public static func validate(_ key: HotkeyKey) -> HotkeyProblem {
        guard keyName(key.keyCode) != nil else { return .unsupportedKey }
        let modifiers = key.modifiers
        // macOS 15'in kısıtı ve ⌥'nin özel karakter yazması: yalnız ⌥ / ⌥⇧ kabul edilmez.
        if modifiers == .option || modifiers == [.option, .shift] { return .optionOnly }
        if isReserved(key) { return .reserved }
        if standsAlone(key.keyCode) { return .none }
        // Harf, rakam, ok ve gezinme tuşları: ⇧ dışında en az iki değiştirici ya da ⌃⇧ (tek ⌘ uygulama kısayollarıyla, tek
        // ⌃ yazı alanlarının ⌃A/⌃E gibi tuşlarıyla, ⌘⇧ ekran görüntüsü ve uygulama kısayollarıyla çakışır).
        let main = modifiers.subtracting(.shift)
        let count = [HotkeyModifiers.control, .option, .command].filter { main.contains($0) }.count
        return count >= 2 || modifiers == .combo ? .none : .needsModifier
    }

    /// macOS'un kendine ayırdığı birleşimler: ekran görüntüsü (⌘⇧3/4/5/6, ⌃ ile de) ve ekranı kilitle (⌃⌘Q).
    private static func isReserved(_ key: HotkeyKey) -> Bool {
        let main = key.modifiers.subtracting(.control)
        if main == [.command, .shift], [0x14, 0x15, 0x17, 0x16].contains(key.keyCode) { return true }
        return key.modifiers == [.control, .command] && key.keyCode == 0x0C
    }

    /// Tek başına da kısayol olabilen tuşlar: sayı tuş takımı ve F1–F20.
    private static func standsAlone(_ code: UInt32) -> Bool {
        keypadDigits.contains(code) || keypadOthers[code] != nil || functionKeys[code] != nil
    }

    /// Ekranda görünen ad: değiştiriciler macOS sırasıyla (⌃⌥⇧⌘), sonra tuş.
    public static func label(_ key: HotkeyKey) -> String {
        var text = ""
        if key.modifiers.contains(.control) { text += "⌃" }
        if key.modifiers.contains(.option) { text += "⌥" }
        if key.modifiers.contains(.shift) { text += "⇧" }
        if key.modifiers.contains(.command) { text += "⌘" }
        return text + (keyName(key.keyCode) ?? String(format: "0x%02X", key.keyCode))
    }

    /// Kısayol olabilen tuşun adı; olamıyorsa nil. Harfler ABD dizilimindeki yerine göre adlandırılır (macOS'un
    /// kısayol tuş kodları dizilimden bağımsızdır).
    public static func keyName(_ code: UInt32) -> String? {
        if let index = keypadDigits.firstIndex(of: code) { return "Num \(index)" }
        if let index = rowDigits.firstIndex(of: code) { return "\(index)" }
        return letters[code] ?? keypadOthers[code] ?? functionKeys[code] ?? navigation[code]
    }

    private static let letters: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
        0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
        0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
    ]
    private static let keypadOthers: [UInt32: String] = [
        0x43: "Num *", 0x45: "Num +", 0x4E: "Num -", 0x41: "Num .", 0x4B: "Num /", 0x51: "Num =", 0x47: "Num Clear",
    ]
    private static let functionKeys: [UInt32: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9",
        0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17",
        0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]
    private static let navigation: [UInt32: String] = [
        0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}

/// Değiştirilebilir kısayollardan önceki Mac sürümlerinin sabit kısayolları: ⌥⌘T ekranı çevirir, ⌥⌘L tıklamaları
/// geçirir. Önceki sürümden gelen kurulumda bu iki tuş ilgili işin ikinci tuşu (⌃⇧rakam yerine) olarak bir kez atanır;
/// kullanıcının alışkanlığı bozulmaz, Num tuşu da çalışır. Yeni kurulum Windows'taki varsayılanlarla açılır. ⌥⌘
/// birleşimleri macOS 15'in kısıtına (yalnız ⌥ ya da ⌥⇧) girmez; `HotkeyTable.validate` de geçirir.
public enum LegacyMacHotkeys {
    public static let screen = HotkeyKey([.option, .command], 0x11)
    public static let clickThrough = HotkeyKey([.option, .command], 0x25)

    /// Kayıtlı ayar önceki bir sürümden mi: ayar var ama kısayol alanı yok. Ayar hiç yoksa (yeni kurulum) false.
    public static func isLegacy(_ saved: Data?) -> Bool {
        guard let saved, let object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any] else { return false }
        return object["hotkeys"] == nil
    }

    /// Eski iki tuşu ikinci yuvaya koyar (başka işte duruyorsa oradan taşınır).
    public static func apply(_ choices: [HotkeyChoice]) -> [HotkeyChoice] {
        let withScreen = HotkeyTable.assign(choices, .screen, slot: 1, key: screen).choices
        return HotkeyTable.assign(withScreen, .clickThrough, slot: 1, key: clickThrough).choices
    }
}
