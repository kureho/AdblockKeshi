import Foundation

/// 既存購入者（¥500/¥700 世代）を恒久 Pro として救済するかの閾値判定（純関数）。
/// StoreKit 2 の `AppTransaction.originalAppVersion`（iOS では CFBundleVersion）を使う。
///
/// 罠対策（tasks/v4-freemium-dns-plan.md §grandfather 準拠）:
/// - **Int 変換後の数値比較**（Apple 公式サンプルの文字列比較は "99" < "10000" が false になりバグる）
/// - **environment == .production 限定**（sandbox/審査/TestFlight は "1.0" を返す → 審査員に購入導線を見せる）
/// - originalAppVersion 欠落/Int 化不能時は **originalPurchaseDate < cutoff の補助判定**で救済
enum StoreEnvironment { case production, sandbox }

struct GrandfatherPolicy {

    /// 転換ビルドの CFBundleVersion（これ「未満」を legacy とみなす。履歴非単調対策で 10000 へジャンプ）。
    let conversionBuild: Int
    /// 補助判定の基準日（これ以前の購入は legacy）。転換当日に確定させる運用。
    let cutoffDate: Date

    /// 既存購入者か（= 恒久 Pro 付与対象）。
    func isLegacy(originalBuild: String?, originalPurchaseDate: Date?, environment: StoreEnvironment) -> Bool {
        // 審査/sandbox 環境（"1.0" を返す）では常に無効化＝審査員に購入導線を見せる
        guard environment == .production else { return false }
        // 主判定: build 番号を Int 変換して数値比較（文字列比較の "99" < "10000" バグを回避）
        if let build = originalBuild.flatMap({ Int($0) }) {
            return build < conversionBuild
        }
        // 補助判定: build 欠落 or Int 化不能（"1.0" 形式）→ 購入日が cutoff 以前なら legacy
        if let date = originalPurchaseDate {
            return date < cutoffDate
        }
        // どちらも判定材料が無い → 過少付与に倒す（無料扱い）
        return false
    }
}
