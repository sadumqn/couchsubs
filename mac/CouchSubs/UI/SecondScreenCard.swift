// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI

/// "Başka bir cihazda göster": QR kod, adres ve Kopyala (Windows, iPhone ve Android'de aynı ad ve sıra). Ayarlar'da açık
/// durur; ana ekrandaki altyazı hedefi kartında düğmeyle açılır. İkinci ekran her zaman ek bir alıcıdır, hedef seçimini
/// (TV, bilgisayar ekranı, ikisi) değiştirmez.
struct SecondScreenPanel: View {
    @EnvironmentObject private var model: AppModel

    private var address: String? {
        AppModel.localAddress(near: nil).map { SecondScreen.address(host: $0, port: Int(model.serverPort), key: model.subtitleAccessKey) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            Text("Show on another device").font(.dsCardTitle)
            if let address {
                if let code = SecondScreen.qrImage(for: address) {
                    // Koyu temada da okunsun diye kod beyaz zeminde; büyütülürken yumuşatılmaz.
                    Image(decorative: code, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(Theme.space("s"))
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
                        .accessibilityLabel(Text("Show on another device"))
                }
                // Kopyala simgesi kutunun içinde; adres tek satır, sığmazsa ortadan kısalır.
                AddressRow(address: address)
                HintText(text: "Scan the code with the camera of a phone or tablet on the same Wi-Fi. While translating, the subtitles appear large in its browser; no app or internet needed.")
            } else {
                HintText(text: "Connect to Wi-Fi to show subtitles on another device.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ayarlar'daki karo.
struct SecondScreenCard: View {
    var body: some View {
        Card { SecondScreenPanel() }
    }
}
