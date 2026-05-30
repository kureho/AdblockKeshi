import Foundation
import SafariServices

enum BlockerState: Equatable {
    case enabled
    case disabled
    case error(String)
}

/// SFContentBlockerManager のシグネチャ模倣（テスト時はモックを注入）
typealias StateFetcher = (String, @escaping (SFContentBlockerState?, Error?) -> Void) -> Void

final class ContentBlockerStateChecker {
    private let identifier: String
    private let fetcher: StateFetcher

    init(
        identifier: String = "com.kureho.adblockkeshi.blocker",
        fetcher: @escaping StateFetcher = { id, completion in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: id, completionHandler: completion)
        }
    ) {
        self.identifier = identifier
        self.fetcher = fetcher
    }

    func fetchState(completion: @escaping (BlockerState) -> Void) {
        fetcher(identifier) { state, error in
            if let error = error {
                completion(.error(error.localizedDescription))
                return
            }
            guard let state = state else {
                completion(.error("state unavailable"))
                return
            }
            completion(state.isEnabled ? .enabled : .disabled)
        }
    }
}
