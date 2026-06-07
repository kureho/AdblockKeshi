import Foundation

@objc(ReportedContentBlockerRequestHandler)
class ReportedContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        // Phase 1: bundle 同梱 reported-rules.json (初期空配列) を返すだけ
        // Phase 5 で App Group fallback chain を追加
        guard let url = Bundle.main.url(forResource: "reported-rules", withExtension: "json") else {
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "reported-rules.json not found in bundle"]
            ))
            return
        }

        guard let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "NSItemProvider init failed"]
            ))
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
