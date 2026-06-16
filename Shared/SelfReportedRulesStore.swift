import Foundation

/// 自己報告ファストレーンの保存層。
///
/// - `rules-self.json`   … 報告した本人の端末ルール（即時追記）
/// - `rules-global.json` … サーバ検証を通って配信されたグローバルルール（FilterDownloader が保存）
/// - `rules-reported.json` … 上2つを union した結果。報告Extension(`ReportedContentBlockerRequestHandler`)
///                           が `ReportedRulesResolver` 経由で読む実ファイル。
///
/// 重複は `trigger.url-filter` で排除する。
struct SelfReportedRulesStore {
    static let selfFilename = "rules-self.json"
    static let globalFilename = "rules-global.json"
    static let mergedFilename = "rules-reported.json"

    let directory: URL
    private let fileManager: FileManager

    /// テスト用: 任意ディレクトリを直接指定。
    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// 本番用: App Group コンテナ直下を使う。コンテナが取れなければ nil。
    init?(appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
          fileManager: FileManager = .default) {
        guard let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.directory = container
        self.fileManager = fileManager
    }

    /// 自己報告ルールを追加し merged を再構築。新規追加されたら true（重複は false）。
    @discardableResult
    func appendSelfRule(_ rule: ContentBlockerRule) throws -> Bool {
        var selfRules = loadSelfRules()
        let key = rule.trigger.urlFilter
        guard !selfRules.contains(where: { $0.trigger.urlFilter == key }) else {
            return false
        }
        selfRules.append(rule)
        try write(selfRules, to: Self.selfFilename)
        try rebuildMerged()
        return true
    }

    /// self + global を union（url-filter で dedup）して merged を書く。
    func rebuildMerged() throws {
        var seen = Set<String>()
        var union: [ContentBlockerRule] = []
        for rule in loadSelfRules() + loadGlobalRules() {
            let key = rule.trigger.urlFilter
            if seen.insert(key).inserted {
                union.append(rule)
            }
        }
        try write(union, to: Self.mergedFilename)
    }

    func loadSelfRules() -> [ContentBlockerRule] { load(Self.selfFilename) }
    func loadGlobalRules() -> [ContentBlockerRule] { load(Self.globalFilename) }
    func loadMergedRules() -> [ContentBlockerRule] { load(Self.mergedFilename) }

    // MARK: - IO

    private func load(_ filename: String) -> [ContentBlockerRule] {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([ContentBlockerRule].self, from: data)
        else { return [] }
        return rules
    }

    private func write(_ rules: [ContentBlockerRule], to filename: String) throws {
        let data = try JSONEncoder().encode(rules)
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic])
    }
}
