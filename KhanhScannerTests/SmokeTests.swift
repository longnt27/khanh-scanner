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
    func testLongPressSelectionEntersSelectionModeAndSelectsItem() {
        let item = LibraryItemID.session(UUID())
        var state = LibrarySelectionState()

        state.beginSelecting(item)

        XCTAssertTrue(state.isEditing)
        XCTAssertEqual(state.selection, [item])
    }

    func testFinishingSelectionClearsSelectedItems() {
        let item = LibraryItemID.folder(UUID())
        var state = LibrarySelectionState()
        state.beginSelecting(item)

        state.finish()

        XCTAssertFalse(state.isEditing)
        XCTAssertTrue(state.selection.isEmpty)
    }

}
