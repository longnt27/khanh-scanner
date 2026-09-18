import Foundation

struct DocumentSession: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date
    var pageIDs: [UUID]
    var folderID: UUID?
    var name: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        pageIDs: [UUID] = [],
        folderID: UUID? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.pageIDs = pageIDs
        self.folderID = folderID
        self.name = name ?? Self.defaultName(for: createdAt)
    }

    static func defaultName(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modifiedAt, pageIDs, folderID, name
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        pageIDs = try values.decode([UUID].self, forKey: .pageIDs)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? Self.defaultName(for: createdAt)
    }
}
