// SPDX-License-Identifier: AGPL-3.0-only
// Kurulum ekranları. Geçici, sade yerleşim: onaylanan tasarım gelince yeniden çizilecek; akış ve metinler kalır.

import CouchSubsCore
import RemotePlay
import SwiftUI

struct OnboardingScreen: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch model.step {
                    case .welcome: WelcomeStep()
                    case .psnLogin: PSNLoginStep()
                    case .console: ConsoleStep()
                    case .output: OutputStep()
                    case .done: EmptyView()
                    }
                }
                .padding(Theme.space("xl"))
            }
            HStack(spacing: Theme.space("m")) {
                if model.step != .welcome {
                    Button("Back") { model.back() }.buttonStyle(.secondary)
                }
                Spacer()
                Button("Continue") { model.advance() }
                    .buttonStyle(.primary)
                    .disabled(!model.canAdvance)
            }
            .padding(Theme.space("l"))
            .background(Color.csSurface)
        }
        .background(Color.csBackground)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        StepLayout(symbol: "captions.bubble", title: "Welcome to CouchSubs",
                   message: "Your phone reads the English subtitles of your PS5 game, translates them into Turkish and shows them on the TV or on this screen.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                Text("You will need:").font(.csHeadline)
                NumberedRow(number: 1, text: "A second PSN account")
                NumberedRow(number: 2, text: "Your PS5 and this phone on the same Wi-Fi")
                NumberedRow(number: 3, text: "Optional: a TV with the CouchSubs TV app")
            }
        }
    }
}

private struct PSNLoginStep: View {
    @Environment(PhoneModel.self) private var model
    @State private var showLogin = false
    @State private var redirected = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        StepLayout(symbol: "person.crop.circle.badge.checkmark", title: "Sign in with the second account",
                   message: "Sign in to PlayStation Network with the second account you just created. Your password goes directly to Sony; CouchSubs only keeps the account ID.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                if model.accountId != nil { DoneLabel(text: String(localized: "Signed in")) }
                Button(model.accountId == nil ? "Sign in" : "Sign in again") {
                    redirected = false
                    showLogin = true
                }
                .buttonStyle(CSButtonStyle(kind: model.accountId == nil ? .primary : .secondary))
                .disabled(working)
                if working { ProgressView() }
                ErrorText(error: error)
            }
        }
        .sheet(isPresented: $showLogin, onDismiss: {
            if !redirected { error = PhoneError.loginWindowClosed.localizedDescription }
        }) {
            NavigationStack {
                LoginWebView(onRedirect: received, onProblem: { _ in })
                    .navigationTitle(Text(verbatim: "PlayStation Network"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showLogin = false } } }
            }
        }
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

private struct ConsoleStep: View {
    @Environment(PhoneModel.self) private var model
    @State private var consoles: [ConsoleInfo] = []
    @State private var selected: String?
    @State private var manualHost = ""
    @State private var pin = ""
    @State private var searching = false
    @State private var working = false
    @State private var error: String?

    private var host: String {
        let typed = manualHost.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? selected ?? "" : typed
    }

    var body: some View {
        StepLayout(symbol: "gamecontroller.fill", title: "Connect your PS5",
                   message: "Turn on the PS5. As the second user, open Settings › System › Remote Play › Pair Device and enter the 8-digit code shown there.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                if let console = model.console { DoneLabel(text: console.name.isEmpty ? "PS5" : console.name) }
                Card {
                    HStack {
                        Text(verbatim: "PS5").font(.csHeadline)
                        if searching { ProgressView() }
                        Spacer()
                        Button("Search again") { Task { await search() } }.buttonStyle(.secondary).disabled(searching)
                    }
                    ForEach(consoles, id: \.host) { console in
                        Button {
                            selected = console.host
                            manualHost = ""
                        } label: {
                            Label {
                                Text(verbatim: "\(console.name) — \(console.host)")
                            } icon: {
                                Image(systemName: selected == console.host ? "largecircle.fill.circle" : "circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if consoles.isEmpty && !searching {
                        HintText(text: "No PS5 found. Make sure it is on and on the same Wi-Fi, or enter its IP address (PS5: Settings › Network › Connection Status).")
                    }
                    TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                        .textFieldStyle(CSTextFieldStyle())
                        .keyboardType(.decimalPad)
                }
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    Text("8-digit code").font(.csCallout).foregroundStyle(Color.csSecondary)
                    TextField("", text: $pin)
                        .textFieldStyle(CSTextFieldStyle(font: .csCode, height: 52))
                        .keyboardType(.numberPad)
                }
                Button("Connect") { Task { await register() } }
                    .buttonStyle(.primary)
                    .disabled(working)
                if working { HintText(text: "Connecting to the PS5… This can take up to 30 seconds.") }
                ErrorText(error: error)
            }
        }
        .task { await search() }
    }

    private func search() async {
        searching = true
        consoles = await model.discoverConsoles()
        if selected == nil { selected = consoles.first?.host }
        searching = false
    }

    private func register() async {
        guard !working else { return }
        working = true
        error = nil
        do { try await model.register(host: host, pin: pin) } catch { self.error = error.localizedDescription }
        working = false
    }
}

/// Altyazının yeri: ağda bulunan bir TV (CouchSubs TV uygulaması kurulu) ya da bu telefonun ekranı.
private struct OutputStep: View {
    @Environment(PhoneModel.self) private var model
    @State private var tvs: [LGTV] = []
    @State private var searching = false
    @State private var working: LGTV?
    @State private var manualHost = ""
    @State private var manualBrand = TVBrand.lg
    @State private var error: String?

    var body: some View {
        StepLayout(symbol: "tv", title: "Where should the subtitles appear?",
                   message: "Choose a TV that already has the CouchSubs TV app, or show the subtitles on this phone.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                if let tv = model.tv, model.hasTV { DoneLabel(text: tv.name) }
                if model.tvAppMissing { TVAppMissingNote() }
                Card {
                    HStack {
                        Text("TV").font(.csHeadline)
                        if searching { ProgressView() }
                        Spacer()
                        Button("Search again") { Task { await search() } }.buttonStyle(.secondary).disabled(searching)
                    }
                    ForEach(tvs, id: \.self) { tv in
                        Button { Task { await pair(tv) } } label: {
                            HStack {
                                Text(verbatim: "\(tv.name) — \(tv.host)")
                                Spacer()
                                if working == tv { ProgressView() }
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(working != nil)
                    }
                    if tvs.isEmpty && !searching {
                        HintText(text: "No TV found. Enter the TV's IP address, or choose Android TV: its CouchSubs app finds this phone by itself.")
                    }
                    Picker("TV", selection: $manualBrand) {
                        Text(verbatim: "LG").tag(TVBrand.lg)
                        Text(verbatim: "Samsung").tag(TVBrand.samsung)
                        Text(verbatim: "Android TV").tag(TVBrand.androidTV)
                    }
                    .pickerStyle(.segmented)
                    if manualBrand != .androidTV {
                        TextField("IP address, e.g. 192.168.1.20", text: $manualHost)
                            .textFieldStyle(CSTextFieldStyle())
                            .keyboardType(.decimalPad)
                    }
                    Button("Connect") {
                        let host = manualHost.trimmingCharacters(in: .whitespaces)
                        Task { await pair(LGTV(name: manualBrand == .androidTV ? "Android TV" : host, host: host, brand: manualBrand)) }
                    }
                    .buttonStyle(.primary)
                    .disabled(working != nil || (manualBrand != .androidTV && manualHost.isEmpty))
                }
                ErrorText(error: error)
                Button("I don't have a TV: show subtitles on this phone") { model.usePhoneScreen() }
                    .buttonStyle(.secondary)
            }
        }
        .task { await search() }
    }

    private func search() async {
        searching = true
        tvs = await model.discoverTVs()
        searching = false
    }

    private func pair(_ tv: LGTV) async {
        working = tv
        error = nil
        do { try await model.pair(tv) } catch { self.error = String(localized: "Could not connect to the TV. Accept the request on the TV screen and try again.") }
        working = nil
    }
}

/// Telefon TV uygulamasını kuramaz; ilk kurulum bilgisayarla bir kez yapılır.
struct TVAppMissingNote: View {
    var body: some View {
        Card {
            Label("The CouchSubs TV app did not open on the TV.", systemImage: "exclamationmark.triangle")
                .font(.csBody.weight(.semibold))
                .foregroundStyle(Color.csWarning)
            HintText(text: "To install the TV app for the first time, use CouchSubs on a computer once. After that this phone is enough.")
        }
    }
}
