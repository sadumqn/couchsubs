// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI
import UIKit

/// "Başka bir cihazda göster": QR kod, adres ve Kopyala (Mac, Windows ve Android'de aynı ad ve sıra). Ayarlar'da ve
/// altyazı hedefi seçiminde gösterilir; ikinci ekran her zaman ek bir alıcıdır, hedef seçimini değiştirmez.
struct SecondScreenTile: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        Tile {
            SectionTitle("Show on another device")
            if let address = model.secondScreenAddress {
                if let code = SecondScreen.qrImage(for: address) {
                    // Koyu temada da okunsun diye kod beyaz zeminde; büyütülürken yumuşatılmaz.
                    Image(decorative: code, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .padding(Mobile.Space.inline)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Mobile.Radius.control))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Show on another device"))
                }
                DSCopyField(text: address)
                Text("Scan the code with the camera of a phone or tablet on the same Wi-Fi. While translating, the subtitles appear large in its browser; no app or internet needed.")
                    .dsMuted()
            } else {
                Text("Connect to Wi-Fi to show subtitles on another device.").dsMuted()
            }
        }
    }
}
