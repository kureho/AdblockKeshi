import Foundation

/// 決済/銀行/大手/政府などの重要ドメイン。誤ってブロックすると被害が大きいので保護する。
///
/// ★D-lite: **報告フォームの送信前ガードには使わない**。報告は「広告が消えなかったページ」の
/// 改善用データなので、yahoo.co.jp 等を送るのは正常な操作（自動昇格を止めるのはサーバ側 L3 の責務）。
/// 現在の利用先は DNS 経路の安全弁（`DNSCriticalGuard`）。
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
