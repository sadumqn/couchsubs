// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import FacebookCore
import GoogleSignIn
import RemotePlay
import SwiftUI
import UIKit

/// SDK'lar uygulama açılırken kurulur (Firebase, Meta); her biri yalnız anahtarı/dosyası varsa.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) var firebase = false
    private(set) var meta = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            firebase = Integrations.configureFirebase()
            meta = Integrations.configureMeta(application: application, options: options)
        }
        return true
    }
}

@main
struct CouchSubsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: PhoneModel
    @State private var account: AccountModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // AppDelegate bu noktada henüz çağrılmadı; Firebase burada da (bir kez) kurulur.
        let firebase = !testing && MainActor.assumeIsolated { Integrations.configureFirebase() }
        // Abonelerin paketleri sunucudan bu klasöre iner; hata ayıklamada uygulamayla gelen örnekler de okunur.
        let library = GamePackLibrary(bundled: AppConfig.useBundledPacks ? GamePackLibrary.bundledDirectory : nil,
                                      user: PackStore.filesDirectory(in: PackStore.defaultDirectory))
        let model = testing ? PhoneModel(store: EphemeralStore(), packs: library)
            : Self.demoStore().map { PhoneModel(store: $0, packs: library) } ?? PhoneModel(packs: library)
        // Çeviri sürerken ekran kararmaz: iOS kilitlenen ya da arka plana geçen uygulamayı askıya alır.
        model.keepScreenAwake = { UIApplication.shared.isIdleTimerDisabled = $0 }

        let accounts: AccountService = firebase ? FirebaseAccounts() : UnavailableAccounts()
        let subscriptions: SubscriptionService = (!testing ? AppConfig.revenueCatAPIKey : nil)
            .map { RevenueCatSubscriptions(apiKey: $0, appUserID: accounts.user?.uid) } ?? UnavailableSubscriptions()
        let analytics = AppAnalytics(firebase: firebase, meta: !testing && AppConfig.facebookAppID != nil)
        let store = AppConfig.packsBaseURL.map { url in
            PackStore(baseURL: url, directory: PackStore.defaultDirectory, token: { @MainActor [accounts] in try await accounts.idToken() })
        }
        let account = AccountModel(accounts: accounts, subscriptions: subscriptions, analytics: analytics, packStore: store, library: library)
        model.onAnalytics = { [analytics] event in analytics.log(event) }
        account.onPacksChanged = { [weak model] unlocked in model?.packsUnlocked = unlocked; model?.reloadPackList() }
        model.packsUnlocked = account.packsUnlocked
        analytics.identify(accounts.user?.uid)
        _model = State(initialValue: model)
        _account = State(initialValue: account)
    }

    /// Hata ayıklama: COUCHSUBS_DEMO=1 ile kurulum bitmiş gibi açılır (ekran görüntüsü ve tasarım denetimi için;
    /// PS5'e bağlanmaz). Anahtarlığa dokunmaz.
    private static func demoStore() -> CouchSubsCore.AppStore? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["COUCHSUBS_DEMO"] == "1" else { return nil }
        let store = EphemeralStore()
        store.save(Data([1, 2, 3]), for: StoreKey.accountId)
        store.save(RegisteredConsole(host: "192.168.1.103", name: "PS5-002", registKey: Data(), morning: Data()), for: StoreKey.console)
        store.save(true, for: StoreKey.setupComplete)
        return store
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(account)
                .appSurface()
                // Google ve Meta girişlerinin dönüş adresleri.
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if AppConfig.facebookAppID != nil {
                        ApplicationDelegate.shared.application(UIApplication.shared, open: url, sourceApplication: nil, annotation: nil)
                    }
                }
                .task { await account.start() }
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
    @Environment(AccountModel.self) private var account
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @AppStorage("accountPrompted") private var accountPrompted = false
    @State private var signInFirst = false
    @State private var path: [Route] = []

    var body: some View {
        Group {
            if !welcomeSeen {
                WelcomeFlow(onSignIn: { finishWelcome(signIn: true) }, onFinish: { finishWelcome(signIn: false) })
            } else if !accountPrompted && account.user == nil {
                SignUpScreen(startInSignIn: signInFirst, onSkip: { accountPrompted = true }, onBack: { welcomeSeen = false })
                    .onChange(of: account.user) { _, user in if user != nil { accountPrompted = true } }
            } else if model.step != .done {
                setup
            } else {
                home
            }
        }
        .preferredColorScheme(.dark)
        .tint(Mobile.Palette.accent)
    }

    private func finishWelcome(signIn: Bool) {
        signInFirst = signIn
        welcomeSeen = true
        if model.step == .welcome { model.advance() }
        // İzin akışı tanıtımdan sonra, uygulama öndeyken (Apple'ın izleme izni bağlamsız sorulmasın).
        Task { await Integrations.requestConsent(meta: AppConfig.facebookAppID != nil, firebase: AppConfig.hasFirebase) }
    }

    /// Kurulum: PSN girişi → PS5 eşleme → altyazının yeri.
    @ViewBuilder private var setup: some View {
        switch model.step {
        case .welcome, .psnLogin:
            PSNScreen(onBack: account.user == nil ? { accountPrompted = false } : nil) {
                if model.step == .welcome { model.advance() }
                model.advance()
            }
        case .console:
            PS5PairScreen(onBack: { model.back() }) { model.advance() }
        case .output, .done:
            TargetScreen(onBack: { model.back() }) { model.advance() }
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            Group {
                if model.isRunning { RunningScreen(path: $path) } else { HomeScreen(path: $path) }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings: SettingsScreen(path: $path)
                case .profile: ProfileScreen(path: $path)
                case .account: AccountDetailsScreen()
                case .subscription: SubscriptionScreen()
                case .packs: PacksScreen()
                case .target: TargetScreen(setup: false) { path.removeLast() }
                case .ps5: PS5PairScreen(onBack: { path.removeLast() }) { path.removeLast() }
                case .psn: PSNScreen(onBack: { path.removeLast() }) { path.removeLast() }
                case .about: AboutScreen()
                }
            }
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if !account.tourDone && path.isEmpty && !model.isRunning {
                CoachTour(anchors: anchors) { withAnimation { account.tourDone = true } }
            }
        }
    }
}
