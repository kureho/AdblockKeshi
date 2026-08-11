import Foundation

protocol ReportDiagnosticsCollecting: Sendable {
    /// 取れたものだけ詰めて返す。**throw しない・呼び出し側を待たせすぎない**。
    func collect() async -> ReportDiagnostics
}

/// 診断情報を best-effort で集める。
///
/// 各項目は独立していて、1 つ失敗しても他は残る。取得元は差し替え可能にしてあり、
/// 既定値は実機で動く実装（`ReportDiagnosticsSources`）を指す。
struct ReportDiagnosticsCollector: ReportDiagnosticsCollecting {

    typealias FlagProvider = @Sendable () async -> Bool?
    typealias TextProvider = @Sendable () -> String?

    private let blockerEnabledProvider: FlagProvider
    private let dnsEnabledProvider: FlagProvider
    private let appVersionProvider: TextProvider
    private let appBuildProvider: TextProvider
    private let filterVersionProvider: TextProvider

    init(blockerEnabled: @escaping FlagProvider = ReportDiagnosticsSources.blockerEnabled,
         dnsEnabled: @escaping FlagProvider = ReportDiagnosticsSources.dnsEnabled,
         appVersion: @escaping TextProvider = ReportDiagnosticsSources.appVersion,
         appBuild: @escaping TextProvider = ReportDiagnosticsSources.appBuild,
         filterVersion: @escaping TextProvider = ReportDiagnosticsSources.filterVersion) {
        self.blockerEnabledProvider = blockerEnabled
        self.dnsEnabledProvider = dnsEnabled
        self.appVersionProvider = appVersion
        self.appBuildProvider = appBuild
        self.filterVersionProvider = filterVersion
    }

    func collect() async -> ReportDiagnostics {
        // 非同期 2 つは並行に。どちらも内部で期限を持つので待ち時間は上限つき。
        async let blocker = blockerEnabledProvider()
        async let dns = dnsEnabledProvider()
        return ReportDiagnostics(
            blockerEnabled: await blocker,
            dnsEnabled: await dns,
            appVersion: Self.sanitize(appVersionProvider()),
            appBuild: Self.sanitize(appBuildProvider()),
            filterVersion: Self.sanitize(filterVersionProvider())
        )
    }

    /// サーバ側 `toNullableText`（`workers/src/handlers/submit.ts`）と同じ基準で落とす。
    /// 空文字・空白のみ・64 字超は送っても NULL になるので、クライアントで先に nil にする。
    static func sanitize(_ value: String?, maxLength: Int = 64) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= maxLength
        else { return nil }
        return trimmed
    }
}

/// 「実際に端末へ適用された variant の generated_at」を診断用の文字列へ落とす純ロジック。
/// 表示用（`FilterUpdateDisplay`）と同じ日付を、機械可読な UTC の `yyyy-MM-dd` で表す。
enum ReportFilterVersion {
    static func format(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
