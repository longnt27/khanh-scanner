import Foundation

struct DocumentSession: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date
    var pageIDs: [UUID]
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        pageIDs: [UUID] = [],
        folderID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.pageIDs = pageIDs
        self.folderID = folderID
    }
}
