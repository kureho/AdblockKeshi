import Foundation

@objc(ContentBlockerRequestHandler)
class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private let resolver: BlockerListResolver

    override init() {
        self.resolver = BlockerListResolver()
        super.init()
    }

    func beginRequest(with context: NSExtensionContext) {
        guard let url = resolver.resolve(),
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
}
