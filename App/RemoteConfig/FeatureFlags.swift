import Foundation

/// Static facade over `RemoteConfigStore` for v3 feature gates.
///
/// `report_tab_enabled`  – per-feature toggle, defaults to `true`.
/// `emergency_kill_switch` – fail-CLOSED master switch. When set to `true`,
/// every gated feature returns its disabled state, regardless of the
/// per-feature flag's value.
public enum FeatureFlags {
    private static let emergencyKillSwitchKey = "emergency_kill_switch"
    private static let reportTabEnabledKey = "report_tab_enabled"

    public static func reportTabEnabled(store: RemoteConfigStore = .shared) -> Bool {
        if store.boolValue(forKey: emergencyKillSwitchKey, default: false) {
            return false
        }
        return store.boolValue(forKey: reportTabEnabledKey, default: true)
    }

    public static func emergencyKillSwitchEnabled(store: RemoteConfigStore = .shared) -> Bool {
        store.boolValue(forKey: emergencyKillSwitchKey, default: false)
    }
}
