// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI

/// Ayarlar › Kısayollar: her iş bir satır, iki düğme (iki tuş; Windows: SettingsWindow ShortcutsTab, aynı sıra ve metinler).
/// Düğmeye tıklanınca yeni tuşlar beklenir: Esc vazgeçer, Delete kısayolu kaldırır. Tuş başka bir işteyse oradan buraya
/// taşınır; başka bir uygulama ya da macOS kullanıyorsa uyarılır. Tuşlar bu pencerenin yerel dinleyicisiyle alınır;
/// yerel dinleyici yalnız CouchSubs'ın kendi tuş olaylarını görür, izin istemez.
struct ShortcutsCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var recording: Slot?
    @State private var message: String?
    @State private var error: String?
    @State private var monitor: Any?

    private struct Slot: Equatable {
        let action: HotkeyAction
        let slot: Int
    }

    var body: some View {
        Card {
            HintText(text: "Each action has two shortcuts, so it also works on keyboards without a numeric keypad. Click a shortcut and press the new keys. Backspace removes it, Esc cancels.")
            Grid(alignment: .leading, horizontalSpacing: Theme.space("s"), verticalSpacing: Theme.space("s")) {
                ForEach(HotkeyTable.order, id: \.self) { action in
                    GridRow {
                        Text(verbatim: HotkeyText.name(action))
                            .font(.csBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<HotkeyTable.slotCount, id: \.self) { slot in
                            button(Slot(action: action, slot: slot))
                        }
                    }
                }
            }
            if let message { HintText(text: LocalizedStringKey(message)) }
            if let error { ErrorText(error: error) }
            Button("Restore defaults") {
                stopRecording()
                message = nil
                error = nil
                model.settings.hotkeys = []
            }
            .buttonStyle(.secondary)
            HintText(text: "The shortcuts work only while translating, even when CouchSubs is in the background.")
        }
        .onDisappear(perform: stopRecording)
    }

    private func button(_ slot: Slot) -> some View {
        let key = HotkeyTable.key(model.settings.hotkeys, slot.action, slot: slot.slot)
        let title = recording == slot ? String(localized: "Press the keys…") : key?.label ?? String(localized: "Not set")
        return Button {
            if recording == slot { stopRecording() } else { startRecording(slot) }
        } label: {
            Text(verbatim: title).frame(minWidth: 120)
        }
        .buttonStyle(.secondary)
    }

    private func startRecording(_ slot: Slot) {
        stopRecording()
        message = nil
        error = nil
        recording = slot
        // Çeviri sürerken basılan tuş kısayol olarak çalışmasın, buraya gelsin.
        model.hotkeysPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    /// Yeni tuşu beklemeyi bırakır; kısayollar yeniden tutulur.
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        model.hotkeysPaused = false
    }

    /// Beklenen tuş geldi; olay yutulursa true.
    private func handle(_ event: NSEvent) -> Bool {
        guard let slot = recording else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: HotkeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let code = UInt32(event.keyCode)
        // Esc vazgeçer, Delete (geri silme ya da ileri silme) kısayolu kaldırır.
        if modifiers.isEmpty, code == 0x35 {
            stopRecording()
            return true
        }
        if modifiers.isEmpty, code == 0x33 || code == 0x75 {
            assign(slot, nil)
            return true
        }
        let chosen = HotkeyKey(modifiers, code)
        let problem = HotkeyTable.validate(chosen)
        guard problem == .none else {
            error = HotkeyText.problem(problem)
            return true
        }
        assign(slot, chosen)
        return true
    }

    private func assign(_ slot: Slot, _ key: HotkeyKey?) {
        // Kendi kısayollarımız bırakılmışken denenir: alınamıyorsa tuşu başka bir uygulama ya da macOS tutuyordur.
        let availability = key.map { GlobalHotkeys.availability(of: $0) } ?? .free
        let (choices, displaced) = HotkeyTable.assign(model.settings.hotkeys, slot.action, slot: slot.slot, key: key)
        stopRecording()
        model.settings.hotkeys = choices
        if let displaced, let key {
            message = String(format: String(localized: "%@ moved here from “%@”."), key.label, HotkeyText.name(displaced))
        } else {
            message = nil
        }
        switch (availability, key) {
        case (.takenByApp, let key?):
            error = String(format: String(localized: "Another app is using %@. It may not work while that app is open."), key.label)
        case (.system, let key?):
            error = String(format: String(localized: "macOS uses %@ for another task (System Settings › Keyboard › Keyboard Shortcuts). It may not work until you turn that off."), key.label)
        default:
            error = nil
        }
    }
}
