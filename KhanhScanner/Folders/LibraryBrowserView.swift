import SwiftUI

enum LibraryRoute: Hashable {
    case folder(UUID)
    case session(UUID)
}

enum LibraryItemID: Hashable {
    case folder(UUID)
    case session(UUID)
}

struct LibrarySelectionState {
    var selection: Set<LibraryItemID> = []
    var isEditing = false

    mutating func beginSelecting(_ item: LibraryItemID) {
        isEditing = true
        selection.insert(item)
    }

    mutating func finish() {
        selection.removeAll()
        isEditing = false
    }
}

struct LibraryBrowserView: View {
    @ObservedObject var library: DocumentLibrary
    let currentFolderID: UUID?
    let canScan: Bool
    let onNewDocument: (UUID?) -> Void

    @State private var selectionState = LibrarySelectionState()
    @State private var newFolderName = ""
    @State private var showingNewFolder = false
    @State private var showingMovePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameDocument = false
    @State private var renamingSessionID: UUID?
    @State private var renameDocumentText = ""
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
        List(selection: $selectionState.selection) {
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
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in
                                    selectionState.beginSelecting(.folder(folder.id))
                                }
                        )
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
                                Text(session.name)
                                    .font(.headline)
                                Text("\(session.pageIDs.count) page\(session.pageIDs.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(LibraryItemID.session(session.id))
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in
                                    selectionState.beginSelecting(.session(session.id))
                                }
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                beginRenaming(session)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, editModeBinding)
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !childFolders.isEmpty || !childSessions.isEmpty {
                    Button(selectionState.isEditing ? "Done" : "Select") {
                        if selectionState.isEditing {
                            selectionState.finish()
                        } else {
                            selectionState.isEditing = true
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
            if selectionState.isEditing && !selectionState.selection.isEmpty {
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
                    Spacer()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
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
            Text(selectionState.selection.isEmpty ? "Create it here." : "Move the selected items into it.")
        }
        .alert("Rename Document", isPresented: $showingRenameDocument) {
            TextField("Document name", text: $renameDocumentText)
            Button("Save", action: renameDocument)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingMovePicker) {
            FolderDestinationPicker(
                folders: library.folders,
                movingFolderIDs: selectedFolderIDs
            ) { destinationID in
                moveSelection(to: destinationID)
            }
        }
        .confirmationDialog(
            bulkDeleteTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(bulkDeleteButtonTitle, role: .destructive, action: deleteSelection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bulkDeleteMessage)
        }
        .alert("Khanh Scanner", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var selectedSessionIDs: [UUID] {
        selectionState.selection.compactMap { item in
            if case let .session(id) = item { return id }
            return nil
        }
    }

    private var selectedFolderIDs: [UUID] {
        selectionState.selection.compactMap { item in
            if case let .folder(id) = item { return id }
            return nil
        }
    }

    private var bulkDeleteTitle: String {
        "Delete \(selectionState.selection.count) selected item\(selectionState.selection.count == 1 ? "" : "s")?"
    }

    private var bulkDeleteButtonTitle: String {
        selectionState.selection.count == 1 ? "Delete Item" : "Delete Items"
    }

    private var bulkDeleteMessage: String {
        if selectedFolderIDs.isEmpty {
            return "The selected documents and their scanned pages will be permanently deleted."
        }
        return "Selected folders, their subfolders, and all documents inside them will be permanently deleted."
    }

    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { selectionState.isEditing ? .active : .inactive },
            set: { newValue in
                if newValue.isEditing {
                    selectionState.isEditing = true
                } else {
                    selectionState.finish()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func beginRenaming(_ session: DocumentSession) {
        renamingSessionID = session.id
        renameDocumentText = session.name
        showingRenameDocument = true
    }

    private func renameDocument() {
        guard let renamingSessionID else { return }
        do {
            try library.renameSession(id: renamingSessionID, to: renameDocumentText)
            self.renamingSessionID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func deleteSelection() {
        do {
            try library.deleteItems(
                sessionIDs: selectedSessionIDs,
                folderIDs: selectedFolderIDs
            )
            finishSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishSelection() {
        selectionState.finish()
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
