import Foundation
import UIKit

enum DocumentSessionRepositoryError: LocalizedError {
    case sessionNotFound
    case imageEncodingFailed
    case pageAssetMissing

    var errorDescription: String? {
        switch self {
        case .sessionNotFound: "The document session no longer exists."
        case .imageEncodingFailed: "A scanned page could not be saved."
        case .pageAssetMissing: "A saved page could not be loaded."
        }
    }
}

final class DocumentSessionRepository {
    private struct Catalog: Codable {
        let version: Int
        var sessions: [DocumentSession]
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = DocumentSessionRepository.defaultRootURL(), fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport.appendingPathComponent("KhanhScanner", isDirectory: true)
    }

    func sessions() throws -> [DocumentSession] {
        try loadCatalog().sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func session(id: UUID) throws -> DocumentSession? {
        try loadCatalog().sessions.first { $0.id == id }
    }

    @discardableResult
    func createSession(at date: Date = Date()) throws -> DocumentSession {
        var catalog = try loadCatalog()
        let session = DocumentSession(createdAt: date)
        catalog.sessions.append(session)
        try saveCatalog(catalog)
        return session
    }

    @discardableResult
    func appendPages(_ images: [UIImage], to sessionID: UUID, modifiedAt: Date = Date()) throws -> DocumentSession {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        guard !images.isEmpty else { return catalog.sessions[index] }

        let directory = pageDirectory(for: sessionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var newPageIDs: [UUID] = []

        do {
            for image in images {
                guard let data = image.pngData() else {
                    throw DocumentSessionRepositoryError.imageEncodingFailed
                }
                let pageID = UUID()
                try data.write(to: pageURL(sessionID: sessionID, pageID: pageID), options: .atomic)
                newPageIDs.append(pageID)
            }
            catalog.sessions[index].pageIDs.append(contentsOf: newPageIDs)
            catalog.sessions[index].modifiedAt = modifiedAt
            try saveCatalog(catalog)
            return catalog.sessions[index]
        } catch {
            for pageID in newPageIDs {
                try? fileManager.removeItem(at: pageURL(sessionID: sessionID, pageID: pageID))
            }
            throw error
        }
    }

    func images(for session: DocumentSession) throws -> [UIImage] {
        try session.pageIDs.map { pageID in
            let url = pageURL(sessionID: session.id, pageID: pageID)
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                throw DocumentSessionRepositoryError.pageAssetMissing
            }
            return image
        }
    }

    @discardableResult
    func setLifecycle(
        _ lifecycle: DocumentLifecycle,
        for sessionID: UUID,
        modifiedAt: Date = Date()
    ) throws -> DocumentSession {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        catalog.sessions[index].lifecycle = lifecycle
        catalog.sessions[index].modifiedAt = modifiedAt
        try saveCatalog(catalog)
        return catalog.sessions[index]
    }

    func deleteSession(id: UUID) throws {
        var catalog = try loadCatalog()
        guard catalog.sessions.contains(where: { $0.id == id }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        catalog.sessions.removeAll { $0.id == id }
        try saveCatalog(catalog)
        let directory = pageDirectory(for: id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private var catalogURL: URL {
        rootURL.appendingPathComponent("sessions.json")
    }

    private func pageDirectory(for sessionID: UUID) -> URL {
        rootURL
            .appendingPathComponent("Pages", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func pageURL(sessionID: UUID, pageID: UUID) -> URL {
        pageDirectory(for: sessionID).appendingPathComponent("\(pageID.uuidString).png")
    }

    private func loadCatalog() throws -> Catalog {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            return Catalog(version: 1, sessions: [])
        }
        return try decoder.decode(Catalog.self, from: Data(contentsOf: catalogURL))
    }

    private func saveCatalog(_ catalog: Catalog) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
    }
}
