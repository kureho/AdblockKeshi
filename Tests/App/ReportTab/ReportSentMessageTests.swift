import XCTest
@testable import AdblockKeshi

/// 送信後の文言。D-lite では報告は **広告フィルタ改善の参考データ**であって、
/// 「報告したのでこの広告がすぐ消える」と誤認させてはいけない。
/// 個別対応を約束する表現（必ず対応 / 確認して修正 / N 日以内に反映）も禁止。
final class ReportSentMessageTests: XCTestCase {

    private static let forbidden = [
        "すぐに", "即", "必ず対応", "確認して修正", "日以内", "この端末",
        "反映されます", "ブロックされます", "消えます",
    ]

    func test_safari_message_framesReportAsImprovementData() {
        let body = ReportSentMessage.body(for: .safari)
        XCTAssertTrue(body.contains("広告フィルタ"), "改善の参考として使う旨を伝える")
        XCTAssertTrue(body.contains("参考"))
    }

    /// Safari 以外は Safari 用フィルタでは原理的に消せない。ここを黙るとまた同じ不満が出る。
    func test_otherApp_message_explainsContentBlockerCannotCoverIt() {
        let body = ReportSentMessage.body(for: .otherApp)
        XCTAssertTrue(body.contains("Safari"), "Safari 用フィルタの限界に触れる")
        XCTAssertTrue(body.contains("アプリ"))
    }

    func test_otherApp_message_buildsOnSafariMessage() {
        XCTAssertTrue(ReportSentMessage.body(for: .otherApp)
            .hasPrefix(ReportSentMessage.body(for: .safari)))
    }

    func test_noMessage_promisesIndividualHandlingOrImmediateEffect() {
        for seenIn in SeenIn.allCases {
            let body = ReportSentMessage.body(for: seenIn)
            for fragment in Self.forbidden {
                XCTAssertFalse(body.contains(fragment),
                               "\(seenIn) の文言に禁止表現「\(fragment)」が含まれている: \(body)")
            }
        }
    }

    func test_title_isNeutral() {
        XCTAssertFalse(ReportSentMessage.title.isEmpty)
        for fragment in Self.forbidden {
            XCTAssertFalse(ReportSentMessage.title.contains(fragment))
        }
    }

    // MARK: - v4.2.0 壊れ報告

    func test_adSuccess_usesSeenInMessage() {
        let success = ReportSuccess(kind: .adNotBlocked, seenIn: .otherApp, host: "a.example.com")
        XCTAssertEqual(ReportSentMessage.body(for: success), ReportSentMessage.body(for: .otherApp))
    }

    func test_brokenSafari_framesReportAsUnbreakData() {
        let body = ReportSentMessage.body(
            for: ReportSuccess(kind: .siteBroken, seenIn: .safari, host: "a.example.com"))
        XCTAssertTrue(body.contains("壊さずに"), "壊れ報告は「壊さないための参考データ」と伝える")
        XCTAssertTrue(body.contains("参考"))
    }

    /// アプリ内の不調は Content Blocker の例外では直らない → DNS 一時停止へ誘導する。
    func test_brokenOtherApp_pointsToDNSPause() {
        let body = ReportSentMessage.body(
            for: ReportSuccess(kind: .siteBroken, seenIn: .otherApp, host: "a.example.com"))
        XCTAssertTrue(body.contains("一時停止"))
    }

    func test_brokenMessages_avoidForbiddenPromises() {
        for seenIn in SeenIn.allCases {
            let body = ReportSentMessage.body(
                for: ReportSuccess(kind: .siteBroken, seenIn: seenIn, host: "a.example.com"))
            for fragment in Self.forbidden {
                XCTAssertFalse(body.contains(fragment),
                               "壊れ報告 (\(seenIn)) の文言に禁止表現「\(fragment)」: \(body)")
            }
        }
    }
}
