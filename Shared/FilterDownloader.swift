import Foundation

actor FilterDownloader {
    static let defaultURL = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/blockerList.json")!
    static let defaultVersionURL = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/version.json")!

    let blockerListURL: URL
    let versionURL: URL
    let appGroupIdentifier: String
    let filename: String
    let session: URLSession

    init(
        blockerListURL: URL = FilterDownloader.defaultURL,
        versionURL: URL = FilterDownloader.defaultVersionURL,
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        filename: String = "blockerList.json",
        session: URLSession = .shared
    ) {
        self.blockerListURL = blockerListURL
        self.versionURL = versionURL
        self.appGroupIdentifier = appGroupIdentifier
        self.filename = filename
        self.session = session
    }

    /// 最新フィルタを取得して App Group コンテナに atomic write。成功時にバイト数を返す。
    @discardableResult
    func downloadAndStore() async throws -> Int {
        let (data, response) = try await session.data(from: blockerListURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "FilterDownloader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) from \(blockerListURL)"]
            )
        }

        // JSON validity check（壊れた payload を排除）
        _ = try JSONSerialization.jsonObject(with: data, options: [])

        guard let containerURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw NSError(
                domain: "FilterDownloader",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable: \(appGroupIdentifier)"]
            )
        }

        let destination = containerURL.appendingPathComponent(filename)
        try data.write(to: destination, options: [.atomic])

        // version.json は補助情報。失敗しても blockerList の DL 結果は維持する。
        await downloadVersionInfoBestEffort(containerURL: containerURL)

        return data.count
    }

    /// CDN の version.json を取得して App Group コンテナに atomic write する。
    /// 失敗時は黙って戻る (補助情報のため UI 上 fallback 表示できれば良い)。
    private func downloadVersionInfoBestEffort(containerURL: URL) async {
        do {
            let (data, response) = try await session.data(from: versionURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            let destination = containerURL.appendingPathComponent("version.json")
            try data.write(to: destination, options: [.atomic])
        } catch {
            return
        }
    }
}
