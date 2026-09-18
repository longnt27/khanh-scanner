import SwiftUI

final class DocumentLibrary: ObservableObject {
    @Published private(set) var sessions: [DocumentSession] = []
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
    func createSession() throws -> DocumentSession {
        let session = try repository.createSession()
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

    func deleteSession(id: UUID) throws {
        try repository.deleteSession(id: id)
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
        loadError = nil
    }
}
