// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI

/// Ana ekranın saniyede iki kez yenilenen bilgileri: son kare, kare hızı, sessizlik süresi, gecikme geçmişi. Model her
/// karede yayın yapmaz; yalnız bunu izleyen küçük görünümler yeniden çizilir.
@MainActor
final class HomeTicker: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var fps = 0
    @Published private(set) var now = Date()
    @Published private(set) var delays: [Int] = []
    private var lastCount = 0
    private var lastAt = Date()
    private var lastMetrics: LineMetrics?

    func tick(_ model: AppModel) {
        let date = Date()
        if model.lastFrame !== image { image = model.lastFrame }
        let elapsed = date.timeIntervalSince(lastAt)
        if elapsed >= 1 {
            let value = model.isRunning ? Int((Double(model.frameCount - lastCount) / elapsed).rounded()) : 0
            if value != fps { fps = max(0, value) }
            lastCount = model.frameCount
            lastAt = date
        }
        if let metrics = model.lastMetrics, metrics != lastMetrics {
            lastMetrics = metrics
            delays = Array((delays + [metrics.totalMs]).suffix(10))
        }
        if !model.isRunning, !delays.isEmpty, model.sessionHistory.isEmpty { delays = [] }
        // Saat yalnız çeviri sürerken ya da sorun kartı açıkken ilerler (dakikalık hız, sessizlik süresi); boşta ekran
        // saniyede iki kez yeniden çizilmez (boşta ≤ %2 işlemci).
        if model.isRunning || HomeProblem.current(model, now: date) != nil { now = date }
    }
}

/// Ana ekran (Perde, tuval DL-Mac-Ana): solda perde (oyun görüntüsü, okunan alan, altyazı plakası, canlı nabız) ve altında
/// üç düğme; sağda dört durum karosu (konsol, TV, oyun, çeviri) ve Canlı Akış ya da sorun varken sessizlik nedeni kartı.
/// Oyun sorulunca "Hangi Oyun?" kartı ekranın üstünde açılır. Çeviri sürerken yalnız canlı nabız atar (hareket kapısı).
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ticker = HomeTicker()
    @Environment(\.dsChromeInsets) private var chrome

    var body: some View {
        ZStack {
            // Sayfa pencere boyu kayar; üst ve alt cam çubuğun arkasından geçer. İlk açılışta perde ve düğme satırı
            // çubukların arasında tam görünür. Sağ sütun perde + düğmelerle aynı yükseklikte.
            GeometryReader { outer in
                let gap = DS.space("l")
                let width = max(outer.size.width - 2 * gap, 0)
                let free = outer.size.height - chrome.top - chrome.bottom
                let left = HomeStage.leftWidth(total: width, gap: gap, availableHeight: free - 2 * gap)
                let height = HomeStage.height(width: left)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: gap) {
                        HomeStage(ticker: ticker).frame(width: left, height: height)
                        RightColumn(ticker: ticker).frame(maxWidth: .infinity).frame(height: height)
                    }
                    .padding(gap)
                    // Uzun pencerede kalan boşluk düğme satırı ile reklam bandı arasında tek şerit olarak kalmaz: içerik
                    // çubukların arasında dikeyde ortalanır (iki sütunun alt kenarı zaten aynı hizada).
                    .frame(minHeight: max(free, 0))
                    .padding(.top, chrome.top)
                    .padding(.bottom, chrome.bottom)
                }
                .scrollIndicators(.automatic)
            }
            GamePickerOverlay(choice: model.gameChoice, areas: model.gameAreas)
        }
        .task {
            while !Task.isCancelled {
                ticker.tick(model)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

// MARK: Perde ve düğmeler

/// Perde kahramanı: kart çerçevesi yok; 16:9 perde sütunu tam doldurur, düğme satırı aynı genişlikte (16 aralık).
private struct HomeStage: View {
    @ObservedObject var ticker: HomeTicker

    static let gap = DS.space("m")

    /// Perde + aralık + düğme satırı.
    static func height(width: CGFloat) -> CGFloat {
        (width * 9 / 16).rounded(.down) + gap + DS.size("button")
    }

    /// Sol sütun genişliği: en az 2/3; pencere uzunsa perde boş yüksekliği dolduracak kadar (en çok %70) büyür, sağ
    /// sütun karoları okunur genişlikte kalır.
    static func leftWidth(total: CGFloat, gap: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let base = (total - gap) * 2 / 3
        let fill = (availableHeight - Self.gap - DS.size("button")) * 16 / 9
        return min(max(base, fill), (total - gap) * 0.7).rounded(.down)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(spacing: Self.gap) {
                HomePerde(ticker: ticker).frame(width: width, height: (width * 9 / 16).rounded(.down))
                HomeButtons().frame(width: width)
            }
        }
    }
}

/// Perde: oyunun son karesi (yoksa sıcak sahne), üstte durağan projeksiyon ışığı, okunan alan (kesikli amber), son çeviri
/// altyazı plakasında (konuşan adı amber; boşta örnek plaka), sağ üstte cam hap (kaynak + kare hızı).
private struct HomePerde: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker
    @Environment(\.dsMotionGate) private var gate

    var body: some View {
        let running = model.isRunning
        let shape = RoundedRectangle(cornerRadius: DS.radius("preview"), style: .continuous)
        Color(red: 0.043, green: 0.043, blue: 0.051)
            .overlay {
                if let image = ticker.image {
                    Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                } else {
                    DSPerdeScene()
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.4), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay { DSProjectorLight() }
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    let area = Self.rect(model.settings.region, size: size)
                    ZStack(alignment: .topLeading) {
                        AreaFrame(rect: area)
                        if running, !model.lastTranslation.isEmpty {
                            let parts = SpeakerSplit(model.lastTranslation)
                            DSSubtitlePlate(speaker: parts.speaker, line: parts.line, speakerColor: .dsAmber, size: 17)
                                .lineLimit(3)
                                .frame(maxWidth: size.width * 0.78)
                                .position(x: size.width / 2, y: Self.plateY(area: area, height: size.height))
                                .id(model.lastTranslation)
                                .transition(.opacity.combined(with: .offset(y: 8)))
                        } else if !running, ticker.image == nil {
                            // Boşta örnek plaka: altyazının nerede ve nasıl görüneceğini gösterir.
                            DSSubtitlePlate(line: String(localized: "Subtitles will appear here while you play."), size: 17)
                                .lineLimit(2)
                                .frame(maxWidth: size.width * 0.78)
                                .position(x: size.width / 2, y: Self.plateY(area: area, height: size.height))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            // Çeviri durumu tek yerde: üst çubuktaki hap ("Çeviri Açık"). Perdede yalnız kaynak ve kare hızı.
            .overlay(alignment: .topTrailing) {
                if running {
                    GlassPill { Text(verbatim: frameRate) }
                        .padding(DS.space("s"))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.06)))
            // Perdenin altına düşen yumuşak amber yansıma (durağan gölge).
            .shadow(color: Color.dsAmberGlow.opacity(running ? 0.45 : 0.25), radius: 26, y: 14)
            .animation(DS.animation(.page, gate: gate), value: model.lastTranslation)
    }

    /// "PS5 · Saniyede 10 Kare" (pencereden okunurken kaynak adı yok).
    private var frameRate: String {
        let rate = String(format: String(localized: "%lld Frames/s"), ticker.fps)
        let source: String? = model.isXbox ? "Xbox" : (model.readsCaptureWindow ? nil : "PS5")
        guard let source else { return rate }
        return source + " · " + rate
    }

    static func rect(_ region: CropRegion, size: CGSize) -> CGRect {
        CGRect(x: region.left * size.width, y: region.top * size.height,
               width: max(0, region.right - region.left) * size.width, height: max(0, region.bottom - region.top) * size.height)
    }

    /// Plaka okunan alanın ortasında; alan çok inceyse perdenin alt beşte birinde.
    static func plateY(area: CGRect, height: CGFloat) -> CGFloat {
        guard area.height > 24 else { return height * 0.82 }
        return min(max(area.midY, height * 0.12), height * 0.9)
    }
}

/// Okunan alan: amber kesikli çerçeve ve "Okunan Alan" etiketi. Durağan (çeviri sürerken sürekli animasyon yok).
private struct AreaFrame: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: DS.radius("control"), style: .continuous)
            .strokeBorder(Color.dsAmber.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(width: rect.width, height: rect.height)
            .overlay(alignment: .topLeading) {
                Text("Area Read")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dsOnAmber)
                    .padding(.horizontal, DS.space("xs"))
                    .frame(height: 22)
                    .background(Color.dsAmber, in: Capsule(style: .circular))
                    .offset(x: DS.space("s"), y: -11)
            }
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

/// "Jason: Tamam." → ("Jason:", "Tamam."); adı olmayan satır olduğu gibi.
struct SpeakerSplit {
    let speaker: String?
    let line: String

    init(_ text: String) {
        if let range = text.range(of: ": "), text.distance(from: text.startIndex, to: range.lowerBound) <= 24,
           !text[..<range.lowerBound].contains(where: { ".!?\n".contains($0) }) {
            speaker = String(text[..<range.lowerBound]) + ":"
            line = String(text[range.upperBound...])
        } else {
            speaker = nil
            line = text
        }
    }
}

/// Perdenin üstündeki cam hap (e3). Yazı sans; sayılar sabit genişlikte (kare hızı değişirken hap titremez).
private struct GlassPill<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        label
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color(red: 0.953, green: 0.933, blue: 0.894))
        .padding(.horizontal, DS.space("s"))
        .frame(height: 28)
        .background {
            Capsule(style: .circular).fill(.ultraThinMaterial)
            Capsule(style: .circular).fill(Color.black.opacity(0.45))
        }
        .overlay(Capsule(style: .circular).strokeBorder(Color.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
    }
}

/// Çeviriyi Başlat/Durdur (1.3 pay), Ekranı Çevir, TV'de Dene (1'er pay); 12 aralık. Sürerken düğme "…ıyor…" yazar,
/// çubuk yükleyici gösterir ve basılamaz.
private struct HomeButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let gap = DS.space("s")
            let unit = (geometry.size.width - 2 * gap) / 3.3
            HStack(spacing: gap) {
                mainButton.frame(width: unit * 1.3)
                Button("Translate the Screen") { model.translateScreen() }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
                    .frame(width: unit)
                    .disabled(!model.isRunning)
                    .help(Text(HotkeyText.title(model.settings, .screen, String(localized: "Translate the screen (%@)"))))
                testButton.frame(width: unit)
            }
        }
        .frame(height: DS.size("button"))
    }

    @ViewBuilder private var mainButton: some View {
        if model.demoMode {
            Button("Exit Demo Mode") { model.exitDemo() }
                .buttonStyle(DSButtonStyle(kind: .stop, fullWidth: true))
                .accessibilityIdentifier("demoModeExit")
        } else if model.isRunning {
            Button("Stop Translating") { model.stop() }
                .buttonStyle(DSButtonStyle(kind: .stop, fullWidth: true))
                .keyboardShortcut(.defaultAction)
        } else {
            Button(model.isStarting ? "Starting…" : "Start Translating") { Task { await model.start() } }
                .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true, busy: model.isStarting))
                .disabled(model.isStarting || !model.canStart)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var testButton: some View {
        let onTV = model.settings.output.showsOnTV
        return Button(model.openingTVAppForTest ? "Opening the App on the TV…" : onTV ? "Try on TV" : "Try on Screen") {
            Task { await model.testSubtitle() }
        }
        .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true, busy: model.openingTVAppForTest))
        .disabled((onTV && !model.hasTV && !model.settings.output.showsOnComputer) || model.openingTVAppForTest)
        .help(Text(onTV ? "Sends a sample subtitle to the TV." : "Shows a sample subtitle on this computer's screen."))
    }
}

// MARK: Sağ sütun

private struct RightColumn: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker

    var body: some View {
        VStack(spacing: DS.space("m")) {
            StatusTiles(choice: model.gameChoice)
            HomeNotices()
            if let problem = HomeProblem.current(model) {
                ProblemCard(problem: problem, ticker: ticker)
            } else {
                LiveFeedCard(ticker: ticker)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Durum karoları

/// Dört karo (2 × 2): renkli simge karesi, küçük anahtar + durum noktası, kalın değer ve mono ek bilgi. Tıklanınca ilgili
/// ayara gider.
private struct StatusTiles: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var choice: GameChoice

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: DS.space("s")), GridItem(.flexible(), spacing: DS.space("s"))]
        LazyVGrid(columns: columns, spacing: DS.space("s")) {
            consoleTile
            tvTile
            HomeTile(key: "Game", value: choice.game?.name ?? String(localized: "Not Recognized"),
                       detail: gameHasPack ? String(localized: "Pack") : nil,
                       tone: choice.game == nil ? .idle : .good, icon: .cover(choice.game?.name)) { choice.ask() }
            HomeTile(key: "Translation", value: engineName, detail: languages,
                       tone: model.translatorStatus == .ready ? .good : .warning, icon: .symbol("sparkles", .sky)) {
                model.openSettings(.advanced)
            }
        }
    }

    @ViewBuilder private var consoleTile: some View {
        let tone = model.demoMode ? StatusTone.good : AppModel.ps5Tone(model.sessionState, running: model.isRunning)
        if model.demoMode {
            HomeTile(key: "Demo Mode", value: String(localized: "Sample pictures"), detail: nil, tone: tone,
                       icon: .symbol("play.rectangle", .amber)) { model.openSettings(.console) }
        } else if model.readsCaptureWindow {
            HomeTile(key: "Window", value: model.settings.captureWindow?.title ?? model.pictureSourceName,
                       detail: shortState, tone: tone, icon: .symbol("macwindow", .gray)) { model.openSettings(.console) }
        } else if model.isXbox {
            HomeTile(key: "Xbox · Beta", value: model.xboxConsole?.name ?? "Xbox", detail: shortState, tone: tone,
                       icon: .symbol("gamecontroller", .olive)) {
                if model.needsXboxLink { model.linkXbox() } else { model.openSettings(.console) }
            }
        } else if model.settings.frameSource == .remotePlayWindow {
            HomeTile(key: "PS5", value: String(localized: "Remote Play Window on This Mac"), detail: shortState, tone: tone,
                       icon: .symbol("gamecontroller", .gray)) { model.openSettings(.console) }
        } else {
            HomeTile(key: "PS5", value: model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? String(localized: "Not Set Up"),
                       detail: shortState, tone: tone, icon: .symbol("gamecontroller", .gray)) { model.openSettings(.console) }
        }
    }

    @ViewBuilder private var tvTile: some View {
        if !model.settings.output.showsOnTV {
            HomeTile(key: "Computer Screen", value: model.settings.output == .obs ? String(localized: "OBS Only (Streaming)") : String(localized: "This Mac"),
                       detail: nil, tone: .good, icon: .symbol("laptopcomputer", .teal)) { model.openSettings(.outputs) }
        } else if let tv = model.tv, model.hasTV {
            HomeTile(key: "TV", value: tv.name, detail: tvDetail, tone: model.tvAppOutdated != nil ? .warning
                       : AppModel.tvTone(clients: model.tvClients, running: model.isRunning), icon: .symbol("tv", .amber)) {
                model.openSettings(.outputs)
            }
        } else {
            HomeTile(key: "TV", value: String(localized: "Not Set Up"), detail: nil, tone: .idle, icon: .symbol("tv", .gray)) { model.step = .tv }
        }
    }

    private var tvDetail: String? {
        if case .upToDate(let version) = model.tvApp { return version }
        return model.tvClients > 0 ? nil : model.tvStatusText
    }

    private var shortState: String? {
        switch model.sessionState {
        case .streaming: String(localized: "Connected")
        case .connecting: String(localized: "Connecting…")
        case .disconnected: model.isRunning ? String(localized: "Not Connected") : nil
        }
    }

    private var gameHasPack: Bool {
        guard let name = choice.game?.name else { return false }
        let key = GameName.key(name)
        return GameCatalog.packShelf(model.installedPacks).contains { item in item.titles.contains { GameName.key($0) == key } }
    }

    private var engineName: String {
        let engine = model.settings.translationEngine
        return engine == .free ? String(localized: "Free Translation") : engine.displayName
    }

    private var languages: String {
        "\(model.settings.sourceLanguage.uppercased())→\(model.settings.targetLanguage.uppercased())"
    }
}

/// Tek karo: e1 yüzey, 16 köşe; solda 36'lık simge karesi (oyun karosunda kapak), üstte 12 pt anahtar + durum noktası,
/// altında 15 pt yarı kalın değer ve mono ek bilgi. Üzerine gelince güçlü kenar.
private struct HomeTile: View {
    enum Icon {
        case symbol(String, DSIconSquare.Tone)
        case cover(String?)
    }

    let key: LocalizedStringKey
    let value: String
    let detail: String?
    let tone: StatusTone
    let icon: Icon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        Button(action: action) {
            HStack(spacing: DS.space("s")) {
                iconView
                VStack(alignment: .leading, spacing: DS.space("line")) {
                    HStack(spacing: DS.space("xxs")) {
                        Text(key).font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1)
                        Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    // Uzun ad iki satıra kırılır (kesilmez); tam ad ipucunda.
                    Text(verbatim: value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dsText).lineLimit(2)
                        .minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(verbatim: detail).font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.dsMuted).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space("s"))
            .padding(.vertical, DS.space("xs"))
            .frame(maxWidth: .infinity, minHeight: DS.size("option"), alignment: .leading)
            .dsElevation(.card, in: shape)
            .overlay(hovering ? shape.strokeBorder(Color.dsBorderStrong) : nil)
            .contentShape(shape)
        }
        .buttonStyle(DSFocusPlainStyle(cornerRadius: DS.radius("tile")))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .help(Text(verbatim: value))
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case let .symbol(name, tint):
            DSIconSquare(symbol: name, tone: tint, size: 36)
        case let .cover(title):
            if let title {
                DSCoverArt(seed: title)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                DSIconSquare(symbol: "questionmark", tone: .gray, size: 36)
            }
        }
    }

    private var dot: Color {
        switch tone {
        case .good: .dsSuccess
        case .warning: .dsLive
        case .idle: .dsFaint
        }
    }
}

// MARK: Canlı Akış

/// Canlı Akış: başlık + "Geçmiş ›", durum hapı (Altyazı Akıyor / Çeviri Durdu), üç küçük sayı (satır + dakikalık hız
/// çizgisi, paketten gelen oran, ortalama gecikme) ve bu oturumun son satırları (konuşan adı amber, Türkçe kalın,
/// İngilizcesi gri; eski satırlar solar).
private struct LiveFeedCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker
    @Environment(\.dsMotionGate) private var gate

    var body: some View {
        let entries = model.isRunning ? model.sessionHistory : []
        let packCount = entries.filter { $0.origin == .pack }.count
        let percent = entries.isEmpty ? 0 : Int((Double(packCount) / Double(entries.count) * 100).rounded())
        let perMinute = entries.filter { ticker.now.timeIntervalSince($0.date) <= 60 }.count
        let feed = Array(model.sessionHistory.prefix(30))
        DSCard(padding: DS.space("l"), spacing: DS.space("s"), scrolls: false) {
            DSCardHeader("Live feed") {
                Button {
                    model.showHistory = true
                } label: {
                    HStack(spacing: DS.space("xxs")) {
                        Text("History")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                    }
                    .font(.dsSmall)
                    .foregroundStyle(Color.dsMuted)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: DS.space("s")) {
                Stat(value: "\(entries.count)", caption: String(format: String(localized: "Lines · %lld/min"), perMinute)) {
                    Sparkline(values: Self.buckets(entries, now: ticker.now))
                }
                Stat(value: "\(packCount)", caption: String(format: String(localized: "From Pack · %lld%%"), percent)) { EmptyView() }
                Stat(value: ticker.delays.isEmpty ? "–" : "\(ticker.delays.reduce(0, +) / ticker.delays.count) ms",
                     caption: String(localized: "Average Delay")) { EmptyView() }
                    .help(Text(verbatim: model.lastMetrics?.summary ?? ""))
            }
            DSDivider()
            if feed.isEmpty {
                DSStatusChip(model.isRunning ? "Waiting for Subtitles" : "Translation Stopped", tone: model.isRunning ? .amber : .muted)
                Text("Subtitles will appear here while you play.").dsMuted()
                if model.showsSubtitleOffTip {
                    Text("CouchSubs reads the English subtitles on screen, not the audio. Turn on the game's own subtitles.").dsMuted()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: DS.space("s")) {
                        ForEach(Array(feed.enumerated()), id: \.element.id) { index, entry in
                            FeedLine(entry: entry)
                                .opacity(index == 0 ? 1 : index < 3 ? 0.8 : 0.55)
                                .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .animation(DS.animation(.page, gate: gate), value: feed.first?.id)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Son 6 dakikanın 30 sn'lik dilimlerindeki satır sayısı (12 değer).
    static func buckets(_ entries: [SubtitleHistory.Entry], now: Date) -> [Double] {
        var counts = Array(repeating: 0.0, count: 12)
        for entry in entries {
            let age = now.timeIntervalSince(entry.date)
            guard age >= 0, age < 360 else { continue }
            counts[11 - Int(age / 30)] += 1
        }
        return counts
    }

    private struct Stat<Graphic: View>: View {
        let value: String
        let caption: String
        @ViewBuilder var graphic: Graphic

        var body: some View {
            VStack(alignment: .leading, spacing: DS.space("line")) {
                Text(verbatim: value).font(.system(size: 17, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Color.dsText).lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: caption).font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1).minimumScaleFactor(0.8)
                graphic.frame(height: Graphic.self == EmptyView.self ? 0 : 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Akıştaki bir satır: konuşan (amber, küçük), Türkçe (kalın), İngilizce (gri).
private struct FeedLine: View {
    let entry: SubtitleHistory.Entry

    var body: some View {
        let parts = SpeakerSplit(entry.translation)
        VStack(alignment: .leading, spacing: DS.space("line")) {
            if let speaker = parts.speaker {
                Text(verbatim: String(speaker.dropLast())).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.dsAmberText)
            }
            Text(verbatim: parts.line).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.dsText).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source).font(.dsCaption).foregroundStyle(Color.dsMuted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let top = max(values.max() ?? 0, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                        y: geometry.size.height - geometry.size.height * 0.85 * CGFloat(value / top) - 2)
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.dsAmber.opacity(0.35), Color.dsAmber.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.dsAmberLine, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
