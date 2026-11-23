// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Karşılama ve konsol seçimi (PlayStation 5 varsayılan, Xbox Beta); gerekenler seçilen konsola göre yazılır.
struct WelcomeStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StepLayout(title: "Welcome to CouchSubs",
                   message: model.isXbox
                       ? "Xbox support is in beta. CouchSubs reads the subtitles in the game picture and shows the translation on your TV or computer. You keep playing with your own controller."
                       : "CouchSubs reads the English subtitles of your PS5 games and shows a Turkish translation on your TV, on top of the game. You keep playing on the TV with your own controller.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                Card(title: "Your console") {
                    ConsolePicker()
                }
                if model.isXbox {
                    Card {
                        Label("You will need: your home Xbox on the same network, a Microsoft account, and a TV or computer to show the subtitles. Remote play must be turned on on the Xbox.",
                              systemImage: "gamecontroller")
                    }
                } else {
                    Card(title: "You will need:") {
                        Label("A PS5 on the same Wi-Fi network as this Mac", systemImage: "gamecontroller")
                        Label("An LG TV with the CouchSubs TV app", systemImage: "tv")
                        Label("A free second PlayStation Network account", systemImage: "person.2")
                    }
                }
                // Kullanım verisi ilk açılışta bir kez söylenir (telefonlardaki karşılama ekranıyla aynı anlam).
                if model.showsUsageNotice { HintText(text: "CouchSubs measures how the app is used without linking it to you; no subtitle text, picture or account data is sent. You can turn this off in Settings › Game packs › Usage data.") }
            }
        }
    }
}
