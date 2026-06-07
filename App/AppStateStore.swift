import Foundation
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var currentSnapshot: ContentRuleListSnapshot?

    private let checker: ContentRuleListStateChecker

    init(checker: ContentRuleListStateChecker = SFContentBlockerStateChecker()) {
        self.checker = checker
    }

    func refresh() async {
        currentSnapshot = await checker.check()
    }

    var shouldShowOnboarding: Bool {
        currentSnapshot?.mode == .bothDisabled
    }
}
