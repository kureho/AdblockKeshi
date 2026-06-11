import UIKit

/// サポート/フィードバック導線の共通定義。
/// 不満の受け皿をストアレビューではなくサポートに向ける (ASC support URL と同一)。
enum SupportLink {
    static let contactURLString = "https://kureho.app/contact?product=adblockkeshi"

    @MainActor
    static func openContact() {
        if let url = URL(string: contactURLString) {
            UIApplication.shared.open(url)
        }
    }
}
