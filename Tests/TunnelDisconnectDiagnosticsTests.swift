import XCTest
import NetworkExtension

/// ★診断専用★ 直近のトンネル切断理由（NE framework が保存した最後の NSError）を print する。
/// assert はしない（常に pass）。実機での障害調査時に -only-testing で単発実行する。
/// 実行: xcodebuild test -destination 'platform=iOS,id=<device>' \
///        -only-testing:AdblockKeshiTests/TunnelDisconnectDiagnosticsTests
final class TunnelDisconnectDiagnosticsTests: XCTestCase {

    func test_printLastDisconnectError() async throws {
        let managers: [NETunnelProviderManager]
        do {
            managers = try await NETunnelProviderManager.loadAllFromPreferences()
        } catch {
            throw XCTSkip("NE 利用不可（sim/CI 等）: \(error.localizedDescription)")
        }
        guard let manager = managers.first else {
            print("[DIAG] manager なし（VPN 構成未登録）")
            return
        }
        print("[DIAG] status=\(manager.connection.status.rawValue) isEnabled=\(manager.isEnabled)")
        let error: Error? = await withCheckedContinuation { cont in
            manager.connection.fetchLastDisconnectError { cont.resume(returning: $0) }
        }
        guard let error else {
            print("[DIAG] lastDisconnectError = nil（正常切断 or 記録なし）")
            return
        }
        printError(error as NSError, prefix: "[DIAG] last")
    }

    private func printError(_ error: NSError, prefix: String, depth: Int = 0) {
        guard depth < 5 else { return }
        print("\(prefix) domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
        print("\(prefix) userInfo=\(error.userInfo)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            printError(underlying, prefix: prefix + " >u", depth: depth + 1)
        }
        for (i, u) in error.underlyingErrors.enumerated() where (u as NSError) !== (error.userInfo[NSUnderlyingErrorKey] as? NSError) {
            printError(u as NSError, prefix: prefix + " >u\(i)", depth: depth + 1)
        }
    }
}
