import Foundation

enum SyncLogLevel: String, Codable {
    case info
    case warning
    case error
}

struct SyncLogEntry: Codable {
    var timestamp: String
    var level: SyncLogLevel
    var category: String
    var message: String
    var trigger: String?
    var device: DeviceInfo
    var itemID: String?
    var cloudFileId: String?
    var localPath: String?
    var cloudPath: String?
    var metadata: [String: String]
}

final class StructuredLogger {
    private let fm: FileManager
    private let logURL: URL

    init(logsDirectoryURL: URL, fileManager: FileManager = .default) {
        self.fm = fileManager
        self.logURL = logsDirectoryURL.appendingPathComponent("sync.log.jsonl")
        try? fm.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    }

    func log(_ entry: SyncLogEntry) {
        guard let data = try? JSONEncoder.pretty.encode(entry) else { return }
        appendLine(data: data)
    }

    private func appendLine(data: Data) {
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            return
        }
    }
}
