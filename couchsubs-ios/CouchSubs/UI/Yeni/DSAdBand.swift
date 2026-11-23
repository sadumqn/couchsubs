// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit

/// Enmera'nın kendi uygulamalarının reklamı (Mac ve Windows'la aynı liste: design/yeni-arayuz/reklamlar.json). Üçüncü taraf
/// reklam ağı, izleme ya da kişisel veri yok; dokununca yalnız App Store sayfası açılır.
struct AdItem: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    let icon: UIImage?
    /// App Store bağlantısı; yoksa düğme pasif ve "Yakında" yazar (iPhone'da Google Play düğmesi gösterilmez).
    let appStore: URL?

    static func == (lhs: AdItem, rhs: AdItem) -> Bool { lhs.id == rhs.id }
}

enum AdCatalog {
    private struct File: Decodable {
        struct Ad: Decodable {
            let id: String
            let icon: String
            let title: [String: String]
            let text: [String: String]
            let appStore: String?
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
            let icon = Bundle.main.url(forResource: ad.icon, withExtension: nil, subdirectory: "reklam")
                .flatMap { UIImage(contentsOfFile: $0.path) }
            return AdItem(id: ad.id, title: ad.title[language] ?? ad.title["en"] ?? ad.id, text: ad.text[language] ?? ad.text["en"] ?? "",
                          icon: icon, appStore: ad.appStore.flatMap(URL.init(string:)))
        }
    }()
}

/// Uygulama ve ayar sayfalarının altında sabit ince reklam şeridi (56): solda uygulama simgesi, ortada başlık + tek satır
/// açıklama, sağda App Store düğmesi, sağ üstte küçük REKLAM etiketi. Reklamlar 6 sn arayla yukarı kayarak değişir
/// (Cebbin, Gramla, Bakkal). Kurulum, açılış, çeviri ve oyun görüntüsü ekranlarında yok.
struct DSAdBand: View {
    var items: [AdItem] = AdCatalog.band
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }

    var body: some View {
        if !items.isEmpty { band }
    }

    private var band: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile") + 2, style: .continuous)
        return ZStack {
            if let ad = items.indices.contains(index) ? items[index] : items.first {
                row(ad)
                    .id(ad.id)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity.combined(with: .offset(y: -8))))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .dsElevation(.card, in: shape)
        .overlay(alignment: .topTrailing) {
            Text("AD")
                .font(.dsAdTag)
                .tracking(DS.tracking("adTag"))
                .foregroundStyle(Color.dsFaint)
                .padding(.top, 4)
                .padding(.trailing, 12)
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
                withAnimation(DS.animation(.page, reduced: reduceMotion)) { index = (index + 1) % items.count }
            }
        }
    }

    private func row(_ ad: AdItem) -> some View {
        HStack(spacing: DS.space("s")) {
            Group {
                if let icon = ad.icon {
                    Image(uiImage: icon).resizable().interpolation(.high)
                } else {
                    Color.dsField
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius("small"), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius("small"), style: .continuous).strokeBorder(Color.dsBorder))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: ad.title).font(.system(.footnote, weight: .semibold)).foregroundStyle(Color.dsText).lineLimit(1)
                Text(verbatim: ad.text).font(.dsCaption).foregroundStyle(Color.dsMuted).tracking(DS.mutedTracking).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            StoreButton(url: ad.appStore)
                .padding(.top, 8)
        }
        .padding(.leading, 10)
        .padding(.trailing, DS.space("s"))
        .padding(.vertical, 8)
    }
}

/// Küçük App Store düğmesi (28 yükseklik, tam yuvarlak, ince halka). Bağlantı yoksa pasif ve "Yakında" yazar.
private struct StoreButton: View {
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "apple.logo").font(.caption2.weight(.semibold)).accessibilityHidden(true)
                if url == nil {
                    Text("Coming Soon").font(.caption.weight(.semibold))
                } else {
                    Text(verbatim: "App Store").font(.caption.weight(.semibold))
                }
            }
            .lineLimit(1)
            .foregroundStyle(url == nil ? Color.dsFaint : Color.dsText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.dsSurfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.dsBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .fixedSize()
    }
}
