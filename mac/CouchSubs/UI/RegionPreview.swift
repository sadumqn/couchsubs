// SPDX-License-Identifier: AGPL-3.0-only
// Mac ve iPhone uygulamalarının ortak parçası (iPhone projesi de bu dosyayı derler).

import CouchSubsCore
import SwiftUI

/// Alanın canlı önizlemesi: son PS5 karesi (yoksa yer tutucu), üstünde alanın çerçevesi; alanın dışı karartılır, okunacak
/// yer belirgin olur. Çerçeve içinden sürüklenerek taşınır, sekiz tutamacından (köşeler ve kenar ortaları) sürüklenerek
/// boyutlandırılır. `centered` (altyazı alanında "Ortada tut" açıkken): yatay boyut ortadan değişir, alan ortalı kalır.
/// Kurallar `RegionEdit`'tedir (Windows ve Android ile aynı). Sürükleme boyunca yalnız önizlemedeki taslak (`RegionDrag`)
/// değişir; `onChange` bırakınca bir kez çağrılır. Her harekette ayar yazılınca bütün Ayarlar sayfası yeniden çiziliyor,
/// pencere titriyordu (GitHub #802). Kaydırma önizlemenin kendi koordinatlarındadır, çerçeve kaydıkça değişmez.
struct RegionPreview: View {
    let region: CropRegion
    let frame: CGImage?
    /// Yatay boyut ortadan değişir (altyazı alanında `UserSettings.keepAreaCentered`); ek alanlarda kapalı.
    var centered = false
    /// Kare yokken gösterilen yazı.
    var placeholder: LocalizedStringKey = "The game picture appears here once translating starts."
    let onChange: (CropRegion) -> Void

    /// Süren sürüklemenin taslağı (hep sürüklemenin başladığı bölgeye göre hesaplanır); sürükleme yokken nil.
    @State private var drag: RegionDrag? = nil
    /// Önizlemenin koordinat alanı: sürüklenen çerçeve ya da tutamaç yer değiştirse de kaydırma buna göre ölçülür.
    private static let space = "RegionPreview"

    /// Görünen tutamaç ve parmakla tutma alanı (dokunmatikte küçük kare tutulmaz).
    private static let handle: CGFloat = 10
    private static let grip: CGFloat = 28

    @Environment(\.csNewLook) private var newLook

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shown = drag?.region ?? region
            let box = CGRect(x: size.width * shown.left, y: size.height * shown.top,
                             width: size.width * (shown.right - shown.left), height: size.height * (shown.bottom - shown.top))
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(decorative: frame, scale: 1).resizable()
                } else {
                    RoundedRectangle(cornerRadius: Theme.radius("inner")).fill(Self.emptyFill(newLook))
                    Text(placeholder)
                        .font(.csCaption).foregroundStyle(Self.mutedText(newLook))
                        .multilineTextAlignment(.center)
                        .padding(Theme.space("m"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(box)
                }
                .fill(Color.black.opacity(frame == nil && newLook ? 0.12 : 0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: newLook ? 4 : 0).strokeBorder(Color.csAccent, lineWidth: newLook ? 1.5 : 2))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .gesture(dragging(.move, in: size))
                    .accessibilityLabel(Text("Subtitle area"))
                ForEach(Array(RegionEdit.handles(shown).enumerated()), id: \.offset) { _, spot in
                    // Yeni arayüzde küçük yuvarlak tutamaç: beyaz, amber halkalı, hafif gölgeli.
                    Group {
                        if newLook {
                            Circle().fill(Color.white)
                                .overlay(Circle().strokeBorder(Color.csAccent, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                                .frame(width: 9, height: 9)
                        } else {
                            Rectangle().fill(Color.csAccent).frame(width: Self.handle, height: Self.handle)
                        }
                    }
                        .frame(width: Self.grip, height: Self.grip)
                        .contentShape(Rectangle())
                        .offset(x: size.width * spot.x - Self.grip / 2, y: size.height * spot.y - Self.grip / 2)
                        .gesture(dragging(spot.handle, in: size))
                        .accessibilityHidden(true)
                }
            }
            .coordinateSpace(name: Self.space)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: newLook ? 12 : Theme.radius("inner"), style: .continuous))
        .overlay {
            if newLook { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Self.borderColor).allowsHitTesting(false) }
        }
    }

    /// Kare yokken zemin: yeni arayüzde alan rengi (krem/koyu), eski görünümde arka plan.
    private static func emptyFill(_ newLook: Bool) -> Color {
        #if os(macOS)
        newLook ? .dsField : .csBackground
        #else
        .csBackground
        #endif
    }

    private static func mutedText(_ newLook: Bool) -> Color {
        #if os(macOS)
        newLook ? .dsMuted : .csSecondary
        #else
        .csSecondary
        #endif
    }

    private static var borderColor: Color {
        #if os(macOS)
        .dsBorder
        #else
        .csBorder
        #endif
    }

    private func dragging(_ handle: RegionEdit.Handle, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                var next = drag ?? RegionDrag(start: region, handle: handle)
                next.move(dx: value.translation.width / max(1, size.width), dy: value.translation.height / max(1, size.height),
                          centered: centered)
                drag = next
            }
            .onEnded { _ in
                let result = drag?.result
                drag = nil
                if let result { onChange(result) }
            }
    }
}

extension AreaPreset {
    /// Seçimin ekrandaki adı.
    var title: LocalizedStringKey {
        switch self {
        case .bottom: "Bottom area"
        case .top: "Top area"
        case .full: "Full screen"
        case .custom: "Custom"
        }
    }
}

/// Yüzde değeri ("40%"; Türkçede "%40").
func percentText(_ value: Double) -> String {
    String(format: String(localized: "%lld%%"), Int(value.rounded()))
}
