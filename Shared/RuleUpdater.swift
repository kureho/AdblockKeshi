import Foundation
import CryptoKit

/// 適用済み variant の記録（App Group の applied-rules.json に永続化）。
/// 「フィルタ最終更新」表示と、次回更新時の sha 比較・ルール数ガードの基準に使う。
struct AppliedRulesRecord: Codable, Equatable {
    /// 適用した payload の sha256（hex）。CDN manifest の宣言値と一致検証済みの値。
    let sha256: String
    /// CDN 側でルールが生成された日時（manifest の generated_at）。UI の「フィルタ最終更新」に使う。
    let generatedAt: Date
    /// 適用した payload のルール数。次回更新のルール数下限ガード（過去実績）の基準。
    let ruleCount: Int
    /// 端末に適用した日時。
    let appliedAt: Date
}

/// applied-rules.json の read/write store。壊れていたら空扱い（fail-safe・次回更新で再記録される）。
struct AppliedRulesStore {
    static let filename = "applied-rules.json"
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init?(appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared") {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.directory = container
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.filename) }

    func read() -> [String: AppliedRulesRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: AppliedRulesRecord].self, from: data)) ?? [:]
    }

    func write(_ records: [String: AppliedRulesRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// variant 1 つ分の更新計画（CDN manifest から導出）。
struct RuleVariantPlan: Equatable {
    /// App Group 上のファイル名 = BlockerListResolver.filename(for:) が返す名前。
    let variantFilename: String
    /// CDN 上の実体 URL（広告 variant のみ blockerList.json という別名である点に注意）。
    let downloadURL: URL
    /// manifest が宣言する sha256（hex）。
    let expectedSHA256: String
    /// manifest の generated_at。
    let generatedAt: Date
    /// 適用記録が無い端末でのルール数下限ガード基準（CI パイプラインの limit 値由来:
    /// convert.sh 150k / build_merged --limit 130k / build_security --limit 30k / empty 0）。
    let defaultBaselineRuleCount: Int
}

/// manifest 解析・sha 比較・ルール数ガードの純ロジック。
enum RuleUpdatePlanner {
    static let cdnBaseURL = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/")!

    enum PlannerError: Error, LocalizedError {
        case invalidManifest(String)
        var errorDescription: String? {
            if case .invalidManifest(let detail) = self { return "invalid manifest: \(detail)" }
            return nil
        }
    }

    /// version.json（広告 = blockerList.json の sha）と version-security.json
    /// （merged/security/empty の sha）から 4 variant の更新計画を作る。
    static func plans(versionJSON: Data, versionSecurityJSON: Data) throws -> [RuleVariantPlan] {
        guard let version = (try? JSONSerialization.jsonObject(with: versionJSON)) as? [String: Any]
        else { throw PlannerError.invalidManifest("version.json is not a JSON object") }
        guard let security = (try? JSONSerialization.jsonObject(with: versionSecurityJSON)) as? [String: Any]
        else { throw PlannerError.invalidManifest("version-security.json is not a JSON object") }

        guard let adSHA = version["blocker_list_sha256"] as? String,
              let adGeneratedRaw = version["generated_at"] as? String,
              let adGenerated = parseISO8601(adGeneratedRaw)
        else { throw PlannerError.invalidManifest("version.json missing blocker_list_sha256/generated_at") }

        guard let mergedSHA = security["merged-rules_sha256"] as? String,
              let securitySHA = security["security-rules_sha256"] as? String,
              let emptySHA = security["empty-rules_sha256"] as? String,
              let secGeneratedRaw = security["generated_at"] as? String,
              let secGenerated = parseISO8601(secGeneratedRaw)
        else { throw PlannerError.invalidManifest("version-security.json missing sha/generated_at keys") }

        return [
            RuleVariantPlan(
                variantFilename: "merged-rules.json",
                downloadURL: cdnBaseURL.appendingPathComponent("merged-rules.json"),
                expectedSHA256: mergedSHA,
                generatedAt: secGenerated,
                defaultBaselineRuleCount: 130_000),
            RuleVariantPlan(
                variantFilename: "ad-rules.json",
                downloadURL: cdnBaseURL.appendingPathComponent("blockerList.json"),
                expectedSHA256: adSHA,
                generatedAt: adGenerated,
                defaultBaselineRuleCount: 150_000),
            RuleVariantPlan(
                variantFilename: "security-rules.json",
                downloadURL: cdnBaseURL.appendingPathComponent("security-rules.json"),
                expectedSHA256: securitySHA,
                generatedAt: secGenerated,
                defaultBaselineRuleCount: 30_000),
            RuleVariantPlan(
                variantFilename: "empty-rules.json",
                downloadURL: cdnBaseURL.appendingPathComponent("empty-rules.json"),
                expectedSHA256: emptySHA,
                generatedAt: secGenerated,
                defaultBaselineRuleCount: 0),
        ]
    }

    /// ISO8601 parse。version-security.json の generated_at は Python isoformat の
    /// 6 桁小数秒（ISO8601DateFormatter 素のままだと失敗する）なので小数部フォールバック付き。
    static func parseISO8601(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        if let range = string.range(of: #"\.\d+"#, options: .regularExpression) {
            return plain.date(from: string.replacingCharacters(in: range, with: ""))
        }
        return nil
    }

    /// sha 差分がある variant のみ DL する判定。記録なし = 要取得。
    static func needsDownload(expectedSHA256: String, applied: AppliedRulesRecord?) -> Bool {
        guard let applied else { return true }
        return applied.sha256 != expectedSHA256
    }

    /// ルール数ガード。下限: 過去実績（baseline）の 50% 未満は拒否（CDN 側の生成事故対策）。
    /// 上限: WebKit の 150,000 超は拒否（Safari compile 不能なものを配らない）。
    static func validateRuleCount(_ count: Int, baseline: Int) -> Bool {
        if count > ReportedRuleBudget.webKitLimit { return false }
        if count * 2 < baseline { return false }
        return true
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// updateIfNeeded() の結果（variant ファイル名単位）。
struct RuleUpdateOutcome: Equatable {
    /// DL → 検証 → App Group へ適用した variant。
    var applied: [String] = []
    /// 手元（App Group/bundle）の内容が既に manifest と一致していて DL 不要だった variant（記録のみ作成）。
    var recordedWithoutDownload: [String] = []
    /// 適用記録と sha 一致 = 最新だった variant（何もしない）。
    var skipped: [String] = []
    /// DL/検証失敗で棄却した variant（既存ルール維持）。
    var failed: [String] = []
    /// 適用があり reload を実行したか。
    var reloaded: Bool = false
}

/// CDN の variant 単位実行時更新（spec 2026-06-02-anti-phishing-design.md §RuleUpdater の実装）。
///
/// 手順: manifest（version.json / version-security.json）の sha256 を適用記録と比較 →
/// **差分がある variant のみ** DL → sha256 検証 → JSON 構文 + ルール数ガード →
/// App Group へ atomic write（BlockerListResolver.resolve(for:) が読む名前）→ 記録 → reload。
/// 失敗時は既存ルールを維持する（App Group → bundle のフォールバックチェーンを壊さない）。
/// 旧実装が毎起動 DL していた 22MB blockerList.json（読む者がいない）はここで掃除する。
actor RuleUpdater {
    static let defaultVersionURL = RuleUpdatePlanner.cdnBaseURL
        .appendingPathComponent("version.json")
    static let defaultVersionSecurityURL = RuleUpdatePlanner.cdnBaseURL
        .appendingPathComponent("version-security.json")
    /// 旧実装（毎起動 22MB DL）が App Group に残した遺物。読むコードはもう無い。
    static let legacyFilenames = [
        "blockerList.json",
        "combined-blockerList.json",
        "combined-blockerList.json.meta",
    ]

    typealias Fetch = @Sendable (URL) async throws -> Data

    enum UpdateError: Error, LocalizedError {
        case shaMismatch(String)
        case notARuleArray(String)
        case ruleCountRejected(String, count: Int, baseline: Int)

        var errorDescription: String? {
            switch self {
            case .shaMismatch(let v): return "\(v): payload sha256 does not match manifest"
            case .notARuleArray(let v): return "\(v): payload is not a JSON array"
            case .ruleCountRejected(let v, let count, let baseline):
                return "\(v): rule count \(count) rejected (baseline \(baseline), webKitLimit \(ReportedRuleBudget.webKitLimit))"
            }
        }
    }

    let directory: URL
    let versionURL: URL
    let versionSecurityURL: URL
    let fetch: Fetch
    let bundledFileURL: @Sendable (String) -> URL?
    let reload: (@Sendable () async -> Void)?
    let now: @Sendable () -> Date

    init(
        directory: URL,
        versionURL: URL = RuleUpdater.defaultVersionURL,
        versionSecurityURL: URL = RuleUpdater.defaultVersionSecurityURL,
        fetch: @escaping Fetch = RuleUpdater.defaultFetch,
        bundledFileURL: @escaping @Sendable (String) -> URL? = RuleUpdater.defaultBundledFileURL,
        reload: (@Sendable () async -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.versionURL = versionURL
        self.versionSecurityURL = versionSecurityURL
        self.fetch = fetch
        self.bundledFileURL = bundledFileURL
        self.reload = reload
        self.now = now
    }

    /// App Group コンテナを directory にする convenience initializer（本番用）。
    init?(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        reload: (@Sendable () async -> Void)? = nil
    ) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.init(directory: container, reload: reload)
    }

    static func defaultFetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "RuleUpdater",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) from \(url)"]
            )
        }
        return data
    }

    /// bundle 同梱 variant の URL 解決。variant 群は ContentBlockerExtension.appex に同梱されている
    /// （App bundle 直下には無い）ため、main → appex の順で探す。
    static func defaultBundledFileURL(_ filename: String) -> URL? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext) { return url }
        if let plugins = Bundle.main.builtInPlugInsURL {
            let appexURL = plugins.appendingPathComponent("ContentBlockerExtension.appex")
            if let appex = Bundle(url: appexURL),
               let url = appex.url(forResource: base, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// manifest を取得して差分 variant のみ更新する。manifest 自体が取れない（オフライン等）は throw。
    /// variant 単位の失敗は outcome.failed に載せて続行（既存ルール維持）。
    func updateIfNeeded() async throws -> RuleUpdateOutcome {
        removeLegacyArtifacts()

        let versionData = try await fetch(versionURL)
        let versionSecurityData = try await fetch(versionSecurityURL)
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionData, versionSecurityJSON: versionSecurityData)

        let store = AppliedRulesStore(directory: directory)
        var records = store.read()
        var outcome = RuleUpdateOutcome()

        for plan in plans {
            let variant = plan.variantFilename
            guard RuleUpdatePlanner.needsDownload(
                expectedSHA256: plan.expectedSHA256, applied: records[variant])
            else {
                outcome.skipped.append(variant)
                continue
            }

            // 適用記録なしでも手元（App Group / bundle）の内容が manifest と一致していれば
            // DL せず記録のみ作る（新規インストール直後や記録欠損時の無駄 DL 回避）。
            if records[variant] == nil,
               let localData = localVariantData(variant),
               RuleUpdatePlanner.sha256Hex(localData) == plan.expectedSHA256,
               let localCount = ruleCount(of: localData) {
                records[variant] = AppliedRulesRecord(
                    sha256: plan.expectedSHA256,
                    generatedAt: plan.generatedAt,
                    ruleCount: localCount,
                    appliedAt: now())
                try? store.write(records)
                outcome.recordedWithoutDownload.append(variant)
                continue
            }

            do {
                let data = try await fetch(plan.downloadURL)
                guard RuleUpdatePlanner.sha256Hex(data) == plan.expectedSHA256 else {
                    throw UpdateError.shaMismatch(variant)
                }
                guard let count = ruleCount(of: data) else {
                    throw UpdateError.notARuleArray(variant)
                }
                let baseline = records[variant]?.ruleCount ?? plan.defaultBaselineRuleCount
                guard RuleUpdatePlanner.validateRuleCount(count, baseline: baseline) else {
                    throw UpdateError.ruleCountRejected(variant, count: count, baseline: baseline)
                }
                // atomic write: Extension が torn read しない。失敗時はここまで到達しない = 既存維持。
                try data.write(to: directory.appendingPathComponent(variant), options: [.atomic])
                records[variant] = AppliedRulesRecord(
                    sha256: plan.expectedSHA256,
                    generatedAt: plan.generatedAt,
                    ruleCount: count,
                    appliedAt: now())
                try store.write(records)
                outcome.applied.append(variant)
            } catch {
                print("[RuleUpdater] \(variant) rejected: \(error.localizedDescription)")
                outcome.failed.append(variant)
            }
        }

        // version.json は moat（報告で追加 N 件）表示用に App Group へ同期する（best-effort）。
        // 「フィルタ最終更新」の日付には使わない（それは AppliedRulesRecord.generatedAt が担う）。
        try? versionData.write(
            to: directory.appendingPathComponent("version.json"), options: [.atomic])

        if !outcome.applied.isEmpty {
            await reload?()
            outcome.reloaded = true
        }
        return outcome
    }

    // MARK: - private

    private func removeLegacyArtifacts() {
        for name in Self.legacyFilenames {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// App Group（優先）→ bundle の順で variant の現内容を読む。
    private func localVariantData(_ filename: String) -> Data? {
        let appGroupFile = directory.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: appGroupFile) { return data }
        guard let bundled = bundledFileURL(filename) else { return nil }
        return try? Data(contentsOf: bundled)
    }

    /// JSON 構文チェック + ルール数取得。top-level が配列でなければ nil（Content Blocker 形式違反）。
    private func ruleCount(of data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let array = object as? [Any]
        else { return nil }
        return array.count
    }
}
