import Foundation

@objc(ContentBlockerRequestHandler)
class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private let resolver: BlockerListResolver
    private let stateStore: StateStore?

    override init() {
        self.resolver = BlockerListResolver()
        self.stateStore = StateStore.sharedAppGroup()
        super.init()
    }

    func beginRequest(with context: NSExtensionContext) {
        // v2.0: state.json を読む（失敗時は両方 ON 扱い = fail-safe）
        let state = stateStore?.read() ?? .default

        // App Group → bundle → empty-rules.json の fallback chain
        guard let url = resolver.resolve(for: state) else {
            // ここに来るのは bundle に empty-rules.json も無いとき（CI 設定不備等）
            context.cancelRequest(withError: NSError(
                domain: "ContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No rules file found, including bundle empty-rules"]
            ))
            return
        }

        guard let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "ContentBlocker",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "NSItemProvider init failed for \(url.path)"]
            ))
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
