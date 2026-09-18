import SwiftUI

final class DocumentLibrary: ObservableObject {
    @Published private(set) var sessions: [DocumentSession] = []
    @Published private(set) var folders: [DocumentFolder] = []
    @Published private(set) var loadError: String?

    private let repository: DocumentSessionRepository

    init(repository: DocumentSessionRepository = DocumentSessionRepository()) {
        self.repository = repository
        reload()
    }

    func session(id: UUID) -> DocumentSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func createSession(in folderID: UUID? = nil) throws -> DocumentSession {
        let session = try repository.createSession(folderID: folderID)
        try reloadThrowing()
        return session
    }

    func appendPages(_ pages: [UIImage], to sessionID: UUID) throws {
        try repository.appendPages(pages, to: sessionID)
        try reloadThrowing()
    }

    func replacePages(_ pages: [UIImage], in sessionID: UUID) throws {
        try repository.replacePages(pages, in: sessionID)
        try reloadThrowing()
    }

    func pageRecords(for sessionID: UUID) throws -> [DocumentPage] {
        try repository.pageRecords(for: sessionID)
    }

    func pageAssets(for sessionID: UUID) throws -> [DocumentPageAssets] {
        try repository.pageAssets(for: sessionID)
    }

    func sourceImage(for pageID: UUID, in sessionID: UUID) throws -> UIImage {
        try repository.sourceImage(for: pageID, in: sessionID)
    }

    func renderedImage(for pageID: UUID, in sessionID: UUID) throws -> UIImage {
        try repository.renderedImage(for: pageID, in: sessionID)
    }

    func appendPageRecords(_ assets: [DocumentPageAssets], to sessionID: UUID) throws {
        try repository.appendPageRecords(assets, to: sessionID)
        try reloadThrowing()
    }

    func updatePage(_ page: DocumentPage, in sessionID: UUID, renderedImage: UIImage) throws {
        try repository.updatePage(page, in: sessionID, renderedImage: renderedImage)
        try reloadThrowing()
    }

    func deletePage(id pageID: UUID, from sessionID: UUID) throws {
        try repository.deletePage(id: pageID, from: sessionID)
        try reloadThrowing()
    }

    func reorderPages(_ pageIDs: [UUID], in sessionID: UUID) throws {
        try repository.reorderPages(pageIDs, in: sessionID)
        try reloadThrowing()
    }

    func images(for sessionID: UUID) throws -> [UIImage] {
        guard let session = try repository.session(id: sessionID) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        return try repository.images(for: session)
    }

    func renameSession(id: UUID, to name: String) throws {
        try repository.renameSession(id: id, to: name)
        try reloadThrowing()
    }

    func deleteSession(id: UUID) throws {
        try repository.deleteSession(id: id)
        try reloadThrowing()
    }

    @discardableResult
    func createFolder(
        name: String,
        parentFolderID: UUID?,
        sessionIDs: [UUID] = [],
        folderIDs: [UUID] = []
    ) throws -> DocumentFolder {
        let folder = try repository.createFolder(
            name: name,
            parentFolderID: parentFolderID,
            sessionIDs: sessionIDs,
            folderIDs: folderIDs
        )
        try reloadThrowing()
        return folder
    }

    func move(sessionIDs: [UUID], folderIDs: [UUID], to destinationFolderID: UUID?) throws {
        try repository.move(sessionIDs: sessionIDs, folderIDs: folderIDs, to: destinationFolderID)
        try reloadThrowing()
    }

    func deleteFolder(id: UUID) throws {
        try repository.deleteFolder(id: id)
        try reloadThrowing()
    }

    func deleteItems(sessionIDs: [UUID], folderIDs: [UUID]) throws {
        try repository.deleteItems(sessionIDs: sessionIDs, folderIDs: folderIDs)
        try reloadThrowing()
    }

    private func reload() {
        do {
            try reloadThrowing()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reloadThrowing() throws {
        sessions = try repository.sessions()
        folders = try repository.folders()
        loadError = nil
    }
}
