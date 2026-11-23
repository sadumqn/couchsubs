// SPDX-License-Identifier: AGPL-3.0-only
// TV uygulaması kurulumunun ortak görünüm parçaları (yeni arayüz): TV kartları ve durum rozetleri, tarama göstergesi,
// markanın ön koşul listesi, canlı adım çizelgesi ve hata kutusu. Kurulumun işleyişi TVInstallScreen ve LGPhoneInstall'da;
// burada yalnız sunum var. Metinler TVText'ten (Android, Mac, Windows ile aynı).

import CouchSubsCore
import SwiftUI

/// Kurulumun durumu (her marka için aynı).
enum TVInstallPhase: Equatable {
    case idle
    case working(InstallStep)
    case done(version: String, installed: Bool)
    case failed(text: String)

    var isWorking: Bool { if case .working = self { true } else { false } }
    var isDone: Bool { if case .done = self { true } else { false } }
}

/// Açıklama ve bilgi notu.
struct InstallIntro: View {
    let body1: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Mobile.Space.titleToBody) {
            Text(verbatim: body1).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.text).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: note).dsMuted()
        }
    }
}

/// Liste başlığı ("Ağdaki Samsung TV'ler") ve tarama sürerken yanında küçük gösterge.
struct InstallListTitle: View {
    let text: String
    var searching = false

    var body: some View {
        HStack(spacing: Mobile.Space.inline) {
            Text(verbatim: text).font(Mobile.TypeScale.cardTitle).foregroundStyle(Mobile.Palette.text)
            Spacer(minLength: 0)
            if searching {
                DSSearchRings(size: 22)
                Text(verbatim: TVText.searching).font(Mobile.TypeScale.caption).foregroundStyle(Mobile.Palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tarama sürerken listenin yerinde duran boş kart.
struct InstallSearching: View {
    var body: some View {
        // Perde arama halkası: amber eş merkezli halkalar (Core Animation; hareket azaltılmışken durağan).
        Tile {
            HStack(spacing: Mobile.Space.gap) {
                DSSearchRings(size: 40)
                Text(verbatim: TVText.searching).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: Mobile.Control.row, alignment: .leading)
        }
    }
}

/// Numaralı bilgi adımları (seçenek gibi görünmez): küçük numara yuvarlağı + metin, aralar 12. `highlight` bu telefonun
/// adresiyse kutunun içinde kopyala simgesiyle gösterilir (Samsung'da Host PC IP olarak yazılır).
struct InstallSteps: View {
    let title: String
    let steps: [String]
    var highlight: String?
    var after: [String] = []

    var body: some View {
        Tile(spacing: Mobile.Space.gap) {
            SectionTitle(LocalizedStringKey(title))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in NumberedStep(text: step, fallback: index + 1) }
            if let highlight {
                if Self.isAddress(highlight) {
                    DSCopyField(text: highlight)
                        .padding(.leading, NumberedStep.indent)
                } else {
                    MobileNote(text: highlight)
                }
            }
            ForEach(Array(after.enumerated()), id: \.offset) { index, step in NumberedStep(text: step, fallback: steps.count + index + 1) }
        }
    }

    /// "192.168.1.20" gibi IPv4 adresi mi (yoksa "adres bulunamadı" uyarısı).
    static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}

/// Bir bilgi adımı: metin "1. …" ile başlıyorsa numara yuvarlağa alınır.
struct NumberedStep: View {
    let text: String
    let fallback: Int
    static let indent: CGFloat = 24 + Mobile.Space.gap

    var body: some View {
        let parts = Self.split(text)
        HStack(alignment: .firstTextBaseline, spacing: Mobile.Space.gap) {
            Text(verbatim: "\(parts.number ?? fallback)")
                .font(.system(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(Mobile.Palette.text)
                .frame(width: 24, height: 24)
                .background(Mobile.Palette.surface2, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .accessibilityHidden(true)
            Text(verbatim: parts.text).font(Mobile.TypeScale.body).foregroundStyle(Mobile.Palette.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "3. Metin" → (3, "Metin"); numarasız metin olduğu gibi kalır.
    static func split(_ text: String) -> (number: Int?, text: String) {
        guard let dot = text.firstIndex(of: "."), let number = Int(text[..<dot]), number < 100 else { return (nil, text) }
        return (number, text[text.index(after: dot)...].trimmingCharacters(in: .whitespaces))
    }
}

/// Ağda görülen bir TV kartı: dokunulabilir (ince halka, sağda seçim yuvarlağı), seçiliyken amber halka ve hafif dolgu.
/// Simge, ad, model ve IP, altında durum rozeti (Bulundu, Geliştirici Modu Açık/Kapalı…).
struct InstallCandidateRow: View {
    let name: String
    let detail: String
    var status: (String, Bool)?
    let selected: Bool
    var symbol = "tv"

    var body: some View {
        // Perde TV kartı: simge karesi (seçiliyken amber), ad + mono ayrıntı, durum hapı; seçiliyken 2 pt amber kenar,
        // amber yumuşak dolgu ve ışıma.
        Tile(emphasis: selected ? .selected : .none, spacing: Mobile.Space.inline) {
            HStack(alignment: .top, spacing: Mobile.Space.gap) {
                DSIconSquare(symbol: symbol, tone: selected ? .amber : .gray, size: 40)
                VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                    Text(verbatim: name).font(Mobile.TypeScale.headline).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: detail).font(.system(.caption, design: .monospaced)).foregroundStyle(Mobile.Palette.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let status {
                        DSBadge(text: status.0, tone: status.1 ? .ok : .warn).padding(.top, Mobile.Space.hair)
                    } else {
                        DSBadge(text: String(localized: "Found"), tone: .unknown).padding(.top, Mobile.Space.hair)
                    }
                }
                Spacer(minLength: 0)
                DSRadio(on: selected).padding(.top, Mobile.Space.inline)
            }
        }
        .contentShape(Rectangle())
        .onChange(of: selected) { on in if on { Haptics.selection() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Adım çizelgesi

/// Kurulumun altı aşaması; her `InstallStep` birine düşer.
enum InstallStage: Int, CaseIterable {
    case connect, approve, send, install, open, ready

    init(_ step: InstallStep) {
        switch step {
        case .connecting, .reading, .pairing: self = .connect
        case .approveOnTV, .key, .signIn, .openPlay: self = .approve
        case .certificate, .signing: self = .send
        case .installing, .uninstalling: self = .install
        case .launching: self = .open
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .connect: "Connecting"
        case .approve: "Approval on the TV"
        case .send: "Sending the App"
        case .install: "Installing"
        case .open: "Opening"
        case .ready: "Ready"
        }
    }
}

/// Canlı adım çizelgesi: geçilen aşamalar yeşil tik, süren aşama amber gösterge ve altında o anki ayrıntı, kalanlar gri.
struct InstallTimeline: View {
    let step: InstallStep?
    var done = false

    var body: some View {
        let current = done ? InstallStage.ready : step.map(InstallStage.init) ?? .connect
        VStack(alignment: .leading, spacing: 0) {
            ForEach(InstallStage.allCases, id: \.rawValue) { stage in
                let state: Int = done || stage.rawValue < current.rawValue ? 2 : stage == current ? 1 : 0
                HStack(alignment: .top, spacing: Mobile.Space.gap) {
                    VStack(spacing: 0) {
                        marker(state)
                        if stage != .ready {
                            Rectangle().fill(state == 2 ? Color.dsAmber : Color.dsBorderStrong).frame(width: 2).frame(minHeight: Mobile.Space.gap)
                        }
                    }
                    VStack(alignment: .leading, spacing: Mobile.Space.hair) {
                        Text(stage.title)
                            .font(state == 1 ? Mobile.TypeScale.headline : Mobile.TypeScale.body)
                            .foregroundStyle(state == 0 ? Mobile.Palette.tertiary : Mobile.Palette.text)
                        if state == 1, !done, let step {
                            Text(verbatim: installStepText(step)).dsMuted()
                        }
                    }
                    .padding(.bottom, stage == .ready ? 0 : Mobile.Space.gap)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func marker(_ state: Int) -> some View {
        ZStack {
            switch state {
            case 2:
                Circle().fill(Color.dsAmber)
                Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(Color.dsOnAmber)
            case 1:
                Circle().fill(Color.dsSurfaceRaised)
                    .overlay(Circle().strokeBorder(Color.dsAmber, lineWidth: 2))
                    .shadow(color: Color.dsAmberGlow, radius: 7)
                DSBarsLoader(scale: 0.6)
            default:
                Circle().fill(Color.dsField)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Sonuç

/// Kurulumun sonucu: canlı çizelge, başarı ya da hata kutusu (neden, numaralı çözüm, günlüğü paylaşma).
struct InstallResult: View {
    let phase: TVInstallPhase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working(let step):
            Tile { InstallTimeline(step: step) }
        case .done(let version, let installed):
            Tile(emphasis: .selected, spacing: Mobile.Space.gap) {
                // Perde başarı anı (≤ 1 sn; hareket azaltılmışken yalnız tik).
                DSCelebration(size: 64)
                    .frame(maxWidth: .infinity)
                InstallTimeline(step: nil, done: true)
                Label(installed ? TVText.done(version) : TVText.upToDate(version), systemImage: "checkmark.circle.fill")
                    .font(Mobile.TypeScale.headline).foregroundStyle(Mobile.Palette.successText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: TVText.next).dsMuted()
            }
        case .failed(let text):
            InstallErrorBox(text: text)
        }
    }
}

/// Hata kutusu: kırmızı ince çerçeve; üstte "Kurulum Tamamlanamadı", ilk cümle başlık (neden), kalan cümleler numaralı
/// çözüm adımları, ayrıntılar (TV'nin yanıtı) gri; altta Günlüğü Paylaş. "Yeniden Dene" kutunun hemen altındaki ana düğme.
struct InstallErrorBox: View {
    let text: String

    var body: some View {
        let parsed = Self.parse(text)
        Tile(emphasis: .danger, spacing: Mobile.Space.gap) {
            Label("Installation Didn't Finish", systemImage: "exclamationmark.triangle.fill")
                .font(Font.dsLabel)
                .foregroundStyle(Mobile.Palette.danger)
            Text(verbatim: parsed.title).font(Mobile.TypeScale.cardTitle).foregroundStyle(Mobile.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, step in
                NumberedStep(text: step, fallback: index + 1)
            }
            ForEach(Array(parsed.extra.enumerated()), id: \.offset) { _, paragraph in
                Text(verbatim: paragraph).dsMuted()
            }
            ShareLink(item: InstallLog.shared.file) { Label(TVText.shareLog, systemImage: "square.and.arrow.up") }
                .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: false))
        }
        // Kutu belirince hata titreşimi.
        .onAppear { Haptics.error() }
    }

    /// İlk paragrafın ilk cümlesi başlık, kalan cümleleri numaralı adımlar; sonraki paragraflar ayrıntı.
    static func parse(_ text: String) -> (title: String, steps: [String], extra: [String]) {
        let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = paragraphs.first else { return (text, [], []) }
        let sentences = sentences(first)
        return (sentences.first ?? first, Array(sentences.dropFirst()), Array(paragraphs.dropFirst()))
    }

    /// Cümlelere böler: nokta, soru ya da ünlem + boşluk + büyük harf ya da rakam (adres ve sürüm numaraları bölünmez).
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            if ".?!".contains(character), index + 2 < characters.count, characters[index + 1] == " ",
               characters[index + 2].isUppercase || characters[index + 2] == "“" || characters[index + 2] == "\"" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                index += 1
            }
            index += 1
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
        return result
    }
}
