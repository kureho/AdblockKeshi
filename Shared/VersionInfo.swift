import Foundation

/// CDN 側 version.json をデコードした構造。
/// `generated_at` は scripts/convert.sh が UTC ISO8601 で書込む。
/// `reported` は v3.0 以降の任意セクション。報告経由で追加された rule の
/// 件数 / 直近 1 ヶ月の増加数を保持し、ContentView の moat 表示に使う。
struct VersionInfo: Equatable {
    struct ReportedMetrics: Equatable {
        let ruleCount: Int
        let addedLastMonth: Int
    }

    let generatedAt: Date
    let ruleCount: Int
    let reported: ReportedMetrics?
}

/// version.json を App Group → bundle の順で解決する read-only store。
/// App Group コンテナに最新が無ければ bundle 同梱版を返す。両方とも無ければ nil。
struct VersionInfoStore {
    let appGroupIdentifier: String
    let filename: String
    let bundle: Bundle
    private let fileManager: FileManager

    init(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        filename: String = "version.json",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.filename = filename
        self.bundle = bundle
        self.fileManager = fileManager
    }

    /// 最終更新情報を返す。App Group 優先、なければ bundle、両方無ければ nil。
    func read() -> VersionInfo? {
        if let data = readAppGroup() ?? readBundle() {
            return Self.decode(data)
        }
        return nil
    }

    func readAppGroup() -> Data? {
        guard let url = fileManager
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
                .appendingPathComponent(filename)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    func readBundle() -> Data? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 任意の version.json バイト列をデコードする (テスト容易性のため static)。
    static func decode(_ data: Data) -> VersionInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any],
              let generatedAtString = dict["generated_at"] as? String,
              let ruleCount = dict["rule_count"] as? Int
        else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: generatedAtString) else { return nil }

        let reported = decodeReported(dict["reported"])
        return VersionInfo(generatedAt: date, ruleCount: ruleCount, reported: reported)
    }

    /// `reported` セクションは型不整合時に nil 扱い (全体の decode は成功させる)。
    private static func decodeReported(_ raw: Any?) -> VersionInfo.ReportedMetrics? {
        guard let dict = raw as? [String: Any],
              let ruleCount = dict["rule_count"] as? Int,
              let addedLastMonth = dict["added_last_month"] as? Int
        else { return nil }
        return VersionInfo.ReportedMetrics(
            ruleCount: ruleCount,
            addedLastMonth: addedLastMonth
        )
    }
}

extension VersionInfo {
    /// ContentView 完了画面に moat (= 蓄積競争優位) を表示するためのテキスト。
    /// `reported` セクションが無い or `ruleCount == 0` のときは表示しない (nil)。
    /// 先月の追加件数が 0 の場合は件数のみ、>0 の場合は「（先月 +N）」を付ける。
    var moatDisplayText: String? {
        guard let metrics = reported, metrics.ruleCount > 0 else { return nil }
        let countString = "\(metrics.ruleCount) 件"
        if metrics.addedLastMonth > 0 {
            return "報告で追加: \(countString)（先月 +\(metrics.addedLastMonth)）"
        }
        return "報告で追加: \(countString)"
    }
}
