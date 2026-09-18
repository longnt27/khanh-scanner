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
        try repository.appendPages([image(color: .green)], to: session.id)

        try repository.deleteSession(id: session.id)

        XCTAssertNil(try repository.session(id: session.id))
        XCTAssertThrowsError(try repository.images(for: session))
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
