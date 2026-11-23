// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation

/// Ekrandaki metinlerde kullanıcının seçtiği kısayollar ("Num 9 ya da ⌃⇧9"; Windows: Views/HotkeyText.cs, aynı metinler).
enum HotkeyText {
    /// İşin çalışan tuşları, ör. "Num 9 ya da ⌃⇧9"; hiç kısayolu yoksa nil.
    static func keys(_ settings: UserSettings, _ action: HotkeyAction) -> String? {
        let keys = HotkeyTable.keys(settings.hotkeys, action)
        switch keys.count {
        case 0: return nil
        case 1: return keys[0].label
        default: return String(format: String(localized: "%@ or %@"), keys[0].label, keys[1].label)
        }
    }

    /// Başlık: "Ekranı çevir (Num 9 ya da ⌃⇧9)"; kısayol yoksa "(kısayol yok)". `format` yerelleştirilmiş biçimdir.
    static func title(_ settings: UserSettings, _ action: HotkeyAction, _ format: String) -> String {
        String(format: format, keys(settings, action) ?? String(localized: "no shortcut"))
    }

    /// "%@ kısayoluna basın …" cümlesi; kısayol yoksa nereden atanacağı söylenir.
    static func sentence(_ settings: UserSettings, _ action: HotkeyAction, _ format: String) -> String {
        guard let keys = keys(settings, action) else {
            return String(localized: "No shortcut is set for this. You can set one under Keyboard shortcuts.")
        }
        return String(format: format, keys)
    }

    /// Ayarlar › Kısayollar'daki satır adı.
    static func name(_ action: HotkeyAction) -> String {
        switch action {
        case .screen: String(localized: "Translate the screen")
        case .freeArea: String(localized: "Free area")
        case .extraRegion1: String(localized: "Translate area 1")
        case .extraRegion2: String(localized: "Translate area 2")
        case .extraRegion3: String(localized: "Translate area 3")
        case .pauseSubtitles: String(localized: "Pause or resume subtitles")
        case .clickThrough: String(localized: "Clicks pass through on or off")
        case .snapshot: String(localized: "Refresh the picture in Settings")
        }
    }

    /// Seçilen tuş neden olmuyor.
    static func problem(_ problem: HotkeyProblem) -> String {
        switch problem {
        case .needsModifier: String(localized: "Use this key with ⌃⇧, ⌥⌘, ⌃⌥ or ⌃⌘, so typing in other apps isn't affected.")
        case .optionOnly: String(localized: "macOS doesn't accept shortcuts with only ⌥ or ⌥⇧, and they would type special characters. Add ⌃ or ⌘.")
        case .reserved: String(localized: "macOS already uses this shortcut.")
        case .unsupportedKey, .none: String(localized: "This key can't be a shortcut.")
        }
    }
}
