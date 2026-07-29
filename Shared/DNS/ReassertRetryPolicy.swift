import Foundation

/// ネットワーク切替（reassert）後にシステム DNS snapshot をリトライするポリシー。
/// Wi-Fi join 直後は DHCP が DNS を configure するまで数秒〜十数秒かかる。
/// 予算が短いと日常の Wi-Fi 切替で cancel（トグルが勝手に OFF）になる
/// （2026-07-29 実機で 2 秒予算が尽きて自動停止を実測 → v4.0.1 で延長）。
/// リトライ中は tunnel settings が外れていて端末の通信は素通しで生きているため、
/// 長く待つこと自体の害は「保護されない時間が延びる」だけに留まる。
enum ReassertRetryPolicy {
    /// snapshot を試す最大回数（0.5 秒 × 60 = 30 秒。Wi-Fi DHCP の遅い環境も吸収する）
    static let maxAttempts = 60
    /// 試行間隔（秒）
    static let interval: TimeInterval = 0.5
}
