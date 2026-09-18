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

    func images(for sessionID: UUID) throws -> [UIImage] {
        guard let session = try repository.session(id: sessionID) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        return try repository.images(for: session)
    }

    func setLifecycle(_ lifecycle: DocumentLifecycle, for sessionID: UUID) throws {
        try repository.setLifecycle(lifecycle, for: sessionID)
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
