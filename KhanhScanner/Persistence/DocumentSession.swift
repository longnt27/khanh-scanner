import Foundation

enum DocumentLifecycle: String, Codable, Equatable {
    case active
    case archived
}

struct DocumentSession: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date
    var pageIDs: [UUID]
    var lifecycle: DocumentLifecycle
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        pageIDs: [UUID] = [],
        lifecycle: DocumentLifecycle = .active,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.pageIDs = pageIDs
        self.lifecycle = lifecycle
        self.folderID = folderID
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modifiedAt, pageIDs, lifecycle, folderID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        pageIDs = try values.decode([UUID].self, forKey: .pageIDs)
        lifecycle = try values.decodeIfPresent(DocumentLifecycle.self, forKey: .lifecycle) ?? .active
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
    }
}
