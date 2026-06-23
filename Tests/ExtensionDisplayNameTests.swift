import XCTest

/// Safari 設定（コンテンツブロッカー / 機能拡張）に出る各拡張の表示名を、出荷 Info.plist で固定する。
///
/// 実機事実（2026-06-24 kureho 目視・iPhone 17 Pro のスクショが根拠。iOS の表示挙動は推測で断定しない）:
/// iOS は **Content Blocker 型**拡張の一覧表示で、親アプリ名「広告消し — 」を自動で前置する。
/// そのため Content Blocker の CFBundleDisplayName に「広告消し — 」を含めると、実機で
/// 「広告消し — 広告消し — 基本保護」と二重化する。→ Content Blocker は役割名のみを持つ。
/// 一方 **Safari Web Extension 型**（遷移保護）は自動前置されないため、完全名
/// 「広告消し — 遷移保護」を CFBundleDisplayName に明示して持つ（実機で重複しないことを確認済み）。
///
/// CI は `xcodegen generate`（project.yml → Info.plist 再生成）の後に test を走らせるため、
/// ここで読む Info.plist は project.yml から再生成された出荷値になる（project.yml が真の source）。
final class ExtensionDisplayNameTests: XCTestCase {

    /// Tests/ExtensionDisplayNameTests.swift → 2 つ上が repo ルート。
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func infoPlist(_ relativePath: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(obj as? [String: Any], "\(relativePath) を辞書として読めない")
    }

    private func displayName(_ relativePath: String) throws -> String {
        try XCTUnwrap(infoPlist(relativePath)["CFBundleDisplayName"] as? String,
                      "\(relativePath) に CFBundleDisplayName が無い")
    }

    private func extensionPointID(_ relativePath: String) throws -> String? {
        (try infoPlist(relativePath)["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
    }

    func test_app_uses_product_name() throws {
        XCTAssertEqual(try displayName("App/Info.plist"), "広告消し")
    }

    /// Content Blocker 2拡張は役割名のみ（iOS が「広告消し — 」を自動前置するため）。
    func test_content_blocker_extensions_use_role_name_only() throws {
        let appName = try displayName("App/Info.plist")  // 広告消し

        XCTAssertEqual(try extensionPointID("Extension/Info.plist"), "com.apple.Safari.content-blocker")
        let basic = try displayName("Extension/Info.plist")
        XCTAssertEqual(basic, "基本保護")
        XCTAssertFalse(basic.contains(appName),
                       "Content Blocker 表示名に親アプリ名を含めると iOS 自動前置で二重化する")

        XCTAssertEqual(try extensionPointID("PopunderBlockerExtension/Info.plist"), "com.apple.Safari.content-blocker")
        let report = try displayName("PopunderBlockerExtension/Info.plist")
        XCTAssertEqual(report, "報告反映")
        XCTAssertFalse(report.contains(appName),
                       "Content Blocker 表示名に親アプリ名を含めると iOS 自動前置で二重化する")
    }

    /// Safari Web Extension（遷移保護）は自動前置されないため、完全名を保持する。
    func test_web_extension_keeps_full_display_name() throws {
        XCTAssertEqual(try extensionPointID("PopupShieldExtension/Info.plist"), "com.apple.Safari.web-extension")
        XCTAssertEqual(try displayName("PopupShieldExtension/Info.plist"), "広告消し — 遷移保護")
    }
}
