import XCTest
@testable import AdblockKeshi

/// 診断情報は「取れたら添える」だけの補助情報。
/// 全項目 nullable で、1 つでも取れなかったら他まで巻き添えにしない。
final class ReportDiagnosticsCollectorTests: XCTestCase {

    func test_collects_allValues_fromProviders() async {
        let collector = ReportDiagnosticsCollector(
            blockerEnabled: { true },
            dnsEnabled: { false },
            appVersion: { "4.1.0" },
            appBuild: { "10004" },
            filterVersion: { "2026-08-01" }
        )
        let diagnostics = await collector.collect()

        XCTAssertEqual(diagnostics.blockerEnabled, true)
        XCTAssertEqual(diagnostics.dnsEnabled, false)
        XCTAssertEqual(diagnostics.appVersion, "4.1.0")
        XCTAssertEqual(diagnostics.appBuild, "10004")
        XCTAssertEqual(diagnostics.filterVersion, "2026-08-01")
    }

    func test_allProvidersUnavailable_yieldsEmptyDiagnostics() async {
        let collector = ReportDiagnosticsCollector(
            blockerEnabled: { nil },
            dnsEnabled: { nil },
            appVersion: { nil },
            appBuild: { nil },
            filterVersion: { nil }
        )
        let diagnostics = await collector.collect()
        XCTAssertEqual(diagnostics, ReportDiagnostics.unavailable)
    }

    /// 1 項目が取れなくても、取れた項目は必ず残る。
    func test_partialFailure_keepsAvailableValues() async {
        let collector = ReportDiagnosticsCollector(
            blockerEnabled: { nil },
            dnsEnabled: { true },
            appVersion: { "4.1.0" },
            appBuild: { nil },
            filterVersion: { "2026-08-01" }
        )
        let diagnostics = await collector.collect()

        XCTAssertNil(diagnostics.blockerEnabled)
        XCTAssertEqual(diagnostics.dnsEnabled, true)
        XCTAssertEqual(diagnostics.appVersion, "4.1.0")
        XCTAssertNil(diagnostics.appBuild)
        XCTAssertEqual(diagnostics.filterVersion, "2026-08-01")
    }

    /// 空文字・空白のみ・64 字超はサーバ側で NULL 扱いになる（`toNullableText`）。
    /// クライアントでも同じ基準で落として、無意味な値を送らない。
    func test_blankAndOverlongText_isDroppedToNil() async {
        let collector = ReportDiagnosticsCollector(
            blockerEnabled: { nil },
            dnsEnabled: { nil },
            appVersion: { "   " },
            appBuild: { "" },
            filterVersion: { String(repeating: "x", count: 65) }
        )
        let diagnostics = await collector.collect()

        XCTAssertNil(diagnostics.appVersion)
        XCTAssertNil(diagnostics.appBuild)
        XCTAssertNil(diagnostics.filterVersion)
    }

    func test_unavailable_isAllNil() {
        let empty = ReportDiagnostics.unavailable
        XCTAssertNil(empty.blockerEnabled)
        XCTAssertNil(empty.dnsEnabled)
        XCTAssertNil(empty.appVersion)
        XCTAssertNil(empty.appBuild)
        XCTAssertNil(empty.filterVersion)
    }
}

/// 「実際に端末へ適用された variant の generated_at」を診断用の文字列に落とす純ロジック。
final class ReportFilterVersionTests: XCTestCase {

    func test_formatsDateAsUTCFullDate() {
        // 2026-08-01T00:00:00Z
        let date = Date(timeIntervalSince1970: 1_785_542_400)
        XCTAssertEqual(ReportFilterVersion.format(date), "2026-08-01")
    }

    func test_returnsNil_whenDateUnavailable() {
        XCTAssertNil(ReportFilterVersion.format(nil))
    }
}
