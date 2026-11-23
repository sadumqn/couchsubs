// SPDX-License-Identifier: AGPL-3.0-only

import ImageIO
import SwiftUI
import UIKit

/// promo.json'ı arka planda çeker ve gösterilecek popup'ı görseliyle hazırlar. Ağ hatası sessizdir. Görsel yalnız bellekte
/// tutulur (diske önbellek yok); gösterilip kapatılınca bırakılır. İstekte çerez, kimlik ya da cihaz bilgisi gitmez.
@MainActor
final class PromoController: ObservableObject {
    struct Ready {
        let popup: PromoPopup
        let image: UIImage
    }

    @Published private(set) var ready: Ready?
    /// Uygulamanın son ön plana geldiği an: popup bundan 10 sn sonra açılır.
    private(set) var foregroundAt = Date()
    private var popup: PromoPopup?
    private var fetchedAt: Date?
    private var busy = false
    private let defaults: UserDefaults
    /// Testlerde ağa çıkılmaz.
    private let enabled: Bool
    private static let shownIdKey = "promo.shownId"
    private static let shownAtKey = "promo.shownAt"

    /// Önbelleksiz, çerezsiz oturum: istekte kimlik ya da önceki yanıtlardan iz gitmez.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = PromoPolicy.timeout
        configuration.timeoutIntervalForResource = PromoPolicy.timeout * 2
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init(defaults: UserDefaults = .standard, enabled: Bool = true) {
        self.defaults = defaults
        self.enabled = enabled
    }

    var record: PromoRecord {
        PromoRecord(id: defaults.string(forKey: Self.shownIdKey), shownAt: defaults.object(forKey: Self.shownAtKey) as? Date)
    }

    /// Uygulama ön plana geldi: promo.json soğuk açılışta (süreçte ilk kez) ve sonra en çok günde bir çekilir; popup
    /// zamanı geldiyse görseli indirilir. `setupDone` false ise (karşılama, kurulum ya da ilk tur sürüyor) hiçbir şey
    /// yapılmaz: yeni kullanıcı ilk açılışında tanıtım görmez.
    func refresh(setupDone: Bool) async {
        guard enabled else { return }
        foregroundAt = Date()
        guard setupDone else {
            ready = nil
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let now = Date()
        if fetchedAt.map({ now.timeIntervalSince($0) >= PromoPolicy.refetchInterval }) ?? true {
            // promo.json'a ulaşılamazsa uygulamayla gelen açılır reklam (Mac ve Windows'taki reklamlar.json › popups).
            if let data = await download(PromoPolicy.configURL, limit: PromoPolicy.maxConfigBytes) {
                popup = PromoPolicy.parse(data)
                fetchedAt = now
            } else {
                popup = Self.bundledPopup
            }
        }
        guard let popup, PromoPolicy.due(popup, record: record, now: now) else {
            ready = nil
            return
        }
        // Görsel zaten hazırsa yeniden inmez; yalnız yeni girişin 10 sn'si beklenir. Uygulamadaki görsel yüklenemezse
        // açılır reklam hiç açılmaz (yer tutucu yok).
        let image: UIImage
        if let current = ready, current.popup == popup {
            image = current.image
        } else if popup.bundled {
            guard let url = Bundle.main.url(forResource: popup.image, withExtension: nil, subdirectory: "reklam"),
                  let data = try? Data(contentsOf: url), let decoded = Self.decode(data) else { return }
            image = decoded
        } else {
            guard let imageURL = PromoPolicy.httpsURL(popup.image) else {
                ready = nil
                return
            }
            guard let data = await download(imageURL, limit: PromoPolicy.maxImageBytes),
                  let decoded = Self.decode(data) else { return }
            image = decoded
        }
        ready = nil
        // Girişten 10 sn dolmadan yayımlanmaz (beklerken yeniden ön plana gelindiyse yeni girişten sayılır); ekran o an
        // boştaysa popup hemen açılır.
        while true {
            let wait = foregroundAt.addingTimeInterval(PromoPolicy.showDelay).timeIntervalSinceNow
            guard wait > 0 else { break }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if Task.isCancelled { return }
        }
        ready = Ready(popup: popup, image: image)
    }

    /// Uygulamayla gelen açılır reklam (reklamlar.json, project.yml kaynaklarında); dosya yoksa nil.
    private static let bundledPopup: PromoPopup? = Bundle.main.url(forResource: "reklamlar", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap(PromoPolicy.bundled)

    /// Popup kapatıldı (X ya da görsele dokunma): gösterim kaydedilir, görsel bırakılır.
    func dismissed(_ popup: PromoPopup) {
        defaults.set(popup.id, forKey: Self.shownIdKey)
        defaults.set(Date(), forKey: Self.shownAtKey)
        ready = nil
    }

    private func download(_ url: URL, limit: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("CouchSubs-iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= limit else { return nil }
        return data
    }

    /// Görsel en çok ~1440 px'e küçültülerek açılır (telefon ekranı için yeter, bellek az tutulur).
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1440,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Tanıtım popup'ı (Android'deki PromoOverlay ile aynı): bulanık ve %75 siyah zemin, üstte ortada "Sponsorlu" rozeti,
/// ortada dikey görsel (9:16; kırpılmaz, oranı korunarak sığar, köşeler yuvarlak), sağ üst köşeye çaprazlama oturan açık
/// renkli yuvarlak kapat (X): görünen daire 36 pt, dokunma alanı 44 pt. Görsele dokununca bağlantı sistem tarayıcısında açılır.
struct PromoOverlay: View {
    let ready: PromoController.Ready
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL
    private let radius: CGFloat = 24
    private let closeTouch: CGFloat = 44
    private let closeDot: CGFloat = 36
    /// "Sponsorlu" rozetinin yeri; görselle arasını kapat düğmesinin taşma payı açar.
    private let badge: CGFloat = 28

    var body: some View {
        ZStack {
            // Bulanıklık üstüne %75 siyah; dokunmak alttaki ana ekrana geçmez.
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.75).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            GeometryReader { geometry in
                let size = imageSize(in: geometry.size)
                VStack(spacing: 0) {
                    // Mac ve Windows'taki açılır reklamla aynı etiket (REKLAM).
                    // Perde: cam hap içinde mono REKLAM etiketi.
                    Text("AD")
                        .font(Font.dsAdTag)
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, Mobile.Space.gap)
                        .padding(.vertical, Mobile.Space.hair)
                        .dsGlass(in: Capsule(style: .circular))
                        .frame(height: badge)
                    Button {
                        if let url = PromoPolicy.webURL(ready.popup.link) { openURL(url) }
                        onDismiss()
                    } label: {
                        Image(uiImage: ready.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width, height: size.height)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ready.popup.alt.isEmpty ? Text("Open link") : Text(verbatim: ready.popup.alt))
                    // Kapat (X) köşeye çaprazlama oturur: dairenin merkezi görselin sağ üst köşe noktasında.
                    .overlay(alignment: .topTrailing) {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: closeDot, height: closeDot)
                                .dsGlass(in: Circle())
                                .frame(width: closeTouch, height: closeTouch)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Close"))
                        .offset(x: closeTouch / 2, y: -closeTouch / 2)
                    }
                    .padding(.top, closeTouch / 2)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(Mobile.Space.screen)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    /// Görsel kırpılmadan sığar: rozet ve köşeden taşan kapat düğmesi için yer ayrılınca oranı korunur.
    private func imageSize(in area: CGSize) -> CGSize {
        let ratio = max(0.2, min(5, ready.image.size.width / max(ready.image.size.height, 1)))
        let height = max(0, area.height - badge - closeTouch / 2)
        let width = max(0, min(area.width - closeTouch, height * ratio))
        return CGSize(width: width, height: width / ratio)
    }
}
