import XCTest
import UIKit
@testable import KhanhScanner

final class DocumentSessionRepositoryTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testCreateSessionPersistsBeforeCaptureBegins() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = DocumentSessionRepository(rootURL: rootURL)

        let session = try repository.createSession(at: createdAt)
        let reloaded = try DocumentSessionRepository(rootURL: rootURL).sessions()

        XCTAssertEqual(reloaded, [session])
        XCTAssertEqual(session.createdAt, createdAt)
        XCTAssertEqual(session.modifiedAt, createdAt)
        XCTAssertEqual(session.lifecycle, .active)
        XCTAssertTrue(session.pageIDs.isEmpty)
    }

    func testAppendPagesPersistsImagesAndOrderAcrossRepositoryInstances() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let first = image(color: .red, size: CGSize(width: 4, height: 6))
        let second = image(color: .blue, size: CGSize(width: 8, height: 3))

        let updated = try repository.appendPages([first, second], to: session.id)
        let reloadedRepository = DocumentSessionRepository(rootURL: rootURL)
        let reloadedSession = try XCTUnwrap(try reloadedRepository.session(id: session.id))
        let images = try reloadedRepository.images(for: reloadedSession)

        XCTAssertEqual(updated.pageIDs.count, 2)
        XCTAssertEqual(reloadedSession.pageIDs, updated.pageIDs)
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].size, first.size)
        XCTAssertEqual(images[1].size, second.size)
    }

    func testDeleteSessionRemovesMetadataAndPageAssets() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let sessionWithPage = try repository.appendPages([image(color: .green)], to: session.id)

        try repository.deleteSession(id: session.id)

        XCTAssertNil(try repository.session(id: session.id))
        XCTAssertThrowsError(try repository.images(for: sessionWithPage))
    }

    func testLifecycleCanBeArchivedAndResumedWithoutChangingPages() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let withPage = try repository.appendPages([image(color: .purple)], to: session.id)

        let archived = try repository.setLifecycle(.archived, for: session.id)
        let resumed = try repository.setLifecycle(.active, for: session.id)
        let appended = try repository.appendPages([image(color: .orange)], to: session.id)
        let reloaded = try XCTUnwrap(try DocumentSessionRepository(rootURL: rootURL).session(id: session.id))

        XCTAssertEqual(archived.lifecycle, .archived)
        XCTAssertEqual(resumed.lifecycle, .active)
        XCTAssertEqual(reloaded.lifecycle, .active)
        XCTAssertEqual(Array(appended.pageIDs.prefix(withPage.pageIDs.count)), withPage.pageIDs)
        XCTAssertEqual(reloaded.pageIDs, appended.pageIDs)
    }

    func testNestedFoldersPersistWithoutDepthLimitInTheModel() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let project = try repository.createFolder(name: "Project A")
        let receipts = try repository.createFolder(name: "Receipts", parentFolderID: project.id)
        let year = try repository.createFolder(name: "2027", parentFolderID: receipts.id)

        let reloaded = try DocumentSessionRepository(rootURL: rootURL).folders()

        XCTAssertEqual(reloaded.first(where: { $0.id == project.id })?.parentFolderID, nil)
        XCTAssertEqual(reloaded.first(where: { $0.id == receipts.id })?.parentFolderID, project.id)
        XCTAssertEqual(reloaded.first(where: { $0.id == year.id })?.parentFolderID, receipts.id)
    }

    func testCreateFolderMovesSelectedSessionsWithoutChangingPages() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let withPage = try repository.appendPages([image(color: .cyan)], to: session.id)

        let folder = try repository.createFolder(name: "Client", sessionIDs: [session.id])
        let moved = try XCTUnwrap(try repository.session(id: session.id))

        XCTAssertEqual(moved.folderID, folder.id)
        XCTAssertEqual(moved.pageIDs, withPage.pageIDs)
        XCTAssertEqual(try repository.images(for: moved).count, 1)
    }

    func testSessionCanMoveBetweenExistingFoldersAndBackToRoot() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let first = try repository.createFolder(name: "First", sessionIDs: [session.id])
        let second = try repository.createFolder(name: "Second")

        try repository.move(sessionIDs: [session.id], to: second.id)
        XCTAssertEqual(try repository.session(id: session.id)?.folderID, second.id)

        try repository.move(sessionIDs: [session.id], to: nil)
        XCTAssertNil(try repository.session(id: session.id)?.folderID)
        XCTAssertNotNil(try repository.folders().first(where: { $0.id == first.id }))
    }

    func testFolderMoveRejectsSelfAndDescendantDestinations() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let parent = try repository.createFolder(name: "Parent")
        let child = try repository.createFolder(name: "Child", parentFolderID: parent.id)
        let grandchild = try repository.createFolder(name: "Grandchild", parentFolderID: child.id)

        XCTAssertThrowsError(try repository.move(folderIDs: [parent.id], to: parent.id))
        XCTAssertThrowsError(try repository.move(folderIDs: [parent.id], to: grandchild.id))

        try repository.move(folderIDs: [grandchild.id], to: nil)
        XCTAssertNil(try repository.folders().first(where: { $0.id == grandchild.id })?.parentFolderID)
    }

    func testDeletingNonEmptyFolderNeverDeletesItsSessionsOrPages() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        try repository.appendPages([image(color: .brown)], to: session.id)
        let folder = try repository.createFolder(name: "Keep", sessionIDs: [session.id])

        XCTAssertThrowsError(try repository.deleteFolder(id: folder.id))

        let reloaded = try XCTUnwrap(try repository.session(id: session.id))
        XCTAssertEqual(reloaded.folderID, folder.id)
        XCTAssertEqual(try repository.images(for: reloaded).count, 1)
    }

    private func image(color: UIColor, size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
