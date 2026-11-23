// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreImage
import Foundation

/// "Başka bir cihazda göster": aynı ağdaki telefon ya da tabletin tarayıcısında canlı altyazı. Sayfa (`/view`) ve akışı
/// (`/events?viewer=second`) erişim anahtarı ister; anahtar adresin içindedir ve QR kodla verilir. Sayfa TV sayılmaz,
/// altyazı hedefi ne olursa olsun (TV, bu cihaz, ikisi) olayları alır. Windows: SecondScreen.cs, Android: SecondScreen.kt.
public enum SecondScreen {
    public static let path = "/view"
    public static let viewer = "second"

    /// Tarayıcıda açılan adres: `http://<ağ adresi>:<port>/view?k=<anahtar>`.
    public static func address(host: String, port: Int, key: String) -> String {
        let shownHost = host.contains(":") ? "[\(host)]" : host
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? key
        return "http://\(shownHost):\(port)\(path)?k=\(escaped)"
    }

    /// Sayfanın kendisi (Windows ve Android aynı dosyayı verir).
    public static let page: Data = {
        guard let url = Bundle.module.url(forResource: "second-screen", withExtension: "html"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }()

    /// Adresin QR kodu, keskin kenarlı (her modül `scale` piksel) ve çevresinde boşlukla. Mac ve iPhone aynı kodu çizer.
    public static func qrImage(for text: String, scale: CGFloat = 8) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}
