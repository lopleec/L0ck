import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

/// The primary view of L0ck, using a native sidebar-detail layout.
struct MainView: View {
    private enum DeletionTarget {
        case record(EncryptedFileRecord)
        case externalFile(URL)
    }

    @Environment(FileStore.self) private var fileStore
    let onShowOnboarding: () -> Void

    @State private var showImportSheet = false
    @State private var showKeyBackup = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var pendingDeletion: DeletionTarget?
    @State private var errorMessage: String?
    @State private var showError = false

    init(onShowOnboarding: @escaping () -> Void = {}) {
        self.onShowOnboarding = onShowOnboarding
    }

    var body: some View {
        @Bindable var store = fileStore

        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                sidebarSearchField(text: $store.searchText)

                List(selection: $store.selectedFileID) {
                    if !fileStore.appFolderFiles.isEmpty {
                        Section("App Folder") {
                            ForEach(fileStore.appFolderFiles) { file in
                                FileRow(file: file)
                                    .tag(file.id)
                                    .contextMenu {
                                        sidebarDeleteButton(for: file)
                                    }
                            }
                        }
                    }

                    if !fileStore.originalDirFiles.isEmpty {
                        Section("Original Directory") {
                            ForEach(fileStore.originalDirFiles) { file in
                                FileRow(file: file)
                                    .tag(file.id)
                                    .contextMenu {
                                        sidebarDeleteButton(for: file)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand {
                    if let selectedFile = fileStore.selectedFile {
                        pendingDeletion = .record(selectedFile)
                    }
                }
                .overlay {
                    if fileStore.filteredFiles.isEmpty {
                        sidebarEmptyState
                    }
                }
            }
            .navigationTitle("L0ck")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            Group {
                if let selectedFile = fileStore.selectedFile {
                    FileDetailView(file: selectedFile)
                } else {
                    detailPlaceholder
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showImportSheet) {
            ImportSheet()
        }
        .sheet(isPresented: $showKeyBackup) {
            KeyBackupView()
        }
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button(deletionActionTitle, role: .destructive) {
                guard let target = pendingDeletion else { return }
                Task { await performDeletion(for: target) }
            }
        } message: {
            Text(deletionMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showImportSheet = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .keyboardShortcut("i", modifiers: .command)

                Menu {
                    Button("Key Backup…", systemImage: "key.horizontal") {
                        showKeyBackup = true
                    }

                    Button("Delete .l0ck File…", systemImage: "trash") {
                        chooseL0ckFileForDeletion()
                    }

                    Divider()

                    Button("Show Onboarding…", systemImage: "sparkles") {
                        onShowOnboarding()
                    }

                    Divider()

                    SettingsLink {
                        Label("Settings…", systemImage: "gearshape")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .frame(minWidth: 920, minHeight: 600)
    }

    private func sidebarSearchField(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search files", text: text)
                .textFieldStyle(.plain)

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quinary)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Empty States

    private var deletionTitle: String {
        switch pendingDeletion {
        case .record(let file):
            return file.fileExists ? "Confirm Deletion" : "Remove Missing Record"
        case .externalFile:
            return "Delete .l0ck File"
        case nil:
            return ""
        }
    }

    private var deletionActionTitle: String {
        switch pendingDeletion {
        case .record(let file):
            return file.fileExists ? "Delete" : "Remove"
        case .externalFile:
            return "Delete"
        case nil:
            return "Delete"
        }
    }

    private var deletionMessage: String {
        guard let pendingDeletion else {
            return ""
        }

        switch pendingDeletion {
        case .record(let file):
            if file.fileExists {
                return L10n.string("Permanently delete this encrypted file? Administrator authentication is required.")
            }

            return L10n.string("Remove this missing file record from L0ck? The encrypted file is already gone from disk.")
        case .externalFile(let url):
            return L10n.format(
                "Permanently delete this .l0ck file from disk?\n%@",
                url.path
            )
        }
    }

    @ViewBuilder
    private func sidebarDeleteButton(for file: EncryptedFileRecord) -> some View {
        Button(file.fileExists ? "Delete…" : "Remove from List", role: .destructive) {
            pendingDeletion = .record(file)
        }
    }

    private func chooseL0ckFileForDeletion() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L10n.string("Select a .l0ck file to delete")

        if let l0ckType = UTType(filenameExtension: "l0ck") {
            panel.allowedContentTypes = [l0ckType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            if let record = fileStore.record(forEncryptedFilePath: url.path) {
                pendingDeletion = .record(record)
            } else {
                pendingDeletion = .externalFile(url)
            }
        }
    }

    private func performDeletion(for target: DeletionTarget) async {
        defer {
            pendingDeletion = nil
        }

        switch target {
        case .record(let file):
            if !file.fileExists {
                await MainActor.run {
                    fileStore.removeRecord(file)
                }
                return
            }

            do {
                try await FileService.shared.deleteEncryptedFile(file)
                await MainActor.run {
                    fileStore.removeRecord(file)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }

        case .externalFile(let url):
            do {
                try await FileService.shared.deleteL0ckFile(at: url)
                if let record = fileStore.record(forEncryptedFilePath: url.path) {
                    await MainActor.run {
                        fileStore.removeRecord(record)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private var sidebarEmptyState: some View {
        ContentUnavailableView {
            Label(
                fileStore.searchText.isEmpty ? "No Encrypted Files" : "No Results",
                systemImage: fileStore.searchText.isEmpty ? "lock.doc" : "magnifyingglass"
            )
        } description: {
            Text(
                fileStore.searchText.isEmpty
                    ? "Import a file to create your first encrypted record."
                    : "Try a different filename or clear the search filter."
            )
        } actions: {
            if fileStore.searchText.isEmpty {
                Button("Import File") {
                    showImportSheet = true
                }
            }
        }
    }

    private var detailPlaceholder: some View {
        ContentUnavailableView {
            Label("Select a File", systemImage: "lock.doc")
        } description: {
            Text("Choose an encrypted file from the sidebar or import a new one.")
        } actions: {
            Button("Import File") {
                showImportSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
