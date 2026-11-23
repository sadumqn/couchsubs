// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI
import UniformTypeIdentifiers

/// Geçmiş (tuval 16): arama kutusu ve kaynak seçici (Tümü / Paket / Çeviri); tabloda Saat, Türkçe, İngilizce, Kaynak;
/// altta oyun · gün · satır sayısı, Dışa Aktar ve Hatalı Çeviriyi Bildir. Satıra tıklanınca seçilir (bildirim o satırla
/// açılır), sağ tıkla kopyalanır. Eski Geçmiş sayfasındaki Tümünü Kopyala ve Temizle de buradadır.
struct HistoryPage: View {
    enum Filter: Hashable { case all, pack, engine }

    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var selected: Int?
    @State private var confirmClear = false
    @State private var copiedAll = false
    @Environment(\.dsChromeInsets) private var chrome

    var body: some View {
        let rows = filtered
        // Sayfa pencere boyu tek kaydırma: arama satırı, tablo kartı (başlık, satırlar, alt bilgi). İçerik üst ve alt cam
        // çubuğun arkasından kayar; kart en az çubukların arasındaki yüksekliği doldurur (kesik kenar, boş şerit yok).
        GeometryReader { outer in
            let free = max(outer.size.height - chrome.top - chrome.bottom - 2 * DS.space("l"), 0)
            ScrollView(.vertical) {
                VStack(spacing: DS.space("m")) {
                    HStack(spacing: DS.space("s")) {
                        DSFieldChrome {
                            HStack(spacing: DS.space("s")) {
                                Image(systemName: "magnifyingglass").foregroundStyle(Color.dsMuted).accessibilityHidden(true)
                                TextField("Search History", text: $query).textFieldStyle(.plain)
                            }
                        }
                        DSTabs(selection: $filter, items: [(.all, "All"), (.pack, "Pack"), (.engine, "Translation")], fill: true)
                            .frame(width: 360)
                    }
                    VStack(spacing: 0) {
                        header
                        if rows.isEmpty {
                            VStack(spacing: DS.space("m")) {
                                DSIconSquare(symbol: model.history.entries.isEmpty ? "captions.bubble" : "magnifyingglass", tone: .gray, size: 48)
                                Text(model.history.entries.isEmpty ? "No subtitles yet. Lines translated while you play appear here." : "No lines match this search.")
                                    .dsMuted(.dsBody)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(DS.space("xxl"))
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(rows, id: \.id) { entry in row(entry) }
                            }
                            Spacer(minLength: 0)
                        }
                        DSDivider()
                        footer(count: rows.count)
                    }
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
                    .dsElevation(.card, in: RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
                }
                .frame(minHeight: free, alignment: .top)
                .padding(DS.space("l"))
                .padding(.top, chrome.top)
                .padding(.bottom, chrome.bottom)
            }
            .scrollIndicators(.automatic)
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.clearHistory() }
        } message: {
            Text("All saved lines are removed from this computer.")
        }
    }

    private var filtered: [SubtitleHistory.Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr"))
        return model.history.entries.filter { entry in
            switch filter {
            case .all: break
            case .pack: guard entry.origin == .pack else { return false }
            case .engine: guard entry.origin == .engine else { return false }
            }
            guard !needle.isEmpty else { return true }
            return (entry.translation + " " + entry.source).lowercased(with: Locale(identifier: "tr")).contains(needle)
        }
    }

    private static let columns: (time: CGFloat, source: CGFloat) = (72, 96)

    private var header: some View {
        HStack(spacing: DS.space("m")) {
            DSMonoLabel("Time").frame(width: Self.columns.time, alignment: .leading)
            DSMonoLabel("Turkish").frame(maxWidth: .infinity, alignment: .leading)
            DSMonoLabel("English").frame(maxWidth: .infinity, alignment: .leading)
            DSMonoLabel("Source").frame(width: Self.columns.source, alignment: .leading)
        }
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("m"))
        .overlay(alignment: .bottom) { DSDivider() }
    }

    private func row(_ entry: SubtitleHistory.Entry) -> some View {
        let isSelected = selected == entry.id
        return HStack(alignment: .center, spacing: DS.space("m")) {
            Text(verbatim: entry.date.formatted(date: .omitted, time: .shortened))
                .font(HistoryRowStyle.timeFont)
                .foregroundStyle(HistoryRowStyle.time)
                .frame(width: Self.columns.time, alignment: .leading)
            Text(verbatim: entry.translation).font(.system(size: 14, weight: .semibold)).foregroundStyle(HistoryRowStyle.translation)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source).font(.dsSmall).foregroundStyle(HistoryRowStyle.source).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                DSStatusChip(entry.origin == .pack ? "Pack" : "Translation", tone: entry.origin == .pack ? .amber : .muted,
                             icon: entry.origin == .pack ? "shippingbox.fill" : nil)
                Spacer(minLength: 0)
            }
            .frame(width: Self.columns.source)
        }
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("s"))
        .background(isSelected ? Color.dsAmberSoft : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected { Capsule(style: .circular).fill(Color.dsAmber).frame(width: 3).padding(.vertical, DS.space("xs")) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.dsTileBorder).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selected = isSelected ? nil : entry.id }
        .contextMenu {
            Button("Copy") { copy("\(entry.translation)\n\(entry.source)") }
            Button("Report a Wrong Translation") { report(entry) }
        }
        .textSelection(.enabled)
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: DS.space("xs")) {
            Text(verbatim: summary(count)).font(.dsSmall).foregroundStyle(Color.dsMuted).lineLimit(1)
            Spacer(minLength: DS.space("s"))
            Button(copiedAll ? "Copied" : "Copy All") {
                copy(SubtitleHistory.plainText(model.history.entries))
                copiedAll = true
            }
            .disabled(model.history.entries.isEmpty)
            .resetsAfterDelay($copiedAll)
            Button("Export") { export() }.disabled(model.history.entries.isEmpty)
            Button("Report a Wrong Translation") { report(model.history.entries.first { $0.id == selected } ?? model.history.entries.first) }
                .disabled(model.history.entries.isEmpty)
            Button("Clear History") { confirmClear = true }.disabled(model.history.entries.isEmpty)
        }
        .buttonStyle(SmallSecondary())
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("s"))
    }

    private func summary(_ count: Int) -> String {
        if let game = model.gameChoice.game?.name {
            return String(format: String(localized: "%@ · Today · %lld Lines"), game, count)
        }
        return String(format: String(localized: "Today · %lld Lines"), count)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Geçmişi düz metin olarak kaydeder (Tümünü Kopyala ile aynı biçim).
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CouchSubs-\(Date().formatted(.iso8601.year().month().day())).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SubtitleHistory.plainText(model.history.entries).write(to: url, atomically: true, encoding: .utf8)
    }

    /// GitHub'da hazır doldurulmuş bir sorun bildirimi açar: satırın İngilizcesi, Türkçesi, kaynağı ve oyun. Hiçbir şey
    /// kendiliğinden gönderilmez; kullanıcı tarayıcıda düzeltip gönderir.
    private func report(_ entry: SubtitleHistory.Entry?) {
        guard let entry else { return }
        let game = model.gameChoice.game?.name ?? "-"
        let body = """
        **Oyun / Game:** \(game)
        **İngilizce / English:** \(entry.source)
        **Çeviri / Translation:** \(entry.translation)
        **Kaynak / Source:** \(entry.origin == .pack ? "pack" : model.settings.translationEngine.rawValue)
        **Doğrusu / Correct translation:**\u{20}
        """
        var components = URLComponents(url: AppIdentity.sourceURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "title", value: "Hatalı çeviri: \(entry.source.prefix(60))"),
                                  URLQueryItem(name: "body", value: body)]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }
}

/// Geçmiş satırının yazı renkleri (kontrast testi bunları ölçer: çeviri ≥ 7:1, kaynak ve saat ≥ 4.5:1, iki temada,
/// kart yüzeyinde ve seçili satırın amber zemininde).
enum HistoryRowStyle {
    static let translationToken = "text"
    static let sourceToken = "muted"
    static let timeToken = "muted"
    static let translation = DS.color(translationToken)
    static let source = DS.color(sourceToken)
    static let time = DS.color(timeToken)
    /// Saat sayıdır: sans, sabit genişlikte rakamlar (sütun hizalı).
    static let timeFont = Font.system(size: 12, weight: .medium).monospacedDigit()
}

/// Geçmiş altındaki küçük ikincil düğmeler (40 yükseklik, 13 pt).
private struct SmallSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SmallBody(configuration: configuration)
    }

    private struct SmallBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .padding(.horizontal, DS.space("m"))
                .frame(height: DS.size("tab"))
                .background(hovering || configuration.isPressed ? Color.dsSurfaceHigh : Color.dsSurfaceRaised, in: Capsule(style: .circular))
                .overlay(Capsule(style: .circular).inset(by: 0.5).stroke(hovering ? Color.dsBorderStrong : Color.dsBorder))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule(style: .circular))
                .onHover { hovering = $0 }
        }
    }
}
