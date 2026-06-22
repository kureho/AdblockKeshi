import SafariServices
import os.log

/// 強力モード（Safari Web Extension）のネイティブハンドラ。
///
/// 状態（有効/サイト別一時停止）は拡張側の `storage.local` が保持し、`background.js` が
/// `scripting.registerContentScripts` の登録/解除を行う。ネイティブ側は state を持たないため、
/// ここでは native message を受けても空応答を返すだけ（将来のアプリ連携用フックとして存置）。
/// プライバシー: URL・ページ内容は受け取らない・保存しない・外部送信しない。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
