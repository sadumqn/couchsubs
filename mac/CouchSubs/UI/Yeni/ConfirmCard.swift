// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Yeni arayüzün onay kartı: mono etiket, başlık, açıklama; sağda amber ana eylem ve ikincil Vazgeç. Açılır pencere
/// (sheet) olarak gösterilir; Esc Vazgeç'tir.
struct DSConfirmCard: View {
    let eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirm: LocalizedStringKey
    var cancel: LocalizedStringKey = "Cancel"
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("m")) {
            if let eyebrow { DSMonoLabel(eyebrow).padding(.bottom, DS.space("xs")) }
            Text(title).font(.dsH2).fixedSize(horizontal: false, vertical: true)
            Text(message).dsMuted(.dsBody)
            HStack(spacing: DS.space("s")) {
                Spacer()
                Button(cancel) { decide(false) }
                    .buttonStyle(.dsSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(confirm) { decide(true) }
                    .buttonStyle(.dsPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, DS.space("xs"))
        }
        .padding(DS.space("l"))
        .frame(width: 480)
        .background(Color.dsSurface)
        .newLook()
    }
}

/// TV'de CouchSubs'ın kimliğini kullanan başka uygulama: kaldırıp CouchSubs kurulsun mu (#976).
struct ForeignTVAppPrompt: View {
    let decide: (Bool) -> Void

    var body: some View {
        DSConfirmCard(eyebrow: "TV", title: "Another App Is Installed",
                      message: "Another app on this TV is using the CouchSubs identity. Remove it and install CouchSubs?",
                      confirm: "Remove And Install", decide: decide)
    }
}
