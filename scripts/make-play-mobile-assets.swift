// SPDX-License-Identifier: AGPL-3.0-only
// Android telefon uygulamasının (com.couchsubs.mobile) Google Play görsellerini üretir:
//   store/play-mobile/icon.png                         512×512, Play simgesi (design/logo.svg)
//   store/play-mobile/<dil>/featureGraphic.png         1024×500, öne çıkan görsel (dile göre alt satır)
//   store/play-mobile/phoneScreenshots/N-ad.png        1080×1920 (9:16), docs/screenshots/telefon/*.png'den
// Kaynak telefon görüntüleri 780×1688'dir (≈9:19,5); Play uzun kenarın kısa kenarın iki katını geçmesine izin
// vermediği için görüntü 1920 yüksekliğe büyütülüp uygulamanın zemin rengiyle 1080 genişliğe ortalanır (kırpma yok).
// Konsol adı ya da logosu kullanılmaz. Kullanım: swift scripts/make-play-mobile-assets.swift   (depo kökünden)

import AppKit

// design/tokens.json koyu tema renkleri (scripts/make-play-assets.swift ile aynı).
let background = NSColor(srgbRed: 0x14 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: 1)
let backgroundTop = NSColor(srgbRed: 0x2B / 255, green: 0x2D / 255, blue: 0x33 / 255, alpha: 1)
let textPrimary = NSColor(srgbRed: 0xF3 / 255, green: 0xEE / 255, blue: 0xE4 / 255, alpha: 1)
let textSecondary = NSColor(srgbRed: 0xA9 / 255, green: 0xA5 / 255, blue: 0x9C / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xF5 / 255, green: 0xB8 / 255, blue: 0x3D / 255, alpha: 1)

guard let logo = NSImage(contentsOfFile: "design/logo.svg") else { fatalError("design/logo.svg okunamadı") }
let out = "store/play-mobile"

func render(width: Int, height: Int, to path: String, alpha: Bool = false, draw: (NSRect) -> Void) {
    // Öne çıkan görsel ve ekran görüntüleri saydamlıksız (24 bit) olmalı; simge saydamlıklı olabilir.
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

func drawLogo(at origin: NSPoint, size: CGFloat) {
    let scale = size / 824
    logo.draw(in: NSRect(x: origin.x - 100 * scale, y: origin.y - 100 * scale, width: 1024 * scale, height: 1024 * scale))
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

func lockup(in rect: NSRect, logoSize: CGFloat, nameSize: CGFloat, tagline: String, taglineSize: CGFloat) {
    let name = text("CouchSubs", size: nameSize, weight: .semibold, color: textPrimary)
    let tag = text(tagline, size: taglineSize, weight: .regular, color: textSecondary)
    let gap = logoSize * 0.28
    let total = logoSize + gap + max(name.size().width, tag.size().width)
    let x = rect.midX - total / 2
    drawLogo(at: NSPoint(x: x, y: rect.midY - logoSize / 2), size: logoSize)
    let lineGap = taglineSize * 0.45
    let top = rect.midY + (name.size().height + tag.size().height + lineGap) / 2
    name.draw(at: NSPoint(x: x + logoSize + gap, y: top - name.size().height))
    tag.draw(at: NSPoint(x: x + logoSize + gap, y: top - name.size().height - lineGap - tag.size().height))
}

render(width: 512, height: 512, to: "\(out)/icon.png", alpha: true) { rect in
    NSGradient(starting: backgroundTop, ending: background)!.draw(in: rect, angle: -90)
    drawLogo(at: NSPoint(x: 0, y: 0), size: 512)
}

let taglines = [
    "tr-TR": "Oyun altyazıları Türkçe, telefonda ve TV'de",
    "en-US": "Game subtitles in Turkish, on phone and TV",
]
for (language, tagline) in taglines {
    render(width: 1024, height: 500, to: "\(out)/\(language)/featureGraphic.png") { rect in
        NSGradient(starting: backgroundTop, ending: background)!.draw(in: rect, angle: -90)
        lockup(in: rect.offsetBy(dx: 0, dy: 20), logoSize: 190, nameSize: 88, tagline: tagline, taglineSize: 32)
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 180, y: 64, width: 360, height: 12), xRadius: 6, yRadius: 6).fill()
    }
}

// Sıra mağazadaki sıradır. 09-altyazi (yatay ekran, dikey tuvalde kesik) bilerek alınmadı.
let screenshots = [
    ("1-karsilama", "01-karsilama-1"),
    ("2-ana", "07-ana"),
    ("3-calisiyor", "08-calisiyor"),
    ("4-paketler", "10-paketler"),
    ("5-psn", "03-psn"),
    ("6-hedef", "05-hedef"),
]
for (name, source) in screenshots {
    guard let image = NSImage(contentsOfFile: "docs/screenshots/telefon/\(source).png"),
          let rep = image.representations.first else { fatalError("\(source).png okunamadı") }
    let width = CGFloat(rep.pixelsWide), height = CGFloat(rep.pixelsHigh)
    render(width: 1080, height: 1920, to: "\(out)/phoneScreenshots/\(name).png") { rect in
        background.setFill()
        rect.fill()
        let scaledWidth = (width * rect.height / height).rounded()
        image.draw(in: NSRect(x: ((rect.width - scaledWidth) / 2).rounded(), y: 0, width: scaledWidth, height: rect.height))
    }
}
print("Telefon Play görselleri üretildi: \(out)")
