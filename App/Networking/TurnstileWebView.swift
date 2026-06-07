import SwiftUI
import WebKit

/// Renders the Cloudflare Turnstile widget inside a WKWebView and reports the
/// resulting `turnstile_response` token back to SwiftUI. The widget runs in
/// "invisible" mode — there is no UI to interact with; the JS callback
/// resolves automatically (usually <1s) for legitimate clients.
struct TurnstileChallengeView: UIViewRepresentable {
    let siteKey: String
    /// Pretend-origin shown to Cloudflare. Must match a hostname configured for
    /// the widget on the Cloudflare dashboard.
    let baseURL: URL
    let onToken: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "turnstileBridge")
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.loadHTMLString(html(siteKey: siteKey), baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func html(siteKey: String) -> String {
        """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <!-- Cloudflare Turnstile api.js does not support Subresource Integrity:
             it is a dynamic version router that returns different bytes per
             request. The official integration explicitly recommends loading
             it bare. The script only runs inside this isolated WKWebView. -->
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileReady" defer></script>
        <style>html,body{margin:0;background:transparent;}</style>
        </head><body>
        <div id="cf"></div>
        <script>
        function send(name, payload) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.turnstileBridge) {
            window.webkit.messageHandlers.turnstileBridge.postMessage({ name: name, payload: payload });
          }
        }
        function onTurnstileReady() {
          try {
            turnstile.render('#cf', {
              sitekey: '\(siteKey)',
              size: 'invisible',
              callback: function(token) { send('token', token); },
              'error-callback': function(err) { send('error', String(err)); },
              'expired-callback': function() { send('error', 'expired'); },
              'timeout-callback': function() { send('error', 'timeout'); }
            });
          } catch (e) { send('error', String(e)); }
        }
        </script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        let onError: (String) -> Void
        private var handled = false

        init(onToken: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onToken = onToken
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !handled, let dict = message.body as? [String: Any] else { return }
            let name = dict["name"] as? String ?? ""
            let payload = dict["payload"] as? String ?? ""
            if name == "token" {
                handled = true
                onToken(payload)
            } else if name == "error" {
                handled = true
                onError(payload)
            }
        }
    }
}

/// Modal sheet that hosts the Turnstile widget and resolves to a token or an
/// error. The host view shows a spinner while the widget initializes.
struct TurnstileChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (Result<String, Error>) -> Void

    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("セキュリティ確認中…")
                .font(.callout)
                .foregroundStyle(.secondary)
            TurnstileChallengeView(
                siteKey: AppConfig.turnstileSiteKey,
                baseURL: URL(string: "https://\(AppConfig.turnstileHostname)")!,
                onToken: { token in
                    onResult(.success(token))
                    dismiss()
                },
                onError: { reason in
                    failed = true
                    onResult(.failure(APIError.turnstileVerificationFailed))
                    dismiss()
                }
            )
            .frame(width: 0, height: 0) // Invisible widget — no visible chrome.
            if failed {
                Text("検証に失敗しました")
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .presentationDetents([.height(180)])
        .presentationDragIndicator(.visible)
    }
}
