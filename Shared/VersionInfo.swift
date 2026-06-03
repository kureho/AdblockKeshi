import Foundation

/// CDN 側 version.json をデコードした構造。
/// `generated_at` は scripts/convert.sh が UTC ISO8601 で書込む。
struct VersionInfo: Equatable {
    let generatedAt: Date
    let ruleCount: Int
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

        return VersionInfo(generatedAt: date, ruleCount: ruleCount)
    }
}
