import Foundation

struct DocumentFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var parentFolderID: UUID?
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        parentFolderID: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentFolderID = parentFolderID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}
