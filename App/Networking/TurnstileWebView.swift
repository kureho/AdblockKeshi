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
/// error. Auto-fails after 30 seconds if the WKWebView hangs (network drop,
/// JS execution stalls) so the host view never spins forever.
struct TurnstileChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (Result<String, Error>) -> Void

    @State private var resolved = false
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
                    guard !resolved else { return }
                    resolved = true
                    onResult(.success(token))
                    dismiss()
                },
                onError: { _ in
                    guard !resolved else { return }
                    resolved = true
                    failed = true
                    // 親 (ReportFormView) の `state` を先に `.error` へ倒してから `dismiss()`
                    // を呼ぶ。逆順（先に dismiss）にすると、このシートの表示を握っている
                    // 外側の `Binding<Bool>`（`turnstileBinding`）の `set` が
                    // `viewModel.cancelTurnstile()` を呼び、`state` がまだ `.awaitingTurnstile`
                    // のうちにそれを `.idle` へ巻き戻してしまう。その後で本来の失敗通知
                    // (`onResult` → `failTurnstile`) が届いても `state` は既に `.awaitingTurnstile`
                    // ではないため `failTurnstile` の guard に弾かれて何も起きず、失敗アラートが
                    // 出ないまま無言でフォームへ戻ってしまう（UI テストで発見・再現済み）。
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
        .task {
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            // A-88 修正④: シートを閉じる（スワイプ等でキャンセル）と SwiftUI がこの `.task` を
            // キャンセルするが、`Task.sleep` は `try?` で握りつぶされるため、キャンセル後も
            // 以降の行がそのまま実行されてしまう。何もしていないのに「時間切れ」として
            // `onResult(.failure(...))` を呼び、キャンセルを装って `dismiss()` してしまう
            // （＝ユーザーが普通に閉じただけなのに確認失敗のエラーになる）。
            guard !Task.isCancelled, !resolved else { return }
            resolved = true
            // 上の onError と同じ理由で、必ず onResult() を先に呼んで `state` を確定させてから
            // dismiss() する。
            onResult(.failure(APIError.turnstileVerificationFailed))
            dismiss()
        }
    }
}
