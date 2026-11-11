// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI
import UIKit

@main
struct CouchSubsApp: App {
    @State private var model = Self.makeModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Testler uygulamanın içinde çalışır; gerçek Anahtarlığa dokunmazlar.
    private static func makeModel() -> PhoneModel {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let model = testing ? PhoneModel(store: EphemeralStore()) : PhoneModel()
        // Çeviri sürerken ekran kararmaz: iOS kilitlenen ya da arka plana geçen uygulamayı askıya alır.
        model.keepScreenAwake = { UIApplication.shared.isIdleTimerDisabled = $0 }
        return model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .appSurface()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.becameActive()
            case .background: Task { await model.flushPool() }
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        if model.step == .done { MainScreen() } else { OnboardingScreen() }
    }
}
