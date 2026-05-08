import Foundation
import Observation

// MARK: - File Store

/// Observable store managing all encrypted file records.
///
/// Persists records as JSON in `~/Library/Application Support/L0ck/file_records.json`.
/// This only stores metadata (file paths, names, dates) — not encryption keys or passwords.
@Observable
class FileStore {

    /// All encrypted file records
    var files: [EncryptedFileRecord] = []

    /// Currently selected file ID
    var selectedFileID: UUID?

    /// Search filter text
    var searchText: String = ""

    /// Storage URL for persisted records
    private let storageURL: URL

    // MARK: - Computed Properties

    /// Files filtered by search text
    var filteredFiles: [EncryptedFileRecord] {
        if searchText.isEmpty {
            return files
        }
        return files.filter {
            $0.originalFileName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The currently selected file record
    var selectedFile: EncryptedFileRecord? {
        files.first { $0.id == selectedFileID }
    }

    /// Files stored in the App folder
    var appFolderFiles: [EncryptedFileRecord] {
        filteredFiles.filter { $0.storageMode == .appFolder }
    }

    /// Files stored in their original directories
    var originalDirFiles: [EncryptedFileRecord] {
        filteredFiles.filter { $0.storageMode == .originalDirectory }
    }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let l0ckDir = appSupport.appendingPathComponent("L0ck", isDirectory: true)
        try? FileManager.default.createDirectory(at: l0ckDir, withIntermediateDirectories: true)
        self.storageURL = l0ckDir.appendingPathComponent("file_records.json")
        loadRecords()
    }

    // MARK: - CRUD Operations

    /// Add a new encrypted file record.
    func addRecord(_ record: EncryptedFileRecord) {
        files.append(record)
        saveRecords()
    }

    /// Remove a specific file record.
    func removeRecord(_ record: EncryptedFileRecord) {
        files.removeAll { $0.id == record.id }
        if selectedFileID == record.id {
            selectedFileID = nil
        }
        saveRecords()
    }

    /// Remove records at the given index set.
    func removeRecords(at offsets: IndexSet) {
        let removedIDs = offsets.map { files[$0].id }
        files.remove(atOffsets: offsets)
        if let selected = selectedFileID, removedIDs.contains(selected) {
            selectedFileID = nil
        }
        saveRecords()
    }

    /// Look up a record by its encrypted file path.
    func record(forEncryptedFilePath path: String) -> EncryptedFileRecord? {
        let targetPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return files.first {
            URL(fileURLWithPath: $0.encryptedFilePath).standardizedFileURL.path == targetPath
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            files = try JSONDecoder().decode([EncryptedFileRecord].self, from: data)
        } catch {
            print("[L0ck] Failed to load file records: \(error)")
        }
    }

    private func saveRecords() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(files)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[L0ck] Failed to save file records: \(error)")
        }
    }
}
