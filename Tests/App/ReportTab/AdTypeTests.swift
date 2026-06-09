import XCTest
@testable import AdblockKeshi

final class AdTypeTests: XCTestCase {
    func test_rawValues_matchServerEnum() {
        // Workers `AD_TYPES` (workers/src/lib/ad-type.ts) と同じ値・同じ順序。
        let expected = [
            "interstitial",
            "popup",
            "autoplay_video",
            "sticky_banner",
            "fake_close",
            "fake_notification",
            "phishing",
            "redirect",
            "preroll",
            "misleading_link",
            "other",
        ]
        XCTAssertEqual(AdType.allCases.map(\.rawValue), expected)
    }

    func test_allCases_areIdentifiableByRawValue() {
        let ids = Set(AdType.allCases.map(\.id))
        XCTAssertEqual(ids.count, AdType.allCases.count)
        XCTAssertEqual(ids, Set(AdType.allCases.map(\.rawValue)))
    }

    func test_labels_areJapaneseAndNonEmpty() {
        // 全 10 個に日本語ラベルが付いていること。空文字なし。
        for type in AdType.allCases {
            XCTAssertFalse(type.label.isEmpty, "\(type) label must not be empty")
            // ASCII のみで構成されたラベルは無いことを確認 (日本語が入っている)
            let isASCIIOnly = type.label.unicodeScalars.allSatisfy { $0.isASCII }
            XCTAssertFalse(isASCIIOnly, "\(type) label must include Japanese: \(type.label)")
        }
    }
}
