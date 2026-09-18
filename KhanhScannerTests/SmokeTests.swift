import XCTest
import UIKit
@testable import KhanhScanner

final class SmokeTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }

    func testScannerPresentationCannotBeDismissedInteractively() {
        let controller = UIViewController()

        ScanDismissalPolicy.protect(controller)

        XCTAssertTrue(controller.isModalInPresentation)
    }
}
