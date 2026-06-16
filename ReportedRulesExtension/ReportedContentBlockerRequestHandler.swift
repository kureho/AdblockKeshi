import Foundation

@objc(ReportedContentBlockerRequestHandler)
class ReportedContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private let resolver: BlockerListResolver

    override init() {
        // 報告から反映された学習フィルタを App Group の rules-reported.json から読む。
        // 未取得時は bundle 同梱の空配列にフォールバック（標準側 ContentBlockerRequestHandler と同型）。
        self.resolver = ReportedRulesResolver.make()
        super.init()
    }

    func beginRequest(with context: NSExtensionContext) {
        // App Group → bundle の fallback chain
        guard let url = resolver.resolve() else {
            // bundle に rules-reported.json も無いとき（CI 設定不備等）
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "rules-reported.json not found in App Group or bundle"]
            ))
            return
        }

        guard let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "ReportedContentBlocker",
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
