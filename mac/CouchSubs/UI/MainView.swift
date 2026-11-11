// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import RemotePlay
import SwiftUI

/// Ana ekran (bento): solda başlat/durdur, durum karoları ve uyarılar; sağda paket notu ve canlı altyazı.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            MainHeader()
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                ScrollView {
                    MainControls()
                        // Karoların parıltısı kırpılmasın.
                        .padding(Theme.space("m"))
                }
                .scrollIndicators(.never)
                .frame(width: Theme.size("mainColumn") + 2 * Theme.space("m"))
                .padding(-Theme.space("m"))
                VStack(alignment: .leading, spacing: Theme.space("gap")) {
                    PackInUseTile()
                    LiveSubtitlesTile()
                }
            }
        }
        .padding(Theme.space("screen"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $model.showSettings) { SettingsView().appSurface() }
    }
}

/// Logo, ad ve ayarlar düğmesi.
private struct MainHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            LogoView(size: 36)
            Text(verbatim: "CouchSubs").font(.csTitle)
            Spacer()
            Button { model.showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.secondary)
            .help(Text("Settings"))
        }
    }
}

/// Sol sütun: başlat/durdur, PS5 ve TV, altyazının yeri, çeviri motoru, kısayol, uyarılar.
private struct MainControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            StartStopButton()
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                StatusTile(symbol: "gamecontroller", title: "PS5", value: model.ps5StatusText,
                           tone: AppModel.ps5Tone(model.sessionState, running: model.isRunning))
                // Altyazı yalnız bilgisayar ekranındaysa TV durumu gösterilmez.
                if model.settings.output.showsOnTV { TVStatusTile() }
            }
            .fixedSize(horizontal: false, vertical: true)
            SubtitleOutputCard()
            HStack(alignment: .top, spacing: Theme.space("gap")) {
                StatusTile(symbol: "globe", title: "Translation", value: engineName)
                StatusTile(symbol: "keyboard", title: "Shortcut", value: String(localized: "Translate the screen (⌥⌘T)"))
            }
            .fixedSize(horizontal: false, vertical: true)
            MainWarnings()
        }
    }

    private var engineName: String {
        let engine = model.settings.translationEngine
        return engine == .free ? String(localized: "Free") : engine.displayName
    }
}

private struct StartStopButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { model.isRunning ? model.stop() : await model.start() }
        } label: {
            Label(model.isRunning ? "Stop translating" : "Start translating",
                  systemImage: model.isRunning ? "stop.fill" : "play.fill")
                .font(.csHeadline)
        }
        .buttonStyle(CSButtonStyle(kind: model.isRunning ? .danger : .primary, fullWidth: true, height: "primaryActionHeight"))
        .disabled(model.isStarting || (!model.isRunning && !model.canStart))
    }
}

private struct TVStatusTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hasTV {
            StatusTile(symbol: "tv", title: "TV",
                       value: model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Waiting for the TV app"),
                       tone: AppModel.tvTone(clients: model.tvClients, running: model.isRunning))
        } else {
            StatusTile(symbol: "tv", title: "TV", value: String(localized: "Not set up")) {
                Button("Connect a TV") { model.step = .tv }.buttonStyle(.secondary)
            }
        }
    }
}

/// Dil paketi eksik, çevrimiçi motor çeviremiyor, macOS yazıyı okuyamıyor.
private struct MainWarnings: View {
    @Environment(AppModel.self) private var model

    private var sourceName: String { Locale.current.localizedString(forLanguageCode: model.settings.sourceLanguage) ?? model.settings.sourceLanguage }
    private var targetName: String { Locale.current.localizedString(forLanguageCode: model.settings.targetLanguage) ?? model.settings.targetLanguage }

    var body: some View {
        if model.translatorStatus != .ready {
            Card {
                if model.translatorStatus == .needsDownload {
                    Label(String(format: String(localized: "The %@–%@ language pack is not downloaded yet."), sourceName, targetName),
                          systemImage: "arrow.down.circle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                    HintText(text: "Open System Settings › General › Language & Region › Translation Languages and download both languages.")
                    Button("Open Language & Region") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                    }
                    .buttonStyle(.secondary)
                } else {
                    Label(String(format: String(localized: "Translation from %@ to %@ is not available on this Mac."), sourceName, targetName),
                          systemImage: "exclamationmark.triangle")
                        .font(.csBody.weight(.semibold))
                        .foregroundStyle(Color.csWarning)
                }
            }
        }

        // Çevrimiçi motor çeviremiyor: satırlar bu arada ücretsiz çeviriyle geliyor.
        if model.isRunning, let issue = model.onlineIssue {
            Card {
                Label(String(format: String(localized: "%@ is not translating right now"), model.settings.onlineEngine.displayName),
                      systemImage: "exclamationmark.triangle")
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(Color.csWarning)
                Text(verbatim: TranslationCard.describe(issue, engine: model.settings.onlineEngine) + " "
                     + String(localized: "Meanwhile the free translation is used."))
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let free = model.readingFailedFreeGB {
            Card {
                Label("macOS can't read the text on the screen.", systemImage: "exclamationmark.triangle")
                    .font(.csBody.weight(.semibold))
                    .foregroundStyle(Color.csWarning)
                if free < 10 {
                    HintText(text: LocalizedStringKey(String(format: String(localized: "The disk is almost full (%.1f GB free). macOS needs free space to read text; free up a few GB and start the translation again."), free)))
                } else {
                    HintText(text: "Restart the Mac and start the translation again.")
                }
            }
        }
    }
}

/// Hazır Türkçe çevirisi olan oyunlar kullanılıyor (yalnız İngilizce→Türkçede ve ayar açıkken).
private struct PackInUseTile: View {
    @Environment(AppModel.self) private var model

    private var active: Bool {
        model.settings.gamePacks && model.settings.sourceLanguage == "en" && model.settings.targetLanguage == "tr"
            && !model.installedPacks.isEmpty
    }

    var body: some View {
        if active {
            HStack(spacing: Theme.space("m")) {
                TileIcon(symbol: "bolt.fill", tint: .csPro, background: .csProSoft)
                Text(verbatim: String(format: String(localized: "Game packs are on · %lld games translated in advance"), model.installedPacks.count))
                    .font(.csBody)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(.pro)
        }
    }
}

/// Son altyazı büyük, öncekiler altında soluk; çeviri sürerken karo parlar ve üst kenarında tarama ışığı akar.
private struct LiveSubtitlesTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("gap")) {
            HStack {
                Text("Live subtitles").font(.csHeadline)
                Spacer()
                if model.isRunning { Pill(text: String(localized: "Translating…"), tone: .success, live: true) }
            }
            if model.lastTranslation.isEmpty {
                HintText(text: "Subtitles will appear here while you play.")
            } else {
                CurrentLine(translation: model.lastTranslation, source: model.lastSource)
                SubtitleHistoryList()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) { if model.isRunning { ScanLight() } }
        .tile(model.isRunning ? .active : .plain)
    }
}

private struct CurrentLine: View {
    let translation: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("hair")) {
            Text(verbatim: translation)
                .font(.system(size: 28, weight: .semibold))
                .shadow(color: Color.csAccent.opacity(0.35), radius: 9)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: source)
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}

/// Kaçırılan satır buradan yeniden okunur (en yenisi üstte, eskiler giderek soluk).
private struct SubtitleHistoryList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = Array(model.history.entries.dropFirst())
        if !entries.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space("m")) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: Theme.space("m")) {
                            Divider().overlay(Color.csBorder)
                            HistoryRow(entry: entry).opacity(index == 0 ? 0.75 : 0.6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel(Text("Subtitle history"))
        }
    }
}

private struct HistoryRow: View {
    let entry: SubtitleHistory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("hair")) {
            Text(verbatim: entry.translation)
                .font(.csHeadline.weight(.regular))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source)
                .font(.csCaption)
                .foregroundStyle(Color.csSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}

/// Canlı altyazı karosunun üst kenarında soldan sağa akan ince sarı çizgi (azaltılmış harekette durur).
private struct ScanLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moving = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Capsule()
                .fill(LinearGradient(colors: [.clear, .csAccent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: width * 0.6, height: 2)
                .offset(x: moving ? width * 0.5 : -width * 0.1)
        }
        .frame(height: 2)
        .padding(.horizontal, Theme.space("xl"))
        .offset(y: -1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { moving = true }
        }
    }
}
