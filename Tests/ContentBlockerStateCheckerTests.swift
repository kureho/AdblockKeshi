import XCTest
import SafariServices
@testable import AdblockKeshi

final class ContentBlockerStateCheckerTests: XCTestCase {

    func test_returns_error_when_fetcher_yields_error() {
        let testError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let mockFetcher: StateFetcher = { _, completion in
            completion(nil, testError)
        }
        let checker = ContentBlockerStateChecker(fetcher: mockFetcher)
        let exp = expectation(description: "error path")
        checker.fetchState { state in
            XCTAssertEqual(state, .error("boom"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func test_returns_error_when_state_is_nil() {
        let mockFetcher: StateFetcher = { _, completion in
            completion(nil, nil)
        }
        let checker = ContentBlockerStateChecker(fetcher: mockFetcher)
        let exp = expectation(description: "nil state")
        checker.fetchState { state in
            XCTAssertEqual(state, .error("state unavailable"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func test_passes_identifier_to_fetcher() {
        var capturedId: String?
        let mockFetcher: StateFetcher = { id, completion in
            capturedId = id
            completion(nil, NSError(domain: "test", code: 0))
        }
        let checker = ContentBlockerStateChecker(
            identifier: "test.bundle.id",
            fetcher: mockFetcher
        )
        let exp = expectation(description: "identifier captured")
        checker.fetchState { _ in
            XCTAssertEqual(capturedId, "test.bundle.id")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func test_default_identifier_matches_extension_bundle_id() {
        var capturedId: String?
        let mockFetcher: StateFetcher = { id, completion in
            capturedId = id
            completion(nil, NSError(domain: "test", code: 0))
        }
        let checker = ContentBlockerStateChecker(fetcher: mockFetcher)
        let exp = expectation(description: "default id")
        checker.fetchState { _ in
            XCTAssertEqual(capturedId, "com.kureho.adblockkeshi.blocker")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}
