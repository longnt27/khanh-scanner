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

    func testReplacePagesPersistsEditedOrderAndRemovesOldAssets() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let original = try repository.appendPages(
            [
                image(color: .red, size: CGSize(width: 10, height: 20)),
                image(color: .blue, size: CGSize(width: 30, height: 40))
            ],
            to: session.id
        )

        let modifiedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let updated = try repository.replacePages(
            [
                image(color: .green, size: CGSize(width: 7, height: 9)),
                image(color: .orange, size: CGSize(width: 11, height: 13))
            ],
            in: session.id,
            modifiedAt: modifiedAt
        )
        let reloaded = try XCTUnwrap(
            try DocumentSessionRepository(rootURL: rootURL).session(id: session.id)
        )
        let images = try repository.images(for: reloaded)

        XCTAssertEqual(reloaded.pageIDs, updated.pageIDs)
        XCTAssertNotEqual(reloaded.pageIDs, original.pageIDs)
        XCTAssertEqual(reloaded.modifiedAt, modifiedAt)
        XCTAssertEqual(images.map(\.size), [
            CGSize(width: 7, height: 9),
            CGSize(width: 11, height: 13)
        ])
        XCTAssertThrowsError(try repository.images(for: original))
    }

    func testDeleteSessionRemovesMetadataAndPageAssets() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let sessionWithPage = try repository.appendPages([image(color: .green)], to: session.id)

        try repository.deleteSession(id: session.id)

        XCTAssertNil(try repository.session(id: session.id))
        XCTAssertThrowsError(try repository.images(for: sessionWithPage))
    }

    func testPersistedSessionNoLongerStoresLifecycleState() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        _ = try repository.createSession()

        let catalogURL = rootURL.appendingPathComponent("sessions.json")
        let json = try XCTUnwrap(String(data: Data(contentsOf: catalogURL), encoding: .utf8))

        XCTAssertFalse(json.contains("\"lifecycle\""))
    }

    func testLegacyCatalogWithLifecycleStillLoads() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let id = UUID()
        let createdAt = "2026-09-18T12:00:00Z"
        let legacy = """
        {
          "version": 2,
          "sessions": [{
            "id": "\(id.uuidString)",
            "createdAt": "\(createdAt)",
            "modifiedAt": "\(createdAt)",
            "pageIDs": [],
            "lifecycle": "archived"
          }],
          "folders": []
        }
        """
        try Data(legacy.utf8).write(to: rootURL.appendingPathComponent("sessions.json"))

        let sessions = try DocumentSessionRepository(rootURL: rootURL).sessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, id)
        XCTAssertFalse(sessions[0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(sessions[0].pageIDs.isEmpty)
    }

    func testRenameSessionTrimsAndPersistsName() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()

        let renamed = try repository.renameSession(
            id: session.id,
            to: "  Client Contract  ",
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let reloaded = try XCTUnwrap(
            try DocumentSessionRepository(rootURL: rootURL).session(id: session.id)
        )

        XCTAssertEqual(renamed.name, "Client Contract")
        XCTAssertEqual(reloaded.name, "Client Contract")
        XCTAssertEqual(reloaded.modifiedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testRenameSessionRejectsBlankNameWithoutChangingExistingName() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        _ = try repository.renameSession(id: session.id, to: "Invoice")

        XCTAssertThrowsError(try repository.renameSession(id: session.id, to: "   \n  "))

        XCTAssertEqual(
            try XCTUnwrap(repository.session(id: session.id)).name,
            "Invoice"
        )
    }

    func testEditablePageRecordPersistsSourceCropRotationAndRenderedImage() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let pageID = UUID()
        let crop = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.12, y: 0.91),
            topRight: CGPoint(x: 0.88, y: 0.89),
            bottomRight: CGPoint(x: 0.86, y: 0.11),
            bottomLeft: CGPoint(x: 0.14, y: 0.09)
        )
        let page = DocumentPage(
            id: pageID,
            cropQuadrilateral: crop,
            rotation: .clockwise90,
            isLegacySource: false
        )
        let source = image(color: .red, size: CGSize(width: 120, height: 180))
        let rendered = image(color: .blue, size: CGSize(width: 80, height: 110))

        _ = try repository.appendPageRecords(
            [DocumentPageAssets(page: page, sourceImage: source, renderedImage: rendered)],
            to: session.id
        )

        let reloadedRepository = DocumentSessionRepository(rootURL: rootURL)
        let records = try reloadedRepository.pageRecords(for: session.id)
        let reloaded = try XCTUnwrap(records.first)
        let reloadedSource = try reloadedRepository.sourceImage(for: pageID, in: session.id)
        let reloadedRendered = try reloadedRepository.renderedImage(for: pageID, in: session.id)

        XCTAssertEqual(records.map(\.id), [pageID])
        XCTAssertEqual(reloaded.cropQuadrilateral, crop)
        XCTAssertEqual(reloaded.rotation, .clockwise90)
        XCTAssertFalse(reloaded.isLegacySource)
        XCTAssertEqual(reloadedSource.size, source.size)
        XCTAssertEqual(reloadedRendered.size, rendered.size)
    }

    func testLegacyFlatPNGLoadsAsFullBoundsEditablePage() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sessionID = UUID()
        let pageID = UUID()
        let createdAt = "2026-09-18T12:00:00Z"
        let legacy = """
        {
          "version": 2,
          "sessions": [{
            "id": "\(sessionID.uuidString)",
            "createdAt": "\(createdAt)",
            "modifiedAt": "\(createdAt)",
            "pageIDs": ["\(pageID.uuidString)"]
          }],
          "folders": []
        }
        """
        try Data(legacy.utf8).write(to: rootURL.appendingPathComponent("sessions.json"))

        let pageDirectory = rootURL
            .appendingPathComponent("Pages", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pageDirectory, withIntermediateDirectories: true)
        let legacyImage = image(color: .green, size: CGSize(width: 60, height: 90))
        try XCTUnwrap(legacyImage.pngData()).write(
            to: pageDirectory.appendingPathComponent("\(pageID.uuidString).png")
        )

        let repository = DocumentSessionRepository(rootURL: rootURL)
        let record = try XCTUnwrap(repository.pageRecords(for: sessionID).first)
        let source = try repository.sourceImage(for: pageID, in: sessionID)
        let rendered = try repository.renderedImage(for: pageID, in: sessionID)

        XCTAssertTrue(record.isLegacySource)
        XCTAssertEqual(record.rotation, .none)
        XCTAssertEqual(record.cropQuadrilateral, .fullBounds)
        XCTAssertEqual(source.size, legacyImage.size)
        XCTAssertEqual(rendered.size, legacyImage.size)
    }

    func testEditablePageCanUpdateReorderAndDeleteWithoutLosingOtherSources() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let session = try repository.createSession()
        let first = DocumentPage(id: UUID(), isLegacySource: false)
        let second = DocumentPage(id: UUID(), isLegacySource: false)

        _ = try repository.appendPageRecords(
            [
                DocumentPageAssets(
                    page: first,
                    sourceImage: image(color: .red, size: CGSize(width: 80, height: 120)),
                    renderedImage: image(color: .red, size: CGSize(width: 60, height: 90))
                ),
                DocumentPageAssets(
                    page: second,
                    sourceImage: image(color: .blue, size: CGSize(width: 100, height: 140)),
                    renderedImage: image(color: .blue, size: CGSize(width: 70, height: 100))
                )
            ],
            to: session.id
        )

        var editedSecond = second
        editedSecond.cropQuadrilateral = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        editedSecond.rotation = .clockwise90
        try repository.updatePage(
            editedSecond,
            in: session.id,
            renderedImage: image(color: .cyan, size: CGSize(width: 90, height: 60))
        )
        try repository.reorderPages([second.id, first.id], in: session.id)

        XCTAssertEqual(try repository.pageRecords(for: session.id).map(\.id), [second.id, first.id])
        XCTAssertEqual(
            try repository.pageRecords(for: session.id).first?.cropQuadrilateral,
            editedSecond.cropQuadrilateral
        )
        XCTAssertEqual(try repository.sourceImage(for: first.id, in: session.id).size, CGSize(width: 80, height: 120))

        try repository.deletePage(id: second.id, from: session.id)

        XCTAssertEqual(try repository.pageRecords(for: session.id).map(\.id), [first.id])
        XCTAssertThrowsError(try repository.sourceImage(for: second.id, in: session.id))
        XCTAssertEqual(try repository.sourceImage(for: first.id, in: session.id).size, CGSize(width: 80, height: 120))
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

    func testBulkDeleteRemovesSelectedItemsAndFolderDescendants() throws {
        let repository = DocumentSessionRepository(rootURL: rootURL)
        let loose = try repository.createSession()
        let looseWithPage = try repository.appendPages([image(color: .red)], to: loose.id)

        let parent = try repository.createFolder(name: "Parent")
        let child = try repository.createFolder(name: "Child", parentFolderID: parent.id)
        let nested = try repository.createSession(folderID: child.id)
        let nestedWithPage = try repository.appendPages([image(color: .blue)], to: nested.id)

        let keepFolder = try repository.createFolder(name: "Keep")
        let keep = try repository.createSession(folderID: keepFolder.id)
        _ = try repository.appendPages([image(color: .green)], to: keep.id)

        try repository.deleteItems(
            sessionIDs: [loose.id],
            folderIDs: [parent.id]
        )

        XCTAssertNil(try repository.session(id: loose.id))
        XCTAssertNil(try repository.session(id: nested.id))
        XCTAssertFalse(try repository.folders().contains(where: { $0.id == parent.id }))
        XCTAssertFalse(try repository.folders().contains(where: { $0.id == child.id }))
        XCTAssertNotNil(try repository.session(id: keep.id))
        XCTAssertTrue(try repository.folders().contains(where: { $0.id == keepFolder.id }))

        XCTAssertThrowsError(try repository.images(for: looseWithPage))
        XCTAssertThrowsError(try repository.images(for: nestedWithPage))
        XCTAssertEqual(try repository.images(for: try XCTUnwrap(repository.session(id: keep.id))).count, 1)
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
