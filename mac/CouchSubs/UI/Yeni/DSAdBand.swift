// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI

/// Enmera'nın kendi uygulamalarının reklamı. Üçüncü taraf reklam ağı, izleme ya da kişisel veri yok: liste uygulamanın
/// içinde (design/yeni-arayuz/reklamlar.json; Windows aynı dosyayı okur), tıklanınca yalnız mağaza bağlantısı açılır.
struct AdItem: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    let icon: NSImage?
    /// Mağaza bağlantısı; yoksa düğme pasif ve "Yakında" yazar.
    let appStore: URL?
    let googlePlay: URL?

    static func == (lhs: AdItem, rhs: AdItem) -> Bool { lhs.id == rhs.id }
}

enum AdCatalog {
    static let home = URL(string: "https://enmera.com.tr")!

    private struct File: Decodable {
        struct Ad: Decodable {
            let id: String
            let icon: String
            let title: [String: String]
            let text: [String: String]
            let appStore: String?
            let googlePlay: String?
        }

        let ads: [Ad]
    }

    /// Banttaki reklamlar, uygulamanın diline göre (Türkçe değilse İngilizce). Dosya yoksa ya da bozuksa bant görünmez.
    static let band: [AdItem] = {
        guard let url = Bundle.main.url(forResource: "reklamlar", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true ? "tr" : "en"
        return file.ads.map { ad in
            let icon = Bundle.main.url(forResource: ad.icon, withExtension: nil, subdirectory: "reklam").flatMap(NSImage.init(contentsOf:))
            return AdItem(id: ad.id, title: ad.title[language] ?? ad.title["en"] ?? ad.id, text: ad.text[language] ?? ad.text["en"] ?? "",
                          icon: icon, appStore: ad.appStore.flatMap(URL.init(string:)), googlePlay: ad.googlePlay.flatMap(URL.init(string:)))
        }
    }()
}

/// Uygulama ve ayar sayfalarının altında sabit 64 pt reklam bandı (Perde: e1 yüzey, 18 köşe, üst kenar parlaması): sağ
/// üstte REKLAM etiketi, reklamlar 6 sn arayla yukarı kayarak değişir; solda uygulama simgesi, ortada başlık + açıklama,
/// sağda App Store ve Google Play düğmeleri. Liste boşsa bant yok.
/// Kurulum, açılış ve oyun görüntüsü pencerelerinde gösterilmez.
struct DSAdBand: View {
    var items: [AdItem] = AdCatalog.band
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsMotionOff) private var motionOff

    var body: some View {
        if !items.isEmpty { band }
    }

    private var band: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile") + 2, style: .continuous)
        return ZStack {
            if let ad = items.indices.contains(index) ? items[index] : items.first {
                row(ad)
                    .id(ad.id)
                    .transition(reduceMotion || motionOff
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity.combined(with: .offset(y: -8))))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DS.size("adBand"))
        .dsElevation(.card, in: shape)
        .overlay(alignment: .topTrailing) {
            Text("AD")
                .font(.dsAdTag)
                .tracking(DS.tracking("adTag"))
                .foregroundStyle(Color.dsFaint)
                .padding(.top, DS.space("unitHint"))
                .padding(.trailing, DS.space("xs"))
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Advertisement"))
        .task(id: items.count) {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(DS.tokens.motion.adRotate * 1_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(DS.animation(.page, reduced: reduceMotion || motionOff)) { index = (index + 1) % items.count }
            }
        }
    }

    private func row(_ ad: AdItem) -> some View {
        HStack(spacing: DS.space("s")) {
            Group {
                if let icon = ad.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Color.dsField
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.dsBorder))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.space("line")) {
                Text(verbatim: ad.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dsText).lineLimit(1)
                Text(verbatim: ad.text).font(.dsSmall).foregroundStyle(Color.dsMuted).tracking(DS.mutedTracking).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: DS.space("s"))
            // REKLAM etiketi sağ üstte; düğmeler dikeyde ortalı ve 28 yüksek, etiketin altında kalır.
            HStack(spacing: DS.space("xs")) {
                StoreButton(name: "App Store", symbol: "apple.logo", url: ad.appStore)
                StoreButton(name: "Google Play", symbol: "play.fill", url: ad.googlePlay)
            }
            .padding(.top, DS.space("xs"))
        }
        .padding(.leading, DS.space("s") - 2)
        .padding(.trailing, DS.space("m"))
    }
}

/// Küçük mağaza düğmesi (28 yükseklik, tam yuvarlak, ince halka). Bağlantı yoksa pasif: soluk ve "Yakında" yazar.
private struct StoreButton: View {
    let name: String
    let symbol: String
    let url: URL?
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: DS.space("unitHint")) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                Text(verbatim: name).font(.system(size: 12, weight: .semibold))
                if url == nil {
                    Text("Coming Soon").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.dsFaint)
                }
            }
            .lineLimit(1)
            .foregroundStyle(url == nil ? Color.dsFaint : Color.dsText)
            .padding(.horizontal, DS.space("s"))
            .frame(height: 28)
            .background(hovering && url != nil ? Color.dsSurfaceHigh : Color.dsSurfaceRaised, in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(hovering && url != nil ? Color.dsBorderStrong : Color.dsBorder))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .onHover { hovering = $0 }
        .fixedSize()
    }
}
