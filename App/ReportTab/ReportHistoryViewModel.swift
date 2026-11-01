import Foundation
import SwiftUI

/// v3.x 以降、報告履歴は端末ローカル保存に切り替えた（履歴の一覧はサーバーから取らない）。
/// このファイルでは旧 ViewModel 形を残さず、`LocalReportHistoryStore` を
/// View 側で直接 `@ObservedObject` する設計に統一する。
///
/// 旧 `ReportHistoryFetcher` プロトコル / `ReportHistoryCache` / `ReportHistoryState`
/// は撤去済み（StubReportAPIClient の history extension も削除）。
