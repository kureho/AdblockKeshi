import Foundation

@objc(ContentBlockerRequestHandler)
class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    static let appGroupIdentifier = "group.com.kureho.adblockkeshi.shared"
    static let filterFilename = "blockerList.json"

    func beginRequest(with context: NSExtensionContext) {
        guard let url = resolveBlockerListURL(),
              let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "ContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "blockerList.json not found"]
            ))
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }

    private func resolveBlockerListURL() -> URL? {
        // 1. App Group コンテナ（Plan B で runtime download が書き込む先）
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) {
            let candidate = containerURL.appendingPathComponent(Self.filterFilename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        // 2. Bundle フォールバック（Plan A バンドル分）
        return Bundle.main.url(forResource: "blockerList", withExtension: "json")
    }
}
