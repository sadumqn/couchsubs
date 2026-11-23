// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI

/// Pencere kabuğunun cam çubukları (iOS sekme çubuğu gibi): üstte başlık çubuğu + sekmeler, altta reklam bandı ya da
/// kurulumun Geri/Devam çubuğu. Sayfa içeriği pencerenin tamamını kaplar ve bu çubukların ARKASINDAN kayar; çubuklar
/// sistemin malzemesiyle bulanık ve temanın zemin renginde yarı opak, yazıları okunur kalır. Sayfalar kayan içeriğin
/// başına ve sonuna `dsChromeInsets` kadar boşluk koyar: ilk açılışta içerik çubukların altından başlar, en alttaki
/// içerik kaydırınca tam görünür.
struct DSChromeInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var dsChromeInsets: EdgeInsets {
        get { self[DSChromeInsetsKey.self] }
        set { self[DSChromeInsetsKey.self] = newValue }
    }
}

/// Cam çubuk zemini: malzeme (arkadaki içerik bulanık) + temanın zemin rengi (koyu ve açık temada aynı yoğunluk) + içeriğe
/// bakan kenarda kıl çizgi. Arkadaki yazılar gürültü yapmaz; çubuktaki yazı ve düğmelerin kontrastı zemindekiyle aynı.
struct DSGlassBar: View {
    let edge: VerticalEdge

    static let tint = 0.93

    var body: some View {
        ZStack {
            Rectangle().fill(.thickMaterial)
            Rectangle().fill(Color.dsBackground.opacity(Self.tint))
        }
        .overlay(alignment: edge == .top ? .bottom : .top) {
            Rectangle().fill(Color.dsBorder).frame(height: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pencereyi tam boy içerikle açar: başlık çubuğu saydam ve yazısız, içerik pencerenin tepesine kadar uzanır (trafik
/// ışıkları üst cam çubuğun üstünde kalır). Pencere başlığın arkasından sürüklenebilir kalır.
struct DSFullSizeWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
}

/// Başlık çubuğunun yüksekliği (trafik ışıkları); tam boy pencerede üst cam çubuğun bu kadarı başlık çubuğudur.
enum DSChrome {
    static let titlebar: CGFloat = 28
}
