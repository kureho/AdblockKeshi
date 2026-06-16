import Foundation

@objc(PopunderContentBlockerRequestHandler)
class PopunderContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private let resolver: BlockerListResolver

    override init() {
        // 既知 popunder/タップ乗っ取り広告網の script-block ルールを App Group → bundle で解決。
        // 標準側 ContentBlockerRequestHandler と同型。
        self.resolver = PopunderRulesResolver.make()
        super.init()
    }

    func beginRequest(with context: NSExtensionContext) {
        guard let url = resolver.resolve() else {
            context.cancelRequest(withError: NSError(
                domain: "PopunderContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "popunder-rules.json not found in App Group or bundle"]
            ))
            return
        }

        guard let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "PopunderContentBlocker",
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
