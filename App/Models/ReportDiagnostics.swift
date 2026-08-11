import Foundation

/// 報告に自動で添える診断情報。ユーザーには何も聞かない。
///
/// **全項目 nullable。1 つも取れなくても報告送信は必ず成功させる**
/// （「診断が取れないから報告できない」は本末転倒）。
/// PII は含めない — 端末を特定しうる値や利用者本人に紐づく値は入れないこと。
struct ReportDiagnostics: Equatable, Sendable {
    /// Safari Content Blocker が有効だったか。無効なら「消えない」のは当然なので切り分けに効く。
    var blockerEnabled: Bool?
    /// DNS 保護が **実際に動いていたか**（購入したかではない）。
    var dnsEnabled: Bool?
    var appVersion: String?
    var appBuild: String?
    /// 端末が実際に読んでいたフィルタの生成日（`yyyy-MM-dd`, UTC）。
    var filterVersion: String?

    init(blockerEnabled: Bool? = nil,
         dnsEnabled: Bool? = nil,
         appVersion: String? = nil,
         appBuild: String? = nil,
         filterVersion: String? = nil) {
        self.blockerEnabled = blockerEnabled
        self.dnsEnabled = dnsEnabled
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.filterVersion = filterVersion
    }

    /// 何も取得できなかったときの値。これで送っても報告は成立する。
    static let unavailable = ReportDiagnostics()
}
