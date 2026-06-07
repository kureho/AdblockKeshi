import Foundation

/// Compile-time configuration for the v3.0 report pipeline. The Site Key is a
/// public credential (intended to ship in the iOS bundle); the corresponding
/// Secret Key lives only as a Cloudflare Worker secret.
enum AppConfig {
    /// Cloudflare Workers production endpoint.
    static let workersBaseURL = URL(string: "https://adblockkeshi-reports.ohara-kureho.workers.dev")!

    /// Cloudflare Turnstile widget Site Key (Invisible mode).
    static let turnstileSiteKey = "0x4AAAAAADgOoutjQmgZGRxz"

    /// Domain the widget is configured against (must match Cloudflare).
    static let turnstileHostname = "kureho.app"
}
