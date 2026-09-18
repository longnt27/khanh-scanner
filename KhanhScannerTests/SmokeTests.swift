import XCTest
@testable import KhanhScanner

final class SmokeTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }

    func testShareCompletionOnlySucceedsForCompletedActivityWithoutError() {
        XCTAssertTrue(ShareCompletionPolicy.isSuccessful(completed: true, error: nil))
        XCTAssertFalse(ShareCompletionPolicy.isSuccessful(completed: false, error: nil))
        XCTAssertFalse(
            ShareCompletionPolicy.isSuccessful(
                completed: true,
                error: NSError(domain: "Share", code: 1)
            )
        )
    }
}
