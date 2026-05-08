import Foundation

// MARK: - Storage Mode

/// Determines where the encrypted file is stored.
enum StorageMode: String, Codable, CaseIterable {
    /// Encrypted file is placed in the same directory as the original file
    case originalDirectory = "original"
    /// Encrypted file is placed in ~/Documents/L0ck/
    case appFolder = "appFolder"

    var displayName: String {
        switch self {
        case .originalDirectory: return L10n.string("Original Directory")
        case .appFolder: return L10n.string("App Folder")
        }
    }

    var iconName: String {
        switch self {
        case .originalDirectory: return "folder"
        case .appFolder: return "folder.badge.gearshape"
        }
    }
}

// MARK: - Encrypted File Record

/// Represents a record of an encrypted file managed by L0ck.
///
/// This stores metadata about the encrypted file, not the encryption
/// keys or password. The actual encrypted data lives in the .l0ck file.
struct EncryptedFileRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let originalFileName: String
    let encryptedFilePath: String
    let storageMode: StorageMode
    let createdAt: Date
    let fileSize: Int64

    init(
        id: UUID = UUID(),
        originalFileName: String,
        encryptedFilePath: String,
        storageMode: StorageMode,
        createdAt: Date = Date(),
        fileSize: Int64
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.encryptedFilePath = encryptedFilePath
        self.storageMode = storageMode
        self.createdAt = createdAt
        self.fileSize = fileSize
    }

    /// URL to the encrypted .l0ck file on disk
    var encryptedFileURL: URL {
        URL(fileURLWithPath: encryptedFilePath)
    }

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Human-readable creation date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Check if the encrypted file still exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: encryptedFilePath)
    }

    /// File extension of the original file
    var originalFileExtension: String {
        (originalFileName as NSString).pathExtension.lowercased()
    }
}

// MARK: - File Type Classification

/// Classifies files by type for preview and icon purposes.
enum FileType {
    case text, image, pdf, video, audio, unknown

    var iconName: String {
        switch self {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .pdf: return "doc.richtext.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .unknown: return "doc.fill"
        }
    }

    var displayName: String {
        switch self {
        case .text: return L10n.string("Text")
        case .image: return L10n.string("Image")
        case .pdf: return L10n.string("PDF")
        case .video: return L10n.string("Video")
        case .audio: return L10n.string("Audio")
        case .unknown: return L10n.string("File")
        }
    }

    /// Determine file type from a filename's extension
    static func from(fileName: String) -> FileType {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "swift", "py", "js", "ts", "json", "xml", "html",
             "css", "csv", "log", "sh", "yml", "yaml", "toml", "conf", "cfg",
             "ini", "rtf", "c", "cpp", "h", "java", "rb", "go", "rs", "php":
            return .text
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "svg", "ico":
            return .image
        case "pdf":
            return .pdf
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v":
            return .video
        case "mp3", "wav", "aac", "flac", "ogg", "m4a", "wma", "aiff":
            return .audio
        default:
            return .unknown
        }
    }
}
