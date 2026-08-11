import Foundation

/// 報告由来ルールの保存層。
///
/// - `rules-self.json`   … 旧「自己報告ファストレーン」で本人の端末に書かれたルール。
///                         **D-lite で廃止**。新規に書くことはなく、残骸は起動時に purge する
///                         （報告は改善用データであって、その端末のブロック指定ではない）。
/// - `rules-global.json` … サーバ検証を通って配信されたグローバルルール（FilterDownloader が保存）。
///                         **これが唯一の現役供給源。絶対に消さない。**
/// - `rules-reported.json` … 上2つを union した安全なルール集合。4→3 統合後は
///                           `CombinedRuleListCoordinator` が `safeMergedReportedRules()` 経由で
///                           読み、標準 ContentBlocker の combined-<state> に統合する。
///
/// 重複はルール内容で排除する。
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

    /// 既存端末治癒（D-lite）: 自己報告ルールを全消しして merged を作り直す。
    ///
    /// `rules-self.json` を空にするだけで、`rules-global.json`（CDN 由来 = L6 の成果物）は
    /// 一切触らない。`rebuildMerged()` が global だけから merged を作り直すので、
    /// サーバ検証済みの保護は無傷のまま「自分で報告した host が自分だけブロックされる」状態を解く。
    ///
    /// ネットワーク非依存・idempotent（毎起動呼んでよい）。self の除去 or merged 内容の変化が
    /// 起きたら true。global 由来の危険ルールが merged から strip される場合も true になり、
    /// 呼び出し側の reload 判断に使える。
    @discardableResult
    func purgeSelfRules() throws -> Bool {
        let hadSelfRules = !loadSelfRules().isEmpty
        if hadSelfRules { try write([], to: Self.selfFilename) }
        let mergedChanged = try rebuildMerged()
        return hadSelfRules || mergedChanged
    }

    /// self + global を union して merged を書く。
    /// 防御多層: 経路を問わず document ブロック(旧形式)は merged から除外する
    /// （CDN/global 経由で混入しても無効化）。dedup はルール内容で行う
    /// （cosmetic は url-filter `.*` を共有するため url-filter dedup では取りこぼす）。
    /// 戻り値: merged ファイルの中身が以前と変わったら true（呼び出し側の reload 判断用）。
    @discardableResult
    func rebuildMerged() throws -> Bool {
        let union = safeMergedReportedRules()
        let previous = loadMergedRules()
        try write(union, to: Self.mergedFilename)
        return union != previous
    }

    /// self ∪ global を「document ブロック除外 + structural dedup」した安全なルール集合を返す。
    /// 並び順は **global → self**（self を末尾に置く）。予算超過時に `ReportedRuleBudget.selectReported`
    /// が末尾を優先保持する。D-lite 以降 self は常に空なので実質 global のみだが、
    /// purge 前の端末が起動しきるまでの過渡状態のために union は残す。
    /// dedup は内容一致で行い、最初の出現（global 側）を残す。
    func safeMergedReportedRules() -> [ContentBlockerRule] {
        var seen = Set<ContentBlockerRule>()
        var union: [ContentBlockerRule] = []
        for rule in loadGlobalRules() + loadSelfRules() {
            guard !ReportedRuleSafety.isDocumentBlockingRisk(rule) else { continue }
            if seen.insert(rule).inserted {
                union.append(rule)
            }
        }
        return union
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
