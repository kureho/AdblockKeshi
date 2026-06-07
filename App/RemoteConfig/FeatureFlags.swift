import Foundation

/// Static facade over `RemoteConfigStore` for v3 feature gates.
///
/// Spec rev4 §6 evaluation order:
///  - `emergency_kill_switch` is the **fail-CLOSED master switch**. Defaults
///    to `true` when no cache exists (cold start before the first successful
///    CDN fetch), so Tab B stays hidden until the CDN confirms `false`.
///  - `report_tab_enabled` is a per-feature toggle, defaults to `true`, and
///    is only consulted when the kill switch resolves to `false`.
public enum FeatureFlags {
    private static let emergencyKillSwitchKey = "emergency_kill_switch"
    private static let reportTabEnabledKey = "report_tab_enabled"

    public static func reportTabEnabled(store: RemoteConfigStore = .shared) -> Bool {
        if store.boolValue(forKey: emergencyKillSwitchKey, default: true) {
            return false
        }
        return store.boolValue(forKey: reportTabEnabledKey, default: true)
    }

    public static func emergencyKillSwitchEnabled(store: RemoteConfigStore = .shared) -> Bool {
        store.boolValue(forKey: emergencyKillSwitchKey, default: true)
    }
}
