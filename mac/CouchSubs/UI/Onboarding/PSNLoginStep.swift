// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI
import WebKit

struct PSNLoginStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLogin = false
    @State private var working = false
    @State private var error: String?
    /// Pencere yönlendirmeyi yakaladı mı; yakalamadan kapanırsa kullanıcıya söylenir (eskiden sessizdi).
    @State private var redirected = false
    /// Giriş sayfasının son sorunu (açılamadı, Sony'nin HTTP hatası).
    @State private var pageProblem: String?
    /// Uygulama içi giriş Sony'nin "Can't connect to the server" hatasında kalırsa giriş tarayıcıda yapılır, yönlendirme
    /// adresi buraya yapıştırılır (panoya kopyalanınca kendiliğinden alınır). Windows'taki PsnLoginStep ile aynı akış.
    @State private var showBrowser = false
    /// Tarayıcıya uygulama içi sayfa sunucusuna bağlanamadığı için geçildi (nedeni de yazılır).
    @State private var browserAutomatic = false
    @State private var browserURL = ""
    @State private var browserError: String?
    /// Son denenen yönlendirme adresi: tek kullanımlık kod panodan ikinci kez denenmez.
    @State private var lastBrowserRedirect: String?
    @State private var showManual = false
    @State private var manualId = ""
    @State private var manualError: String?

    var body: some View {
        StepLayout(title: "Sign in with the second account",
                   message: "Sign in to PlayStation Network with the second account you just created. Your password goes directly to Sony; CouchSubs only keeps the account ID.") {
            // Kompakt hesap kartı (iPhone ve Windows aynı): rozet, başlık + durum, sağda tek düğme; diğer iki yol kartın
            // altındaki "Diğer Giriş Yolları" açılırında. Birimler arası 24.
            VStack(alignment: .leading, spacing: DS.unitGap) {
                DSAccountCard(badge: "PS", title: "PlayStation Account", signedIn: model.accountId != nil, busy: working,
                              expanded: showBrowser || showManual, signIn: openLogin) {
                    browserEntry
                    manualEntry
                }
                .frame(maxWidth: 640, alignment: .leading)
                if error != nil { ErrorText(error: error).textSelection(.enabled) }
            }
        }
        // Kullanıcı tarayıcıdan dönünce panoda yönlendirme adresi varsa kendiliğinden alınır.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            takeRedirectFromPasteboard()
        }
        .sheet(isPresented: $showLogin, onDismiss: sheetClosed) {
            PSNLoginSheet(onRedirect: received, onProblem: { pageProblem = $0 }, onUnreachable: {
                // Sony'nin sayfası uygulama içinde sunucusuna bağlanamadı; aynı giriş tarayıcıda çalışıyor.
                redirected = true
                showLogin = false
                error = nil
                openBrowserLogin(automatic: true)
            })
        }
    }

    private func openLogin() {
        redirected = false
        pageProblem = nil
        showLogin = true
    }

    @ViewBuilder private var browserEntry: some View {
        if showBrowser {
            VStack(alignment: .leading, spacing: DS.space("s")) {
                if browserAutomatic {
                    HintText(text: "Sony's sign-in page could not reach its server inside the app, so sign-in moved to your browser.")
                }
                HintText(text: "Sign in with your second account in the browser that opened. When you finish, the browser stays on a remoteplay.dl.playstation.net page that only says redirect. Click the address bar, copy the whole address and come back here. CouchSubs picks up the copied address by itself; if it does not, paste it below and press Save.")
                HStack(spacing: DS.space("s")) {
                    TextField("", text: $browserURL)
                        .textFieldStyle(CSTextFieldStyle())
                        .onSubmit(submitBrowser)
                    Button("Save", action: submitBrowser).buttonStyle(.dsPrimary).disabled(working)
                }
                Button("Open the Browser Again") { model.openInBrowser(PSNAccount.authorizeURL) }.buttonStyle(.dsSecondary)
                ErrorText(error: browserError)
            }
        } else {
            Button("Sign In in the Browser") { openBrowserLogin(automatic: false) }.buttonStyle(.dsSecondary)
        }
    }

    /// Sony'nin giriş sayfası varsayılan tarayıcıda açılır, adres yapıştırma alanı görünür.
    private func openBrowserLogin(automatic: Bool) {
        showBrowser = true
        browserAutomatic = automatic
        browserError = nil
        // Tarayıcı açılmadan önce panoda duran (eski girişten kalmış) adres kendiliğinden denenmesin.
        lastBrowserRedirect = PSNAccount.redirect(fromPastedText: NSPasteboard.general.string(forType: .string))?.absoluteString ?? lastBrowserRedirect
        model.openInBrowser(PSNAccount.authorizeURL)
    }

    private func takeRedirectFromPasteboard() {
        guard showBrowser, !working,
              let redirect = PSNAccount.redirect(fromPastedText: NSPasteboard.general.string(forType: .string)),
              redirect.absoluteString != lastBrowserRedirect else { return }
        browserURL = redirect.absoluteString
        submitBrowser()
    }

    private func submitBrowser() {
        guard !working else { return }
        guard let redirect = PSNAccount.redirect(fromPastedText: browserURL) else {
            browserError = String(localized: "This address has no sign-in code. It should start with https://remoteplay.dl.playstation.net/remoteplay/redirect?code=")
            return
        }
        browserError = nil
        lastBrowserRedirect = redirect.absoluteString
        working = true
        error = nil
        Task {
            do {
                try await model.completePSNLogin(redirect: redirect)
                browserURL = ""
                showBrowser = false
                // Kullanılmış kod panoda kalmasın.
                if PSNAccount.redirect(fromPastedText: NSPasteboard.general.string(forType: .string)) != nil {
                    NSPasteboard.general.clearContents()
                }
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }

    /// Sony girişi açılmıyorsa (ör. servis sağlayıcı engelliyor) hesap kimliği elle yazılır.
    @ViewBuilder private var manualEntry: some View {
        if showManual {
            VStack(alignment: .leading, spacing: DS.space("s")) {
                HintText(text: "If Sony's sign-in page does not open (some internet providers block it), enter the second account's PSN account ID in base64 (12 characters, e.g. AbCdEfGhIjk=).")
                HStack(spacing: DS.space("s")) {
                    TextField("", text: $manualId)
                        .textFieldStyle(CSTextFieldStyle())
                        .frame(maxWidth: 320)
                        .onSubmit(saveManual)
                    Button("Save", action: saveManual).buttonStyle(.dsPrimary)
                }
                ErrorText(error: manualError)
            }
        } else {
            Button("Enter Account ID Manually") { showManual = true }.buttonStyle(.dsSecondary)
        }
    }

    private func saveManual() {
        if model.useManualAccountId(manualId) {
            manualError = nil
            error = nil
        } else {
            manualError = String(localized: "This is not a valid account ID. It is 12 characters in base64, e.g. AbCdEfGhIjk=.")
        }
    }

    /// Pencere yönlendirmesiz kapandıysa nedeni söylenir (eskiden sessizce dönülüyordu).
    private func sheetClosed() {
        guard !redirected else { return }
        let failure: Error = model.loginWindowError(problem: pageProblem)
        error = failure.localizedDescription
    }

    private func received(_ url: URL) {
        redirected = true
        showLogin = false
        working = true
        error = nil
        Task {
            do { try await model.completePSNLogin(redirect: url) } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

/// Sony'nin giriş sayfasını açar; giriş bitince yönlendirme adresini yakalar.
struct PSNLoginSheet: View {
    let onRedirect: (URL) -> Void
    /// Sayfa açılamadı ya da Sony hata kodu döndürdü (nil: sorun giderildi).
    let onProblem: (String?) -> Void
    /// Sony'nin sayfası sunucusuna bağlanamadı: giriş tarayıcıda sürer.
    var onUnreachable: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "PlayStation Network").font(.csHeadline)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.secondary)
            }
            .padding(Theme.space("m"))
            Divider()
            LoginWebView(onRedirect: onRedirect, onProblem: onProblem, onUnreachable: onUnreachable)
        }
        .frame(width: 520, height: 680)
    }
}
