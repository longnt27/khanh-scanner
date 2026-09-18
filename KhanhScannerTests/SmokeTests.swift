import XCTest
import UIKit
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

    func testScannerPresentationCannotBeDismissedInteractively() {
        let controller = UIViewController()

        ScanDismissalPolicy.protect(controller)

        XCTAssertTrue(controller.isModalInPresentation)
    }
}
