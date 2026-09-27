import Foundation

/// Compile-time configuration for the v3.0 report pipeline. The Site Key is a
/// public credential (intended to ship in the iOS bundle); the corresponding
/// Secret Key lives only as a Cloudflare Worker secret.
enum AppConfig {
    /// Cloudflare Workers production endpoint.
    static let workersBaseURL = URL(string: "https://adblockkeshi-reports.ohara-kureho.workers.dev")!

    /// Cloudflare Turnstile widget Site Key (Invisible mode).
    ///
    /// A-88 修正②の検証用: `-uiTestForceTurnstileFailure` 起動引数が付いているときだけ、
    /// Cloudflare 公式の「invisible widget で必ず失敗する」テスト用キーに切り替える
    /// (`https://developers.cloudflare.com/turnstile/troubleshooting/testing/`)。
    /// DEBUG ビルドかつ明示的な起動引数がある場合のみで、本番ビルド・通常起動には一切影響しない。
    static var turnstileSiteKey: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestForceTurnstileFailure") {
            return "2x00000000000000000000BB"
        }
        #endif
        return "0x4AAAAAADgOoutjQmgZGRxz"
    }

    /// Domain the widget is configured against (must match Cloudflare).
    static let turnstileHostname = "kureho.app"
}
