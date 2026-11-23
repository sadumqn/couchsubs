// SPDX-License-Identifier: AGPL-3.0-only

import Carbon.HIToolbox
import CouchSubsCore
import Foundation

/// Genel kısayollar (varsayılan Num 0, 1, 2, 3, 5, 7, 8, 9 ve aynı işler için ⌃⇧rakam; kullanıcı Ayarlar › Kısayollar'da
/// değiştirebilir, bkz. `HotkeyTable`): kullanıcı kumandayla oynarken Mac'teki pencere arka planda olsa da çalışır
/// (Windows: GlobalHotkeys.cs, RegisterHotKey).
///
/// Carbon `RegisterEventHotKey` kullanılır: yalnız kayıtlı tuş birleşimini alır, öbür tuşları görmez; bu yüzden ne
/// Erişilebilirlik ne de Giriş İzleme izni ister ve App Store sanal alanında (sandbox) çalışır. `NSEvent` genel tuş
/// dinleyicisi (`addGlobalMonitorForEvents`) her tuşu görür ve Erişilebilirlik izni ister; o yüzden kullanılmaz.
/// macOS 15, yalnız ⌥ ya da ⌥⇧ ile kurulan kısayolları tuş dinleyicilerine karşı kısıtladı (bu Mac'te kayıt hata dönmüyor, olay gelmeyebilir); ⌥ özel karakter de yazar. `HotkeyTable.validate` bunları baştan reddeder. ⌥⌘, ⌃⇧ gibi birleşimler kısıta girmez; HotkeyModelTests kaydını sınar.
///
/// Kısayollar yalnız `enabled` iken tutulur; böylece çeviri kapalıyken sayı tuşları diğer uygulamalarda normal çalışır.
/// Tuşu başka bir uygulama tutuyorsa sessizce atlanır, işin öbür tuşu yine çalışır.
@MainActor
final class GlobalHotkeys {
    /// Bir tuşun durumu (Ayarlar'da yeni tuş seçilince söylenir).
    enum Availability: Equatable {
        case free
        /// Başka bir uygulama bu birleşimi kendine ayırmış.
        case takenByApp
        /// macOS'un kendi kısayollarından biri (Sistem Ayarları › Klavye › Klavye Kısayolları; Görev Denetimi gibi).
        case system
    }

    private nonisolated static let signature = OSType(0x4353_5354) // "CSST"
    /// Ayarlar'da tuşun boş olup olmadığını denemek için kısa süre alınan kimlik.
    private nonisolated static let probeId: UInt32 = 0xFFFF

    private let pressed: (HotkeyAction) -> Void
    private var registered: [UInt32: (ref: EventHotKeyRef, action: HotkeyAction)] = [:]
    private var handler: EventHandlerRef?
    /// Alınamayan kısayollar bir kez günlüğe yazıldı (her çeviri başlangıcında yinelenmesin).
    private var loggedFailure: String?

    init(pressed: @escaping (HotkeyAction) -> Void) {
        self.pressed = pressed
    }

    /// Kısayollar tutuluyor mu.
    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { register() } else { unregister() }
        }
    }

    /// Tutulacak kısayollar (`HotkeyTable.resolve`). Kısayollar tutuluyorsa hemen yenilenir.
    var bindings: [HotkeyBinding] = HotkeyTable.bindings {
        didSet {
            guard bindings != oldValue, enabled else { return }
            unregister()
            register()
        }
    }

    /// Tuş şu an kullanılabilir mi. Ayarlar yeni tuşu beklerken CouchSubs kendi kısayollarını bırakır
    /// (`AppModel.hotkeysPaused`); bu yüzden alınamayan tuşu başka bir uygulama tutuyordur.
    static func availability(of key: HotkeyKey) -> Availability {
        if isSystemShortcut(key) { return .system }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: probeId)
        let status = RegisterEventHotKey(key.keyCode, key.modifiers.rawValue, id, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr ? .free : .takenByApp
    }

    /// macOS'un açık sembolik kısayolları (Görev Denetimi, Spotlight, masaüstü değiştirme …) arasında mı.
    private static func isSystemShortcut(_ key: HotkeyKey) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        let relevant = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return list.contains { item in
            guard (item[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let modifiers = (item[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value else { return false }
            return code == key.keyCode && modifiers & relevant == key.modifiers.rawValue
        }
    }

    private func register() {
        installHandler()
        var failed: [String] = []
        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(binding.key.keyCode, binding.key.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered[id.id] = (ref, binding.action) } else { failed.append(binding.key.label) }
        }
        let failure = failed.joined(separator: ", ")
        if !failed.isEmpty, failure != loggedFailure {
            loggedFailure = failure
            SubtitleLog.write("kısayol alınamadı, başka bir uygulama kullanıyor: \(failure)")
        }
    }

    private func unregister() {
        for item in registered.values { UnregisterEventHotKey(item.ref) }
        registered.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotkeys.signature else { return OSStatus(eventNotHandledErr) }
            let hotkeys = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            let number = id.id
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkeys.fire(number) } }
            return noErr
        }, 1, &spec, me, &handler)
    }

    private func fire(_ id: UInt32) {
        guard let action = registered[id]?.action else { return }
        pressed(action)
    }
}
