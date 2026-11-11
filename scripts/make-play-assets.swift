// SPDX-License-Identifier: AGPL-3.0-only
// Android TV uygulamasının başlatıcı afişini ve Google Play görsellerini design/logo.svg'den üretir:
//   tv-android/app/src/main/res/drawable-nodpi/banner.png          320×180, TV ana ekranı (adı içerir: TV-BN)
//   tv-android/fastlane/metadata/android/<dil>/images/icon.png          512×512, Play simgesi (tam kare)
//   tv-android/fastlane/metadata/android/<dil>/images/featureGraphic.png 1024×500, öne çıkan görsel
//   tv-android/fastlane/metadata/android/<dil>/images/tvBanner.png       1280×720, Play'deki TV afişi
// Konsol adı ya da logosu kullanılmaz. Ekran görüntüleri: scripts/play-screenshots.sh.
// Kullanım: swift scripts/make-play-assets.swift   (depo kökünden)

import AppKit

// design/tokens.json koyu tema renkleri.
let background = NSColor(srgbRed: 0x14 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: 1)
let backgroundTop = NSColor(srgbRed: 0x2B / 255, green: 0x2D / 255, blue: 0x33 / 255, alpha: 1)
let textPrimary = NSColor(srgbRed: 0xF3 / 255, green: 0xEE / 255, blue: 0xE4 / 255, alpha: 1)
let textSecondary = NSColor(srgbRed: 0xA9 / 255, green: 0xA5 / 255, blue: 0x9C / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xF5 / 255, green: 0xB8 / 255, blue: 0x3D / 255, alpha: 1)

guard let logo = NSImage(contentsOfFile: "design/logo.svg") else { fatalError("design/logo.svg okunamadı") }

func render(width: Int, height: Int, to path: String, alpha: Bool = false, draw: (NSRect) -> Void) {
    // Play öne çıkan görseli ve TV afişini saydamlıksız (24 bit) ister; simge saydamlıklı olabilir.
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func fill(_ rect: NSRect) {
    background.setFill()
    rect.fill()
}

/// Logonun kendi zemini (yuvarlatılmış kare) dahil; `size` kenar uzunluğu (svg'nin 824/1024'lük karesi bu boya gelir).
func drawLogo(at origin: NSPoint, size: CGFloat) {
    let scale = size / 824
    logo.draw(in: NSRect(x: origin.x - 100 * scale, y: origin.y - 100 * scale, width: 1024 * scale, height: 1024 * scale))
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

/// Logo ve yanında ad (isteğe bağlı alt satır); ikisi birlikte `rect` içinde ortalanır.
func lockup(in rect: NSRect, logoSize: CGFloat, nameSize: CGFloat, tagline: String? = nil, taglineSize: CGFloat = 0) {
    let name = text("CouchSubs", size: nameSize, weight: .semibold, color: textPrimary)
    let tag = tagline.map { text($0, size: taglineSize, weight: .regular, color: textSecondary) }
    let gap = logoSize * 0.28
    let textWidth = max(name.size().width, tag?.size().width ?? 0)
    let total = logoSize + gap + textWidth
    let x = rect.midX - total / 2
    drawLogo(at: NSPoint(x: x, y: rect.midY - logoSize / 2), size: logoSize)
    let lineGap = taglineSize * 0.45
    let blockHeight = name.size().height + (tag.map { $0.size().height + lineGap } ?? 0)
    let top = rect.midY + blockHeight / 2
    name.draw(at: NSPoint(x: x + logoSize + gap, y: top - name.size().height))
    if let tag {
        tag.draw(at: NSPoint(x: x + logoSize + gap, y: top - name.size().height - lineGap - tag.size().height))
    }
}

/// Altta ince vurgu çizgisi: altyazı satırını andırır.
func accentBar(in rect: NSRect, width: CGFloat, height: CGFloat, bottom: CGFloat) {
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.midX - width / 2, y: bottom, width: width, height: height),
                 xRadius: height / 2, yRadius: height / 2).fill()
}

// TV ana ekranı afişi: 320×180, adı içerir.
render(width: 320, height: 180, to: "tv-android/app/src/main/res/drawable-nodpi/banner.png") { rect in
    fill(rect)
    lockup(in: rect, logoSize: 84, nameSize: 38)
}

let taglines = [
    "tr-TR": "Oyun altyazıları Türkçe, TV'nizde",
    "en-US": "Game subtitles in Turkish, on your TV",
]

for (language, tagline) in taglines {
    let images = "tv-android/fastlane/metadata/android/\(language)/images"

    // Play simgesi: tam kare, köşeleri Play yuvarlatır.
    render(width: 512, height: 512, to: "\(images)/icon.png", alpha: true) { rect in
        NSGradient(starting: backgroundTop, ending: background)!.draw(in: rect, angle: -90)
        drawLogo(at: NSPoint(x: 0, y: 0), size: 512)
    }

    render(width: 1024, height: 500, to: "\(images)/featureGraphic.png") { rect in
        NSGradient(starting: backgroundTop, ending: background)!.draw(in: rect, angle: -90)
        lockup(in: rect.offsetBy(dx: 0, dy: 20), logoSize: 200, nameSize: 92, tagline: tagline, taglineSize: 36)
        accentBar(in: rect, width: 360, height: 12, bottom: 64)
    }

    render(width: 1280, height: 720, to: "\(images)/tvBanner.png") { rect in
        NSGradient(starting: backgroundTop, ending: background)!.draw(in: rect, angle: -90)
        lockup(in: rect.offsetBy(dx: 0, dy: 24), logoSize: 260, nameSize: 112, tagline: tagline, taglineSize: 42)
        accentBar(in: rect, width: 440, height: 14, bottom: 96)
    }
}
print("Play görselleri üretildi.")
