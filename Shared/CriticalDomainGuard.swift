import Foundation

/// 自己報告ファストレーンの安全弁。決済/銀行/大手/政府などの重要ドメインは、
/// 誤って報告されても端末でブロックしない。
/// サーバ `workers/src/lib/critical-list.ts` の CRITICAL_DOMAINS と同一リスト・同一判定
/// （完全一致 + `.<critical>` サフィックス一致でサブドメインも保護）。
enum CriticalDomainGuard {

    /// サーバ critical-list.ts と同期。更新時は両方を合わせること。
    static let criticalDomains: Set<String> = [
        // Apple & services
        "apple.com", "icloud.com", "me.com", "mac.com", "itunes.com",
        // Google & services
        "google.com", "gmail.com", "youtube.com", "googleusercontent.com", "gstatic.com",
        // Microsoft
        "microsoft.com", "outlook.com", "live.com", "office.com", "azure.com",
        // Amazon
        "amazon.com", "amazon.co.jp", "amazonaws.com",
        // Meta
        "meta.com", "facebook.com", "instagram.com", "whatsapp.com",
        // Twitter/X
        "twitter.com", "x.com", "t.co",
        // Devops/Code
        "linkedin.com", "github.com", "cloudflare.com",
        // Japan e-commerce
        "yahoo.co.jp", "rakuten.co.jp", "mercari.com",
        // Japan gov
        "mhlw.go.jp", "meti.go.jp", "mof.go.jp", "jnto.go.jp",
        // Japan media
        "nhk.or.jp", "mainichi.jp", "asahi.com", "nikkei.com",
        // kureho own
        "kureho.app", "kureho.com",
        // Payment
        "visa.com", "mastercard.com", "paypal.com", "stripe.com",
        // Banks
        "mizuhobank.co.jp", "smbc.co.jp", "mufg.jp",
        // Search engines
        "bing.com", "duckduckgo.com",
    ]

    static func isCritical(_ host: String) -> Bool {
        let domain = host.lowercased()
        if criticalDomains.contains(domain) { return true }
        for critical in criticalDomains where domain.hasSuffix("." + critical) {
            return true
        }
        return false
    }
}
