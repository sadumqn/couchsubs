// SPDX-License-Identifier: AGPL-3.0-only
// Ayarlar. Geçici, sade yerleşim (sistem formu): onaylanan tasarım gelince yeniden çizilecek.

import CouchSubsCore
import SwiftUI

struct SettingsScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var checking = false
    @State private var keyResult: String?
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Translation") {
                    Picker("Translation engine", selection: $model.settings.translationEngine) {
                        Text("Free (on this device)").tag(TranslationEngine.free)
                        ForEach(TranslationEngine.allCases.filter { $0 != .free }, id: \.self) { engine in
                            Text(verbatim: engine.displayName).tag(engine)
                        }
                    }
                    let engine = model.settings.translationEngine
                    if engine != .free {
                        if model.hasKey(engine) {
                            Label("Key saved", systemImage: "checkmark.circle.fill").foregroundStyle(Color.csSuccess)
                            Button("Remove key", role: .destructive) { model.removeKey(engine) }
                        } else {
                            SecureField("API key", text: $key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Save and test") { Task { await save(engine) } }
                                .disabled(checking || key.isEmpty)
                        }
                        if let keyResult { Text(verbatim: keyResult).font(.csCallout).foregroundStyle(Color.csSecondary) }
                    }
                }
                Section("Game packs") {
                    Toggle("Use the ready Turkish translations of game packs", isOn: $model.settings.gamePacks)
                    ForEach(model.installedPacks) { pack in
                        LabeledContent(pack.title, value: pack.entries.formatted())
                    }
                }
                Section("Subtitles") {
                    Picker("Show subtitles", selection: $model.settings.output) {
                        Text("On the TV").tag(SubtitleOutput.tv)
                        Text("On this phone").tag(SubtitleOutput.computer)
                        Text("On both").tag(SubtitleOutput.both)
                    }
                    Stepper(value: $model.settings.style.fontSize, in: 24...96, step: 4) {
                        LabeledContent("Text size", value: model.settings.style.fontSize.formatted())
                    }
                    Picker("Text colour", selection: $model.settings.style.textColor) {
                        Text("White").tag(SubtitleTextColor.white)
                        Text("Yellow").tag(SubtitleTextColor.yellow)
                    }
                    Toggle("Bold text", isOn: $model.settings.style.bold)
                    Button("Send test subtitle") { model.sendTestSubtitle() }
                }
                Section {
                    Toggle("Share lines missing from the packs (anonymous)", isOn: $model.settings.sharePool)
                } footer: {
                    Text("English lines that no game pack has yet are sent without any personal data, so the packs grow.")
                }
                Section {
                    Button("Set up again…", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Set up again?", isPresented: $confirmReset) {
                Button("Set up again", role: .destructive) {
                    model.resetSetup()
                    dismiss()
                }
            }
        }
    }

    private func save(_ engine: TranslationEngine) async {
        checking = true
        keyResult = nil
        let accepted = await model.saveKey(key, for: engine)
        keyResult = accepted ? nil : String(localized: "The key did not work. Check it and try again.")
        if accepted { key = "" }
        checking = false
    }
}
