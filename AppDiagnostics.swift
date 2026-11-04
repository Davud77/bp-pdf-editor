// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Darwin

/// Local diagnostics only. The lock protects the file, rotation and stderr
/// reader; no UI or PDF objects are touched by the background pipe callback.
final class AppDiagnostics: @unchecked Sendable {
    static let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/BotPlus PDF Editor", isDirectory: true)
    static let shared: AppDiagnostics? = try? AppDiagnostics(directory: directory)

    let directory: URL
    private let lock = NSLock()
    private let maximumBytes: Int
    private let retainedFiles: Int
    private let session = UUID().uuidString
    private var sequence = 0
    private var size = 0
    private var file: FileHandle?
    private var pipe: Pipe?
    private var marker: URL?
    private var originalStderr: Int32 = -1

    init(directory: URL, maximumBytes: Int = 2 * 1024 * 1024, retainedFiles: Int = 8) throws {
        self.directory = directory
        self.maximumBytes = max(128, maximumBytes)
        self.retainedFiles = max(1, retainedFiles)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try rotate()
    }

    private func rotate() throws {
        try file?.close(); file = nil
        let name = "session-\(session)-\(String(format: "%05d", sequence)).log"
        sequence += 1
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                              attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url); size = 0
        let candidates = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent.hasPrefix("session-") && $0.pathExtension == "log" && $0 != url }
            .sorted { lhs, rhs in
                let a = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            }
        for old in candidates.prefix(max(0, candidates.count - retainedFiles + 1)) {
            try FileManager.default.removeItem(at: old)
        }
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        do {
            var cursor = data.startIndex
            while cursor < data.endIndex {
                if size >= maximumBytes { try rotate() }
                let end = min(data.endIndex, cursor + maximumBytes - size)
                try file?.write(contentsOf: data[cursor..<end])
                size += end - cursor; cursor = end
            }
        } catch {
            // Avoid writing into our stderr pipe here, which would recurse on
            // disk-full/permission failures. Diagnostics never abort the app.
        }
    }

    func record(_ event: String) {
        let text = String(event.prefix(2048)).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let date = ISO8601DateFormatter().string(from: Date())
        append(Data("\(date) [app] \(text)\n".utf8))
    }

    static func record(_ event: String) { shared?.record(event) }
    static func error(_ operation: String, _ error: Error) {
        let value = error as NSError
        // Avoid localized descriptions: they can contain PDF text, passwords
        // or full user paths. Runtime stderr is retained verbatim locally.
        record("error operation=\(operation) domain=\(value.domain) code=\(value.code)")
    }

    func startSession() {
        lock.lock()
        if marker != nil { lock.unlock(); return }
        lock.unlock()
        let fm = FileManager.default
        let previous = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in previous where url.lastPathComponent.hasPrefix(".active-") {
            guard let pid = Int32(url.lastPathComponent.dropFirst(8)), pid != getpid(),
                  kill(pid, 0) == -1, errno == ESRCH else { continue }
            record("previous_session_ended_without_clean_shutdown pid=\(pid)")
            try? fm.removeItem(at: url)
        }
        let url = directory.appendingPathComponent(".active-\(getpid())")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        record("session_start id=\(session) version=\(version) build=\(build) os=\(ProcessInfo.processInfo.operatingSystemVersionString) arch=\(Self.architecture)")
        if fm.createFile(atPath: url.path, contents: Data(session.utf8), attributes: [.posixPermissions: 0o600]) {
            lock.lock(); marker = url; lock.unlock()
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "other"
        #endif
    }

    func finishSession() {
        record("session_end clean=true")
        lock.lock(); defer { lock.unlock() }
        if let marker { try? FileManager.default.removeItem(at: marker) }
        marker = nil
        try? file?.synchronize()
    }

    func captureStandardError() {
        lock.lock(); defer { lock.unlock() }
        guard pipe == nil else { return }
        let stream = Pipe(), original = dup(STDERR_FILENO)
        guard original >= 0 else { return }
        stream.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { self?.append(data) }
        }
        guard dup2(stream.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            stream.fileHandleForReading.readabilityHandler = nil; close(original); return
        }
        originalStderr = original; pipe = stream
        try? stream.fileHandleForWriting.close()
    }

    func stopCapturingStandardError() {
        lock.lock(); defer { lock.unlock() }
        guard originalStderr >= 0 else { return }
        _ = dup2(originalStderr, STDERR_FILENO); close(originalStderr); originalStderr = -1
        // Leave the reader alive until EOF drains the pipe. No signal handler,
        // executor hop or asynchronous work is attempted while crashing.
    }

    deinit {
        stopCapturingStandardError()
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? file?.close()
    }
}
