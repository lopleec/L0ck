import SwiftUI

// MARK: - Status Badge

/// Compact system-style badge for file storage mode.
struct StatusBadge: View {
    let mode: StorageMode

    var body: some View {
        Label(mode.displayName, systemImage: mode.iconName)
            .font(.caption)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.quaternary.opacity(0.5))
            )
            .foregroundStyle(.secondary)
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusBadge(mode: .appFolder)
        StatusBadge(mode: .originalDirectory)
    }
    .padding()
}
