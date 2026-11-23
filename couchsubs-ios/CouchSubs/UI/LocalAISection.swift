// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// "Yerel model (Ollama, LM Studio)" motorunun alanları: Mac ve Windows'taki gibi sunucu adresi, model adı, isteğe bağlı
/// anahtar ve "Bağlantıyı dene" (Android'de aynı alanlar). Model telefonda çalışmaz: sunucu aynı ağdaki bir bilgisayardır,
/// adresi de o bilgisayarın ağ adresidir (ör. http://192.168.1.20:11434/v1). Ek talimat ayrı alanda (AIInstructionField).
struct PhoneLocalAISection: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var address = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var checking = false
    @State private var result: Result<String, AIFailure>?
    @FocusState private var focused: Field?

    private enum Field { case address, model }

    var body: some View {
        Text("Server address").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        TextField("Server address", text: $address, prompt: Text(verbatim: Self.example))
            .textFieldStyle(MobileFieldStyle())
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: .address)
            .onSubmit(commit)
        if !address.isEmpty, LocalAIServer.normalize(address) == nil {
            MobileNote(text: String(format: String(localized: "This address is not valid. Example: %@"), Self.example))
        }
        Text("Model name").font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        TextField("Model name", text: $modelName, prompt: Text(verbatim: LocalAIServer.defaultModel))
            .textFieldStyle(MobileFieldStyle())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: .model)
            .onSubmit(commit)
        Text("The model runs on a computer on the same Wi-Fi, not on this phone. Type that computer's network address. Ollama accepts other devices only when it is started with OLLAMA_HOST=0.0.0.0; in LM Studio, turn on Serve on Local Network.")
            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        Text("Type the model name as the server shows it. In Ollama, download it first: ollama pull qwen2.5:7b (downloaded models: ollama list). In LM Studio, load the model and start the local server.")
            .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
        if model.hasKey(.local) {
            HStack {
                Label(String(localized: "Key saved"), systemImage: "checkmark")
                    .font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.success)
                Spacer()
                Button("Remove key") {
                    model.removeKey(.local)
                    result = nil
                }
                .buttonStyle(MobileButtonStyle(kind: .secondary, compact: true))
            }
        } else {
            SecureField("API key (optional)", text: $key)
                .textFieldStyle(MobileFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        HStack(spacing: Mobile.Space.gap) {
            Button(checking ? LocalizedStringKey("Testing…") : LocalizedStringKey("Test connection")) { test() }
                .buttonStyle(MobileButtonStyle(kind: .secondary, compact: true))
                .disabled(checking || LocalAIServer.normalize(address) == nil)
            Spacer()
            Link("Download Ollama", destination: AIProvider.local.keyPage).font(Mobile.TypeScale.caption)
        }
        if let result {
            switch result {
            case .success(let sample):
                MobileNote(text: String(format: String(localized: "It works. Sample translation: %@"), sample), tone: Mobile.Palette.secondary)
            case .failure(let failure):
                MobileNote(text: LocalAIText.describe(OnlineKeyState(failure), server: model.settings.localAIServer,
                                                      keychainFailure: String(localized: "The API key could not be saved to this iPhone's keychain.")))
            }
        }
        EmptyView()
            .onAppear {
                address = model.settings.localAIBaseURL == LocalAIServer.ollamaURL ? "" : model.settings.localAIBaseURL
                modelName = model.settings.localAIModel
            }
            .onChange(of: focused) { _ in commit() }
            .onDisappear(perform: commit)
    }

    /// Telefonda örnek adres bilgisayarın ağ adresidir; 127.0.0.1 telefonun kendisidir.
    static let example = "http://192.168.1.20:11434/v1"

    private func commit() {
        if LocalAIServer.normalize(address) != nil, address != model.settings.localAIBaseURL { model.settings.localAIBaseURL = address }
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != model.settings.localAIModel { model.settings.localAIModel = name }
    }

    private func test() {
        commit()
        checking = true
        result = nil
        let typed = key
        Task {
            result = await model.testLocalAI(key: typed)
            if case .success = result { key = "" }
            checking = false
        }
    }
}
