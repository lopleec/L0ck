import SwiftUI

// MARK: - File Row

/// Native source-list row for an encrypted file.
struct FileRow: View {
    let file: EncryptedFileRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: FileType.from(fileName: file.originalFileName).iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.originalFileName)
                    .lineLimit(1)

                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !file.fileExists {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Encrypted file not found at its recorded location")
            }
        }
        .padding(.vertical, 2)
    }

    private var secondaryText: String {
        "\(file.formattedSize) • \(file.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
