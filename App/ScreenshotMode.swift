import Foundation
import CoreGraphics

/// LP スクショ撮影用 `--screenshot-mode` モードの判定と共通 helper。
/// Release ビルドでは常に 0 を返すため本番 UI に影響しない。
enum ScreenshotMode {

    /// `--screenshot-mode` 起動引数があれば true（DEBUG only）。
    static var isActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        #else
        return false
        #endif
    }

    /// LP の iPhone モック内に流したときに content と画面端の余白を確保するための extra horizontal padding。
    static var extraHorizontalPadding: CGFloat {
        isActive ? 16 : 0
    }

    /// `--open-dns` 起動引数があれば DNS 設定画面へ直行する（DEBUG only・撮影用）。
    /// タップ操作なしで DNSSettingsView を撮るために使う。Release では常に false。
    static var autoOpenDNS: Bool {
        #if DEBUG
        return isActive && ProcessInfo.processInfo.arguments.contains("--open-dns")
        #else
        return false
        #endif
    }
}
