// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import UniformTypeIdentifiers

@MainActor enum PDFAttachmentExport {
    /// Always asks for a destination; an embedded filename never selects a path.
    static func save(_ data: Data,name: String,openAfterSaving: Bool,russian: Bool,completion: @escaping @MainActor (String?) -> Void) {
        let panel = NSSavePanel()
        let name = safeFilename(name)
        panel.nameFieldStringValue = name
        if let type = UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension),type != .directory { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        panel.prompt = russian ? (openAfterSaving ? "Сохранить и открыть" : "Сохранить") : (openAfterSaving ? "Save and Open" : "Save")
        panel.begin { response in
            guard response == .OK,let url = panel.url else { return }
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let worker = Task.detached(priority: .userInitiated) { try data.write(to: url,options: .atomic) }
                    try await worker.value
                    if openAfterSaving && !NSWorkspace.shared.open(url) {
                        completion(russian ? "Вложение сохранено, но macOS не смогла открыть его. Выберите приложение через Finder." : "The attachment was saved, but macOS could not open it. Choose an application in Finder.")
                    } else { completion(nil) }
                } catch { completion(russian ? "Не удалось сохранить вложение: \(error.localizedDescription)" : "Could not save attachment: \(error.localizedDescription)") }
            }
        }
    }
    static func safeFilename(_ original: String) -> String {
        let tail = original.replacingOccurrences(of: "\\",with: "/").split(separator: "/",omittingEmptySubsequences: true).last.map(String.init) ?? "Attachment.bin"
        let stripped = String(String.UnicodeScalarView(tail.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }))
        let name = String(stripped.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." ? "Attachment.bin" : name
    }
}
