import SwiftUI
import PDFKit
import QuickLookUI

// MARK: - File Detail View

/// Native macOS detail view for an encrypted file.
struct FileDetailView: View {
    @Environment(FileStore.self) private var fileStore
    @AppStorage("previewAutoClearSeconds") private var previewAutoClearSeconds = 10
    let file: EncryptedFileRecord

    @State private var showPasswordForPreview = false
    @State private var showPasswordForExport = false
    @State private var showUniversalExportSheet = false
    @State private var showDeleteConfirm = false
    @State private var previewData: Data?
    @State private var previewFileName: String?
    @State private var systemPreviewURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isWorking = false
    @State private var autoClearTask: Task<Void, Never>?

    private let actionColumns = [
        GridItem(.flexible(minimum: 150, maximum: 220), spacing: 10),
        GridItem(.flexible(minimum: 150, maximum: 220), spacing: 10),
        GridItem(.flexible(minimum: 150, maximum: 220), spacing: 10)
    ]

    private var fileType: FileType {
        FileType.from(fileName: file.originalFileName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                actionsSection
                detailsSection

                if let previewFileName {
                    previewSection(fileName: previewFileName)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .sheet(isPresented: $showPasswordForPreview) {
            PasswordPrompt(
                title: L10n.string("Preview File"),
                message: L10n.string("Enter the file password to preview this file in L0ck."),
                mode: .decrypt
            ) { password in
                await performPreview(password: password)
            }
        }
        .sheet(isPresented: $showPasswordForExport) {
            PasswordPrompt(
                title: L10n.string("Export File"),
                message: L10n.string("Enter the file password before exporting a decrypted copy to disk."),
                mode: .decrypt
            ) { password in
                await performExport(password: password)
            }
        }
        .sheet(isPresented: $showUniversalExportSheet) {
            UniversalExportSheet { currentPassword, exportPassword in
                await performUniversalExport(
                    currentPassword: currentPassword,
                    exportPassword: exportPassword
                )
            }
        }
        .alert(file.fileExists ? "Confirm Deletion" : "Remove Missing Record", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(file.fileExists ? "Delete" : "Remove", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text(
                file.fileExists
                    ? "Permanently delete this encrypted file? Administrator authentication is required."
                    : "Remove this missing file record from L0ck? The encrypted file is already gone from disk."
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? L10n.string("Unknown error"))
        }
        .onChange(of: file.id) {
            clearPreview()
        }
        .onChange(of: previewAutoClearSeconds) {
            scheduleAutoClearIfNeeded()
        }
        .onDisappear {
            clearPreview()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: fileType.iconName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text(file.originalFileName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        StatusBadge(mode: file.storageMode)

                        Text(fileType.displayName)
                            .foregroundStyle(.secondary)

                        Text(file.formattedSize)
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.format("Added %@", file.formattedDate))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !file.fileExists {
                        Label("Encrypted file is missing from disk.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.yellow)
                    }
                }

                Spacer()
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
                Button {
                    showPasswordForPreview = true
                } label: {
                    Label("Preview", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!file.fileExists || isWorking)

                Button {
                    showPasswordForExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!file.fileExists || isWorking)

                Button {
                    showUniversalExportSheet = true
                } label: {
                    Label("Universal .l0ck…", systemImage: "lock.trianglebadge.exclamationmark")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!file.fileExists || isWorking)

                Button {
                    Task { await performReapplyProtection() }
                } label: {
                    Label("Reapply Protection", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!file.fileExists || isWorking)

                Button {
                    NSWorkspace.shared.selectFile(file.encryptedFilePath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!file.fileExists || isWorking)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
            .controlSize(.large)

            if isWorking {
                ProgressView("Working…")
                    .controlSize(.small)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Type", value: fileType.displayName)
                    LabeledContent("Size", value: file.formattedSize)
                    LabeledContent("Added", value: file.formattedDate)
                    LabeledContent("Storage") {
                        StatusBadge(mode: file.storageMode)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(file.encryptedFilePath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.encryptedFilePath, forType: .string)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Encrypted File", systemImage: "doc.badge.lock")
            }
        }
    }

    private func previewSection(fileName: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(systemPreviewURL == nil ? "Decrypted only in memory" : "System preview uses a hidden, locked temporary decrypted copy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(autoClearDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if systemPreviewURL != nil {
                            Text("Temporary preview copies are removed when you clear them or quit L0ck.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Clear Preview") {
                        clearPreview()
                    }
                }

                switch FileType.from(fileName: fileName) {
                case .text:
                    if let previewData {
                        textPreview(data: previewData)
                    }
                case .image:
                    if let previewData {
                        imagePreview(data: previewData)
                    }
                case .pdf:
                    if let previewData {
                        pdfPreview(data: previewData)
                    }
                case .video, .audio, .unknown:
                    if let systemPreviewURL {
                        quickLookPreview(url: systemPreviewURL)
                    } else if let previewData {
                        unsupportedPreview(fileName: fileName, data: previewData)
                    }
                }
            }
        } label: {
            Label("Preview", systemImage: "eye")
        }
    }

    // MARK: - Preview Renderers

    private func textPreview(data: Data) -> some View {
        Group {
            if let text = String(data: data, encoding: .utf8) {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 180, maxHeight: 360)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quinary)
                )
            } else {
                Text("Unable to decode this file as UTF-8 text.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func imagePreview(data: Data) -> some View {
        Group {
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 420)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Unable to decode this image file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pdfPreview(data: Data) -> some View {
        PDFPreviewView(data: data)
            .frame(height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func unsupportedPreview(fileName: String, data: Data) -> some View {
        ContentUnavailableView {
            Label("Preview Unavailable", systemImage: "doc")
        } description: {
            Text(
                L10n.format(
                    "%@ files can't be previewed here. Use Export to save a decrypted copy and open it in another app. Size: %@.",
                    FileType.from(fileName: fileName).displayName,
                    ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                )
            )
        }
    }

    // MARK: - Actions

    private func performPreview(password: String) async -> Bool {
        isWorking = true
        do {
            let result = try FileService.shared.decryptInMemory(record: file, password: password)
            let fileType = FileType.from(fileName: result.fileName)
            let tempPreviewURL = try makeSystemPreviewURLIfNeeded(
                fileName: result.fileName,
                fileType: fileType,
                data: result.fileData
            )

            await MainActor.run {
                clearPreview()
                previewData = tempPreviewURL == nil ? result.fileData : nil
                previewFileName = result.fileName
                systemPreviewURL = tempPreviewURL
                scheduleAutoClearIfNeeded()
                isWorking = false
            }
            return true
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
            return false
        }
    }

    private func makeSystemPreviewURLIfNeeded(
        fileName: String,
        fileType: FileType,
        data: Data
    ) throws -> URL? {
        switch fileType {
        case .text, .image, .pdf:
            return nil
        case .video, .audio, .unknown:
            return try FileService.shared.writeTemporaryPreviewFile(fileName: fileName, data: data)
        }
    }

    @MainActor
    private var autoClearDescription: String {
        let seconds = max(0, previewAutoClearSeconds)

        guard seconds > 0 else {
            return L10n.string("Auto-clear is off. Clear the preview manually or quit L0ck.")
        }

        return L10n.format("Auto-clears after %@ seconds.", String(seconds))
    }

    @MainActor
    private func scheduleAutoClearIfNeeded() {
        autoClearTask?.cancel()
        autoClearTask = nil

        let hasActivePreview = previewData != nil || systemPreviewURL != nil
        let seconds = max(0, previewAutoClearSeconds)

        guard hasActivePreview, seconds > 0 else { return }

        autoClearTask = Task {
            let delay = UInt64(seconds) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                clearPreview()
            }
        }
    }

    @MainActor
    private func clearPreview() {
        autoClearTask?.cancel()
        autoClearTask = nil
        FileService.shared.removeTemporaryPreviewFile(at: systemPreviewURL)
        previewData = nil
        previewFileName = nil
        systemPreviewURL = nil
    }

    private func quickLookPreview(url: URL) -> some View {
        QuickLookPreviewView(url: url)
            .frame(minHeight: 360, maxHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performExport(password: String) async -> Bool {
        isWorking = true

        do {
            _ = try await AdminAuthService.shared.requestAdminAuth(
                prompt: L10n.string("L0ck needs administrator permission to export the decrypted file.")
            )
        } catch {
            await MainActor.run {
                errorMessage = L10n.string("Administrator authentication is required for export.")
                showError = true
                isWorking = false
            }
            return false
        }

        return await MainActor.run {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.originalFileName
            panel.canCreateDirectories = true

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try FileService.shared.decryptAndExport(
                        record: file,
                        password: password,
                        destinationURL: url
                    )
                } catch {
                    errorMessage = L10n.format("Failed to save file: %@", error.localizedDescription)
                    showError = true
                    isWorking = false
                    return false
                }
            }

            isWorking = false
            return true
        }
    }

    private func performUniversalExport(
        currentPassword: String,
        exportPassword: String
    ) async -> Bool {
        isWorking = true

        let exportData: Data
        do {
            exportData = try FileService.shared.makeUniversalEncryptedFileData(
                record: file,
                currentPassword: currentPassword,
                exportPassword: exportPassword
            )
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
            return false
        }

        let destinationURL = await MainActor.run { () -> URL? in
            let panel = NSSavePanel()
            panel.title = L10n.string("Save Universal .l0ck File")
            panel.nameFieldStringValue = "\(file.originalFileName).l0ck"
            panel.canCreateDirectories = true
            return panel.runModal() == .OK ? panel.url : nil
        }

        guard let destinationURL else {
            await MainActor.run {
                isWorking = false
            }
            return true
        }

        do {
            try exportData.write(to: destinationURL, options: .atomic)

            await MainActor.run {
                isWorking = false
            }
            return true
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
            return false
        }
    }

    private func performDelete() async {
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
    }

    private func performReapplyProtection() async {
        isWorking = true

        do {
            try await FileService.shared.reapplyProtection(to: file)
            await MainActor.run {
                isWorking = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
        }
    }
}

// MARK: - PDF Preview

struct PDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.dataRepresentation() != data {
            nsView.document = PDFDocument(data: data)
        }
    }
}

struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)!
        previewView.autostarts = true
        previewView.previewItem = url as NSURL
        return previewView
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let currentPath = (nsView.previewItem as? NSURL)?.path
        if currentPath != url.path {
            nsView.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}

struct UniversalExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSubmit: (String, String) async -> Bool

    @State private var currentPassword = ""
    @State private var exportPassword = ""
    @State private var confirmExportPassword = ""
    @State private var showPassword = false
    @State private var isProcessing = false

    private var passwordsMatch: Bool {
        !exportPassword.isEmpty && exportPassword == confirmExportPassword
    }

    private var isStrongEnough: Bool {
        PasswordPolicy.meetsUniversalExportRequirement(exportPassword)
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && passwordsMatch && isStrongEnough
    }

    private var strengthScore: Int {
        PasswordPolicy.strengthScore(for: exportPassword)
    }

    private var strengthColor: Color {
        switch strengthScore {
        case 0...1: return .red
        case 2...3: return .orange
        case 4: return .yellow
        default: return .green
        }
    }

    private var strengthText: String {
        switch strengthScore {
        case 0...1: return L10n.string("Weak")
        case 2...3: return L10n.string("Medium")
        case 4: return L10n.string("Strong")
        default: return L10n.string("Very Strong")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Universal Export")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Create a shareable .l0ck file protected only by a new export password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            Form {
                Section {
                    Label("Not Recommended", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("Universal .l0ck files can move between Macs, but they no longer use this Mac's device keys.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Current File Password") {
                    passwordField("Password", text: $currentPassword)
                }

                Section("Universal Export Password") {
                    passwordField("Password", text: $exportPassword)
                    passwordField("Confirm Password", text: $confirmExportPassword)
                    Toggle("Show password", isOn: $showPassword)

                    if !exportPassword.isEmpty {
                        LabeledContent("Strength") {
                            HStack(spacing: 8) {
                                strengthBar
                                Text(strengthText)
                                    .foregroundStyle(strengthColor)
                            }
                        }
                    }

                    Text("Use at least 12 characters with uppercase, lowercase, a number, and a symbol.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !exportPassword.isEmpty && !isStrongEnough {
                        Label("Password must include uppercase, lowercase, a number, and a symbol.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if !exportPassword.isEmpty && !confirmExportPassword.isEmpty && !passwordsMatch {
                        Label("Passwords do not match", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        isProcessing = true
                        let shouldDismiss = await onSubmit(currentPassword, exportPassword)
                        isProcessing = false
                        if shouldDismiss {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text("Export Universal .l0ck")
                            .frame(minWidth: 160)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
    }

    private var strengthBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < strengthScore ? strengthColor : Color.secondary.opacity(0.25))
                    .frame(width: 20, height: 5)
            }
        }
    }

    private func passwordField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        Group {
            if showPassword {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
    }
}
