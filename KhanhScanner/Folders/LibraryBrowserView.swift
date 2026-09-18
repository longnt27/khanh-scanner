import SwiftUI

enum LibraryRoute: Hashable {
    case folder(UUID)
    case session(UUID)
}

enum LibraryItemID: Hashable {
    case folder(UUID)
    case session(UUID)
}

struct LibraryBrowserView: View {
    @ObservedObject var library: DocumentLibrary
    let currentFolderID: UUID?
    let canScan: Bool
    let onNewDocument: (UUID?) -> Void

    @State private var selection: Set<LibraryItemID> = []
    @State private var editMode: EditMode = .inactive
    @State private var newFolderName = ""
    @State private var showingNewFolder = false
    @State private var showingMovePicker = false
    @State private var errorMessage: String?

    private var childFolders: [DocumentFolder] {
        library.folders.filter { $0.parentFolderID == currentFolderID }
    }

    private var childSessions: [DocumentSession] {
        library.sessions.filter { $0.folderID == currentFolderID }
    }

    private var title: String {
        guard let currentFolderID else { return "Khanh Scanner" }
        return library.folders.first(where: { $0.id == currentFolderID })?.name ?? "Folder"
    }

    var body: some View {
        List(selection: $selection) {
            if childFolders.isEmpty && childSessions.isEmpty {
                ContentUnavailableView(
                    currentFolderID == nil ? "No Documents" : "Empty Folder",
                    systemImage: "folder",
                    description: Text("Create a folder or start a new document scan.")
                )
                .listRowBackground(Color.clear)
            }

            if !childFolders.isEmpty {
                Section("Folders") {
                    ForEach(childFolders) { folder in
                        NavigationLink(value: LibraryRoute.folder(folder.id)) {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .tag(LibraryItemID.folder(folder.id))
                        .swipeActions {
                            Button(role: .destructive) { deleteFolder(folder.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !childSessions.isEmpty {
                Section("Documents") {
                    ForEach(childSessions) { session in
                        NavigationLink(value: LibraryRoute.session(session.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text(
                                    "\(session.pageIDs.count) page\(session.pageIDs.count == 1 ? "" : "s") · "
                                    + (session.lifecycle == .active ? "In Progress" : "Finished")
                                )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(LibraryItemID.session(session.id))
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !childFolders.isEmpty || !childSessions.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        if editMode.isEditing {
                            editMode = .inactive
                            selection.removeAll()
                        } else {
                            editMode = .active
                        }
                    }
                }

                Menu {
                    Button { onNewDocument(currentFolderID) } label: {
                        Label("New Document Scan", systemImage: "camera.viewfinder")
                    }
                    .disabled(!canScan)
                    Button {
                        newFolderName = ""
                        showingNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing && !selection.isEmpty {
                HStack {
                    Button {
                        newFolderName = ""
                        showingNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Spacer()
                    Button { showingMovePicker = true } label: {
                        Label("Move", systemImage: "folder")
                    }
                }
                .padding()
                .background(.bar)
            } else if childFolders.isEmpty && childSessions.isEmpty {
                Button { onNewDocument(currentFolderID) } label: {
                    Label("New Document Scan", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(!canScan)
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create", action: createFolder)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selection.isEmpty ? "Create it here." : "Move the selected items into it.")
        }
        .sheet(isPresented: $showingMovePicker) {
            FolderDestinationPicker(
                folders: library.folders,
                movingFolderIDs: selectedFolderIDs
            ) { destinationID in
                moveSelection(to: destinationID)
            }
        }
        .alert("Khanh Scanner", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var selectedSessionIDs: [UUID] {
        selection.compactMap { item in
            if case let .session(id) = item { return id }
            return nil
        }
    }

    private var selectedFolderIDs: [UUID] {
        selection.compactMap { item in
            if case let .folder(id) = item { return id }
            return nil
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func createFolder() {
        do {
            try library.createFolder(
                name: newFolderName,
                parentFolderID: currentFolderID,
                sessionIDs: selectedSessionIDs,
                folderIDs: selectedFolderIDs
            )
            finishSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveSelection(to destinationID: UUID?) {
        do {
            try library.move(
                sessionIDs: selectedSessionIDs,
                folderIDs: selectedFolderIDs,
                to: destinationID
            )
            finishSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFolder(_ id: UUID) {
        do {
            try library.deleteFolder(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishSelection() {
        selection.removeAll()
        editMode = .inactive
    }
}

private struct FolderDestinationPicker: View {
    private struct Row: Identifiable {
        let folder: DocumentFolder
        let depth: Int
        var id: UUID { folder.id }
    }

    @Environment(\.dismiss) private var dismiss
    let folders: [DocumentFolder]
    let movingFolderIDs: [UUID]
    let onSelect: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    Label("Home", systemImage: "house")
                }

                ForEach(rows) { row in
                    Button {
                        select(row.folder.id)
                    } label: {
                        HStack {
                            Color.clear.frame(width: CGFloat(row.depth) * 18, height: 1)
                            Label(row.folder.name, systemImage: "folder")
                        }
                    }
                    .disabled(isInvalidDestination(row.folder.id))
                }
            }
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var rows: [Row] {
        flatten(parentID: nil, depth: 0, visited: [])
    }

    private func flatten(parentID: UUID?, depth: Int, visited: Set<UUID>) -> [Row] {
        folders
            .filter { $0.parentFolderID == parentID && !visited.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .flatMap { folder in
                let nextVisited = visited.union([folder.id])
                return [Row(folder: folder, depth: depth)]
                    + flatten(parentID: folder.id, depth: depth + 1, visited: nextVisited)
            }
    }

    private func isInvalidDestination(_ destinationID: UUID) -> Bool {
        movingFolderIDs.contains { movingID in
            destinationID == movingID || isDescendant(destinationID, of: movingID)
        }
    }

    private func isDescendant(_ candidateID: UUID, of ancestorID: UUID) -> Bool {
        var currentID: UUID? = candidateID
        var visited: Set<UUID> = []
        while let id = currentID {
            if id == ancestorID { return true }
            guard visited.insert(id).inserted else { return true }
            currentID = folders.first(where: { $0.id == id })?.parentFolderID
        }
        return false
    }

    private func select(_ destinationID: UUID?) {
        onSelect(destinationID)
        dismiss()
    }
}
