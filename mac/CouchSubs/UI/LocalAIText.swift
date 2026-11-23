// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import Foundation

/// Yerel model (Ollama, LM Studio) sunucusunun durum iletileri; Mac ve iPhone ayarları ortak kullanır
/// (couchsubs-ios/project.yml). `keychainFailure`: anahtar kaydedilemediğinde platformun iletisi.
enum LocalAIText {
    static func describe(_ state: OnlineKeyState, server: LocalAIServer?, keychainFailure: String) -> String {
        let server = server ?? LocalAIServer(baseURL: LocalAIServer.ollamaURL, model: LocalAIServer.defaultModel)!
        switch state {
        case .valid:
            return String(localized: "It works.")
        case .keychainWriteFailed:
            return keychainFailure
        case .invalid:
            return String(localized: "The local model server did not accept the API key. Check the key, or remove it if the server does not need one.")
        case .quotaExceeded:
            return String(localized: "The local model server is busy. Try again in a moment.")
        case .modelRejected:
            if server.kind == .lmStudio {
                return String(format: String(localized: "LM Studio does not have the model %@. Download and load it in LM Studio, or check the model name."), server.model)
            }
            return String(format: String(localized: "The model %1$@ is not on the local server. Download it: ollama pull %1$@"), server.model)
        case .unreachable, .busy:
            switch server.kind {
            case .ollama:
                return String(format: String(localized: "Ollama is not running: %1$@ could not be reached, or the model did not answer in time. Open Ollama and download the model: ollama pull %2$@"), server.address, server.model)
            case .lmStudio:
                return String(format: String(localized: "LM Studio is not running: %@ could not be reached, or the model did not answer in time. Open LM Studio, load the model and start the local server."), server.address)
            case .other:
                return String(format: String(localized: "The local model server at %@ could not be reached, or the model did not answer in time. Check the address and that the server is running."), server.address)
            }
        }
    }
}
