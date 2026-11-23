// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI
import WebKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Sony'nin giriş sayfası; giriş bitince yönlendirme adresini yakalar. Mac ve iPhone/iPad uygulamaları ortak kullanır.
struct LoginWebView: PlatformViewRepresentable {
    let onRedirect: (URL) -> Void
    let onProblem: (String?) -> Void
    /// Arttıkça sayfa baştan yüklenir ("Yeniden dene"); Mac kullanmaz.
    var reloadToken = 0
    /// Sony'nin sayfası "Can't connect to the server" dedi: giriş sistem tarayıcısında sürdürülmeli (Windows'taki gibi).
    var onUnreachable: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onRedirect: onRedirect, onProblem: onProblem, onUnreachable: onUnreachable) }

    /// Sony'nin sayfasındaki görünür metni (değiştikçe, en çok yarım saniyede bir) uygulamaya gönderir. Sony arka plan
    /// çağrısı başarısız olunca sayfa yenilenmeden "Can't connect to the server" yazar; gezinme olayı gelmez.
    private static let pageTextWatcher = """
        (() => {
          if (window.top !== window || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.couchsubsPageText) return;
          let last = '', timer = 0;
          const send = () => {
            timer = 0;
            const text = document.body ? (document.body.innerText || '').slice(0, 4000) : '';
            if (text === last) return;
            last = text;
            window.webkit.messageHandlers.couchsubsPageText.postMessage(text);
          };
          const schedule = () => { if (!timer) timer = setTimeout(send, 500); };
          const start = () => {
            schedule();
            new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true, characterData: true });
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
        })();
        """

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context) }
    func updateNSView(_ view: WKWebView, context: Context) { reloadIfAsked(view, context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context) }
    func updateUIView(_ view: WKWebView, context: Context) { reloadIfAsked(view, context) }
    #endif

    private func reloadIfAsked(_ view: WKWebView, _ context: Context) {
        guard context.coordinator.reloadToken != reloadToken else { return }
        context.coordinator.reloadToken = reloadToken
        view.load(URLRequest(url: PSNAccount.authorizeURL))
    }

    private func makeWebView(_ context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.pageTextWatcher, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Zayıf sarmalayıcı: içerik denetleyicisi işleyiciyi güçlü tutar, eşgüdümcü sızmasın.
        configuration.userContentController.add(WeakScriptHandler(context.coordinator), name: "couchsubsPageText")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        context.coordinator.reloadToken = reloadToken
        view.load(URLRequest(url: PSNAccount.authorizeURL))
        return view
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onRedirect: (URL) -> Void
        let onProblem: (String?) -> Void
        let onUnreachable: () -> Void
        private var redirected = false
        private var unreachable = false
        var reloadToken = 0

        init(onRedirect: @escaping (URL) -> Void, onProblem: @escaping (String?) -> Void, onUnreachable: @escaping () -> Void = {}) {
            self.onRedirect = onRedirect
            self.onProblem = onProblem
            self.onUnreachable = onUnreachable
        }

        /// Sony'nin sayfası "Can't connect to the server" yazdı (Windows'taki davranış; bir Mac kullanıcısında da uygulama
        /// içi giriş bu hatayla kaldı): giriş tarayıcıya taşınır.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !redirected, !unreachable, message.frameInfo.isMainFrame,
                  PSNAccount.isSonyHost(message.frameInfo.securityOrigin.host),
                  PSNAccount.looksServerUnreachable(message.body as? String) else { return }
            unreachable = true
            RemotePlayLog.write("PSN giriş sayfası sunucuya bağlanamadı (\(message.frameInfo.securityOrigin.host)); giriş tarayıcıya taşınıyor")
            onUnreachable()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Kodlu ya da Sony'nin hatasını taşıyan her yönlendirme yakalanır; eskiden hatalı yönlendirme boş sayfada kalıyordu.
            if let url = action.request.url, !redirected,
               PSNAccount.code(fromRedirect: url) != nil || PSNAccount.error(fromRedirect: url) != nil {
                redirected = true
                onRedirect(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
                if http.statusCode >= 400 {
                    RemotePlayLog.write("PSN giriş sayfası: HTTP \(http.statusCode)")
                    onProblem("HTTP \(http.statusCode)")
                } else {
                    onProblem(nil)
                }
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        /// iPhone'da sayfanın içerik süreci arka planda (bellek baskısıyla) kapanınca sayfa beyaz kalıyordu (TestFlight):
        /// sayfa yeniden yüklenir.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard !redirected else { return }
            RemotePlayLog.write("PSN giriş sayfası: içerik süreci kapandı, yeniden yükleniyor")
            if webView.url == nil {
                webView.load(URLRequest(url: PSNAccount.authorizeURL))
            } else {
                webView.reload()
            }
        }

        private func report(_ error: Error) {
            // Yönlendirmeyi kendimiz iptal ediyoruz; o bir sorun değildir.
            let nsError = error as NSError
            let canceled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            // WebKitErrorFrameLoadInterruptedByPolicyChange: yönlendirmeyi iptal etmemiz.
            let interrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
            if redirected || canceled || interrupted { return }
            RemotePlayLog.write("PSN giriş sayfası açılamadı: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
            onProblem(nsError.localizedDescription)
        }
    }
}

/// WKUserContentController işleyicisini güçlü tutar; eşgüdümcüyle döngü oluşmasın diye araya zayıf başvuru girer.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
