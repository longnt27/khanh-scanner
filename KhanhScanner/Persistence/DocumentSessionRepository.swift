import Foundation
import UIKit

enum DocumentSessionRepositoryError: LocalizedError {
    case sessionNotFound
    case folderNotFound
    case invalidFolderName
    case invalidDocumentName
    case cyclicFolderRelationship
    case folderNotEmpty
    case imageEncodingFailed
    case pageAssetMissing

    var errorDescription: String? {
        switch self {
        case .sessionNotFound: "The document session no longer exists."
        case .folderNotFound: "The folder no longer exists."
        case .invalidFolderName: "Enter a folder name."
        case .invalidDocumentName: "Enter a document name."
        case .cyclicFolderRelationship: "A folder cannot be moved into itself or one of its subfolders."
        case .folderNotEmpty: "Move this folder's contents before deleting it."
        case .imageEncodingFailed: "A scanned page could not be saved."
        case .pageAssetMissing: "A saved page could not be loaded."
        }
    }
}

final class DocumentSessionRepository {
    private struct Catalog: Codable {
        let version: Int
        var sessions: [DocumentSession]
        var folders: [DocumentFolder]

        init(version: Int = 2, sessions: [DocumentSession] = [], folders: [DocumentFolder] = []) {
            self.version = version
            self.sessions = sessions
            self.folders = folders
        }

        private enum CodingKeys: String, CodingKey {
            case version, sessions, folders
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = max(try values.decodeIfPresent(Int.self, forKey: .version) ?? 1, 2)
            sessions = try values.decodeIfPresent([DocumentSession].self, forKey: .sessions) ?? []
            folders = try values.decodeIfPresent([DocumentFolder].self, forKey: .folders) ?? []
        }
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

    func folders() throws -> [DocumentFolder] {
        try loadCatalog().folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func session(id: UUID) throws -> DocumentSession? {
        try loadCatalog().sessions.first { $0.id == id }
    }

    @discardableResult
    func createSession(at date: Date = Date(), folderID: UUID? = nil) throws -> DocumentSession {
        var catalog = try loadCatalog()
        if let folderID, !catalog.folders.contains(where: { $0.id == folderID }) {
            throw DocumentSessionRepositoryError.folderNotFound
        }
        let session = DocumentSession(createdAt: date, folderID: folderID)
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

    @discardableResult
    func replacePages(
        _ images: [UIImage],
        in sessionID: UUID,
        modifiedAt: Date = Date()
    ) throws -> DocumentSession {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }

        let oldPageIDs = catalog.sessions[index].pageIDs
        let directory = pageDirectory(for: sessionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var newPageIDs: [UUID] = []
        do {
            for image in images {
                guard let data = image.pngData() else {
                    throw DocumentSessionRepositoryError.imageEncodingFailed
                }
                let pageID = UUID()
                try data.write(
                    to: pageURL(sessionID: sessionID, pageID: pageID),
                    options: .atomic
                )
                newPageIDs.append(pageID)
            }

            catalog.sessions[index].pageIDs = newPageIDs
            catalog.sessions[index].modifiedAt = modifiedAt
            try saveCatalog(catalog)
        } catch {
            for pageID in newPageIDs {
                try? fileManager.removeItem(
                    at: pageURL(sessionID: sessionID, pageID: pageID)
                )
            }
            throw error
        }

        for pageID in oldPageIDs {
            try? fileManager.removeItem(
                at: pageURL(sessionID: sessionID, pageID: pageID)
            )
        }
        return catalog.sessions[index]
    }

    func pageRecords(for sessionID: UUID) throws -> [DocumentPage] {
        let catalog = try loadCatalog()
        guard let session = catalog.sessions.first(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }

        return try session.pageIDs.map { pageID in
            let metadata = pageMetadataURL(sessionID: sessionID, pageID: pageID)
            if fileManager.fileExists(atPath: metadata.path) {
                return try decoder.decode(DocumentPage.self, from: Data(contentsOf: metadata))
            }

            let legacy = pageURL(sessionID: sessionID, pageID: pageID)
            guard fileManager.fileExists(atPath: legacy.path) else {
                throw DocumentSessionRepositoryError.pageAssetMissing
            }
            return DocumentPage(
                id: pageID,
                cropQuadrilateral: .fullBounds,
                rotation: .none,
                isLegacySource: true
            )
        }
    }

    func sourceImage(for pageID: UUID, in sessionID: UUID) throws -> UIImage {
        let source = sourceAssetURL(sessionID: sessionID, pageID: pageID)
        if let data = try? Data(contentsOf: source), let image = UIImage(data: data) {
            return image
        }

        let legacy = pageURL(sessionID: sessionID, pageID: pageID)
        guard let data = try? Data(contentsOf: legacy), let image = UIImage(data: data) else {
            throw DocumentSessionRepositoryError.pageAssetMissing
        }
        return image
    }

    func renderedImage(for pageID: UUID, in sessionID: UUID) throws -> UIImage {
        let rendered = renderedAssetURL(sessionID: sessionID, pageID: pageID)
        if let data = try? Data(contentsOf: rendered), let image = UIImage(data: data) {
            return image
        }

        let legacy = pageURL(sessionID: sessionID, pageID: pageID)
        guard let data = try? Data(contentsOf: legacy), let image = UIImage(data: data) else {
            throw DocumentSessionRepositoryError.pageAssetMissing
        }
        return image
    }

    func pageAssets(for sessionID: UUID) throws -> [DocumentPageAssets] {
        try pageRecords(for: sessionID).map { page in
            DocumentPageAssets(
                page: page,
                sourceImage: try sourceImage(for: page.id, in: sessionID),
                renderedImage: try renderedImage(for: page.id, in: sessionID)
            )
        }
    }

    @discardableResult
    func appendPageRecords(
        _ assets: [DocumentPageAssets],
        to sessionID: UUID,
        modifiedAt: Date = Date()
    ) throws -> DocumentSession {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        guard !assets.isEmpty else { return catalog.sessions[index] }

        let existingIDs = Set(catalog.sessions[index].pageIDs)
        guard assets.allSatisfy({ !existingIDs.contains($0.page.id) }) else {
            throw DocumentSessionRepositoryError.imageEncodingFailed
        }

        var writtenIDs: [UUID] = []
        do {
            for asset in assets {
                try writePageAssets(asset, sessionID: sessionID)
                writtenIDs.append(asset.page.id)
            }
            catalog.sessions[index].pageIDs.append(contentsOf: assets.map { $0.page.id })
            catalog.sessions[index].modifiedAt = modifiedAt
            try saveCatalog(catalog)
            return catalog.sessions[index]
        } catch {
            for pageID in writtenIDs {
                try? fileManager.removeItem(at: pageAssetDirectory(sessionID: sessionID, pageID: pageID))
            }
            throw error
        }
    }

    func updatePage(
        _ page: DocumentPage,
        in sessionID: UUID,
        renderedImage: UIImage,
        modifiedAt: Date = Date()
    ) throws {
        var catalog = try loadCatalog()
        guard let sessionIndex = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        guard catalog.sessions[sessionIndex].pageIDs.contains(page.id) else {
            throw DocumentSessionRepositoryError.pageAssetMissing
        }

        let assetDirectory = pageAssetDirectory(sessionID: sessionID, pageID: page.id)
        try fileManager.createDirectory(at: assetDirectory, withIntermediateDirectories: true)

        let source = sourceAssetURL(sessionID: sessionID, pageID: page.id)
        if !fileManager.fileExists(atPath: source.path) {
            let legacySource = try sourceImage(for: page.id, in: sessionID)
            guard let sourceData = legacySource.jpegData(compressionQuality: 0.96) else {
                throw DocumentSessionRepositoryError.imageEncodingFailed
            }
            try sourceData.write(to: source, options: .atomic)
        }

        guard let renderedData = renderedImage.pngData() else {
            throw DocumentSessionRepositoryError.imageEncodingFailed
        }
        try renderedData.write(
            to: renderedAssetURL(sessionID: sessionID, pageID: page.id),
            options: .atomic
        )
        try encoder.encode(page).write(
            to: pageMetadataURL(sessionID: sessionID, pageID: page.id),
            options: .atomic
        )

        catalog.sessions[sessionIndex].modifiedAt = modifiedAt
        try saveCatalog(catalog)

        let legacy = pageURL(sessionID: sessionID, pageID: page.id)
        if fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.removeItem(at: legacy)
        }
    }

    func deletePage(
        id pageID: UUID,
        from sessionID: UUID,
        modifiedAt: Date = Date()
    ) throws {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        guard catalog.sessions[index].pageIDs.contains(pageID) else {
            throw DocumentSessionRepositoryError.pageAssetMissing
        }

        catalog.sessions[index].pageIDs.removeAll { $0 == pageID }
        catalog.sessions[index].modifiedAt = modifiedAt
        try saveCatalog(catalog)

        try? fileManager.removeItem(at: pageAssetDirectory(sessionID: sessionID, pageID: pageID))
        try? fileManager.removeItem(at: pageURL(sessionID: sessionID, pageID: pageID))
    }

    func reorderPages(
        _ orderedPageIDs: [UUID],
        in sessionID: UUID,
        modifiedAt: Date = Date()
    ) throws {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }

        let existing = catalog.sessions[index].pageIDs
        guard orderedPageIDs.count == existing.count,
              Set(orderedPageIDs) == Set(existing) else {
            throw DocumentSessionRepositoryError.pageAssetMissing
        }

        catalog.sessions[index].pageIDs = orderedPageIDs
        catalog.sessions[index].modifiedAt = modifiedAt
        try saveCatalog(catalog)
    }

    func images(for session: DocumentSession) throws -> [UIImage] {
        try session.pageIDs.map { try renderedImage(for: $0, in: session.id) }
    }

    @discardableResult
    func renameSession(
        id sessionID: UUID,
        to name: String,
        modifiedAt: Date = Date()
    ) throws -> DocumentSession {
        var catalog = try loadCatalog()
        guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentSessionRepositoryError.sessionNotFound
        }

        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw DocumentSessionRepositoryError.invalidDocumentName
        }

        catalog.sessions[index].name = normalized
        catalog.sessions[index].modifiedAt = modifiedAt
        try saveCatalog(catalog)
        return catalog.sessions[index]
    }

    @discardableResult
    func createFolder(
        name: String,
        parentFolderID: UUID? = nil,
        sessionIDs: [UUID] = [],
        folderIDs: [UUID] = [],
        at date: Date = Date()
    ) throws -> DocumentFolder {
        var catalog = try loadCatalog()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw DocumentSessionRepositoryError.invalidFolderName
        }
        if let parentFolderID, !catalog.folders.contains(where: { $0.id == parentFolderID }) {
            throw DocumentSessionRepositoryError.folderNotFound
        }

        let folder = DocumentFolder(name: normalizedName, parentFolderID: parentFolderID, createdAt: date)
        catalog.folders.append(folder)
        try moveItems(
            sessionIDs: sessionIDs,
            folderIDs: folderIDs,
            to: folder.id,
            modifiedAt: date,
            catalog: &catalog
        )
        try saveCatalog(catalog)
        return folder
    }

    func move(
        sessionIDs: [UUID] = [],
        folderIDs: [UUID] = [],
        to destinationFolderID: UUID?,
        modifiedAt: Date = Date()
    ) throws {
        var catalog = try loadCatalog()
        try moveItems(
            sessionIDs: sessionIDs,
            folderIDs: folderIDs,
            to: destinationFolderID,
            modifiedAt: modifiedAt,
            catalog: &catalog
        )
        try saveCatalog(catalog)
    }

    func deleteFolder(id: UUID) throws {
        var catalog = try loadCatalog()
        guard catalog.folders.contains(where: { $0.id == id }) else {
            throw DocumentSessionRepositoryError.folderNotFound
        }
        let containsSessions = catalog.sessions.contains { $0.folderID == id }
        let containsFolders = catalog.folders.contains { $0.parentFolderID == id }
        guard !containsSessions && !containsFolders else {
            throw DocumentSessionRepositoryError.folderNotEmpty
        }
        catalog.folders.removeAll { $0.id == id }
        try saveCatalog(catalog)
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

    func deleteItems(
        sessionIDs: [UUID] = [],
        folderIDs: [UUID] = []
    ) throws {
        var catalog = try loadCatalog()
        let requestedSessionIDs = Set(sessionIDs)
        let requestedFolderIDs = Set(folderIDs)

        for sessionID in requestedSessionIDs where !catalog.sessions.contains(where: { $0.id == sessionID }) {
            throw DocumentSessionRepositoryError.sessionNotFound
        }
        for folderID in requestedFolderIDs where !catalog.folders.contains(where: { $0.id == folderID }) {
            throw DocumentSessionRepositoryError.folderNotFound
        }

        var foldersToDelete = requestedFolderIDs
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for folder in catalog.folders {
                guard let parentID = folder.parentFolderID,
                      foldersToDelete.contains(parentID),
                      !foldersToDelete.contains(folder.id) else {
                    continue
                }
                foldersToDelete.insert(folder.id)
                addedDescendant = true
            }
        }

        var sessionsToDelete = requestedSessionIDs
        for session in catalog.sessions {
            if let folderID = session.folderID, foldersToDelete.contains(folderID) {
                sessionsToDelete.insert(session.id)
            }
        }

        let removedSessions = catalog.sessions.filter { sessionsToDelete.contains($0.id) }
        catalog.sessions.removeAll { sessionsToDelete.contains($0.id) }
        catalog.folders.removeAll { foldersToDelete.contains($0.id) }
        try saveCatalog(catalog)

        for session in removedSessions {
            let directory = pageDirectory(for: session.id)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
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

    private func pageAssetDirectory(sessionID: UUID, pageID: UUID) -> URL {
        pageDirectory(for: sessionID)
            .appendingPathComponent(pageID.uuidString, isDirectory: true)
    }

    private func sourceAssetURL(sessionID: UUID, pageID: UUID) -> URL {
        pageAssetDirectory(sessionID: sessionID, pageID: pageID)
            .appendingPathComponent("source.jpg")
    }

    private func renderedAssetURL(sessionID: UUID, pageID: UUID) -> URL {
        pageAssetDirectory(sessionID: sessionID, pageID: pageID)
            .appendingPathComponent("rendered.png")
    }

    private func pageMetadataURL(sessionID: UUID, pageID: UUID) -> URL {
        pageAssetDirectory(sessionID: sessionID, pageID: pageID)
            .appendingPathComponent("metadata.json")
    }

    private func writePageAssets(_ assets: DocumentPageAssets, sessionID: UUID) throws {
        let directory = pageAssetDirectory(sessionID: sessionID, pageID: assets.page.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let sourceData = assets.sourceImage.jpegData(compressionQuality: 0.96),
              let renderedData = assets.renderedImage.pngData() else {
            throw DocumentSessionRepositoryError.imageEncodingFailed
        }

        do {
            try sourceData.write(
                to: sourceAssetURL(sessionID: sessionID, pageID: assets.page.id),
                options: .atomic
            )
            try renderedData.write(
                to: renderedAssetURL(sessionID: sessionID, pageID: assets.page.id),
                options: .atomic
            )
            try encoder.encode(assets.page).write(
                to: pageMetadataURL(sessionID: sessionID, pageID: assets.page.id),
                options: .atomic
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func loadCatalog() throws -> Catalog {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            return Catalog()
        }
        return try decoder.decode(Catalog.self, from: Data(contentsOf: catalogURL))
    }

    private func saveCatalog(_ catalog: Catalog) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
    }

    private func moveItems(
        sessionIDs: [UUID],
        folderIDs: [UUID],
        to destinationFolderID: UUID?,
        modifiedAt: Date,
        catalog: inout Catalog
    ) throws {
        if let destinationFolderID,
           !catalog.folders.contains(where: { $0.id == destinationFolderID }) {
            throw DocumentSessionRepositoryError.folderNotFound
        }

        for sessionID in Set(sessionIDs) {
            guard let index = catalog.sessions.firstIndex(where: { $0.id == sessionID }) else {
                throw DocumentSessionRepositoryError.sessionNotFound
            }
            catalog.sessions[index].folderID = destinationFolderID
            catalog.sessions[index].modifiedAt = modifiedAt
        }

        for folderID in Set(folderIDs) {
            guard let index = catalog.folders.firstIndex(where: { $0.id == folderID }) else {
                throw DocumentSessionRepositoryError.folderNotFound
            }
            if destinationFolderID == folderID
                || isDescendant(destinationFolderID, of: folderID, folders: catalog.folders) {
                throw DocumentSessionRepositoryError.cyclicFolderRelationship
            }
            catalog.folders[index].parentFolderID = destinationFolderID
            catalog.folders[index].modifiedAt = modifiedAt
        }
    }

    private func isDescendant(_ candidateID: UUID?, of ancestorID: UUID, folders: [DocumentFolder]) -> Bool {
        var currentID = candidateID
        var visited: Set<UUID> = []
        while let id = currentID {
            if id == ancestorID { return true }
            guard visited.insert(id).inserted else { return true }
            currentID = folders.first(where: { $0.id == id })?.parentFolderID
        }
        return false
    }
}
