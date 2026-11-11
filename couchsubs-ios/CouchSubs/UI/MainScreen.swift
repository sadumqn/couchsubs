// SPDX-License-Identifier: AGPL-3.0-only
// Ana ekran. Geçici, sade yerleşim: onaylanan tasarım gelince yeniden çizilecek.

import CouchSubsCore
import SwiftUI
import Translation

struct MainScreen: View {
    @Environment(PhoneModel.self) private var model
    @State private var showSettings = false
    @State private var showSubtitles = false
    /// Apple'ın çeviri dil paketini indirme isteği (iOS indirme penceresini kendisi gösterir).
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space("l")) {
                    Button {
                        Task { model.isRunning ? model.stop() : await model.start() }
                    } label: {
                        Label(model.isRunning ? "Stop translating" : "Start translating",
                              systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(CSButtonStyle(kind: model.isRunning ? .danger : .primary, fullWidth: true, height: "primaryActionHeight"))
                    .disabled(model.isStarting || (!model.isRunning && !model.canStart))

                    // iOS arka plandaki uygulamanın ağ bağlantısını keser; telefon açık ve uygulama önde kalmalı.
                    HintText(text: "Keep CouchSubs open on the screen while you play. iOS stops the connection when the app goes to the background; the screen stays on while translating.")

                    Card {
                        StatusRow(title: "PS5", value: model.ps5StatusText,
                                  tone: model.sessionState == .streaming ? .good : model.isRunning ? .warning : .idle)
                        if model.settings.output.showsOnTV {
                            Divider().overlay(Color.csBorder)
                            StatusRow(title: "TV", value: model.hasTV ? model.tvStatusText : String(localized: "Not set up"),
                                      tone: model.tvClients > 0 ? .good : model.isRunning ? .warning : .idle)
                        }
                    }
                    if model.tvAppMissing { TVAppMissingNote() }
                    if model.settings.output.showsOnComputer {
                        Button("Show subtitles on this phone") { showSubtitles = true }
                            .buttonStyle(CSButtonStyle(kind: .secondary, fullWidth: true))
                    }
                    if model.translatorStatus == .needsDownload {
                        Card {
                            Label("The English–Turkish language pack is not downloaded yet.", systemImage: "arrow.down.circle")
                                .foregroundStyle(Color.csWarning)
                            Button("Download") {
                                download = TranslationSession.Configuration(source: Locale.Language(identifier: model.settings.sourceLanguage),
                                                                            target: Locale.Language(identifier: model.settings.targetLanguage))
                            }
                            .buttonStyle(.secondary)
                        }
                    }
                    if model.isRunning, model.onlineIssue != nil {
                        HintText(text: "The online translation is not answering right now. Meanwhile the free translation is used.")
                    }
                    Card(title: "Last subtitle") {
                        if model.lastFromPack {
                            Label("From the game pack", systemImage: "shippingbox").font(.csCaption).foregroundStyle(Color.csAccentText)
                        }
                        if model.lastTranslation.isEmpty {
                            HintText(text: "Subtitles will appear here while you play.")
                        } else {
                            Text(verbatim: model.lastTranslation).font(.csTitle)
                            Text(verbatim: model.lastSource).font(.csCallout).foregroundStyle(Color.csSecondary)
                        }
                    }
                    if model.history.entries.count > 1 {
                        Card(title: "Subtitle history") {
                            ForEach(model.history.entries.dropFirst()) { entry in
                                VStack(alignment: .leading, spacing: Theme.space("xs")) {
                                    Text(verbatim: entry.translation).font(.csBody)
                                    Text(verbatim: entry.source).font(.csCallout).foregroundStyle(Color.csSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.space("xl"))
            }
            .background(Color.csBackground)
            .navigationTitle(Text(verbatim: "CouchSubs"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .fullScreenCover(isPresented: $showSubtitles) { SubtitleScreen() }
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await model.refreshTranslatorStatus()
            }
            .task { await model.refreshTranslatorStatus() }
        }
    }
}

/// Telefon ekranındaki altyazı ("TV'm yok"): siyah zemin, büyük yazı, yatay.
struct SubtitleScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.space("s")) {
                ForEach(model.phoneLines) { line in
                    Text(verbatim: line.text)
                        .font(.system(size: CGFloat(model.settings.style.fontSize), weight: model.settings.style.bold ? .bold : .semibold))
                        .foregroundStyle(textColor)
                        .opacity(line.fading ? 0.4 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(.horizontal, Theme.space("xl"))
            .padding(.bottom, Theme.space("xxl"))
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                .foregroundStyle(Color.white.opacity(0.6))
                .padding()
                .accessibilityLabel(Text("Close"))
        }
        .statusBarHidden()
        .onAppear { Orientation.request(.landscape) }
        .onDisappear { Orientation.request(.portrait) }
    }

    private var textColor: Color {
        switch model.settings.style.textColor {
        case .yellow: .csAccent
        case .white: .white
        }
    }
}

/// Altyazı ekranı açılınca telefon yataya döner.
enum Orientation {
    @MainActor
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}
