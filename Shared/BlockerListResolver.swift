import Foundation

struct BlockerListResolver {
    let appGroupIdentifier: String
    let filterFilename: String
    let bundle: Bundle
    private let fileManager: FileManager

    init(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        filterFilename: String = "blockerList.json",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.filterFilename = filterFilename
        self.bundle = bundle
        self.fileManager = fileManager
    }

    /// App Group コンテナ優先 → Bundle フォールバック。
    /// Plan B で runtime download が App Group に書き込んだ最新フィルタを優先採用するための構造。
    func resolve() -> URL? {
        if let url = appGroupURL(), fileManager.fileExists(atPath: url.path) {
            return url
        }
        return bundleURL()
    }

    func appGroupURL() -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filterFilename)
    }

    func bundleURL() -> URL? {
        let basename = (filterFilename as NSString).deletingPathExtension
        let ext = (filterFilename as NSString).pathExtension
        return bundle.url(forResource: basename, withExtension: ext)
    }
}
