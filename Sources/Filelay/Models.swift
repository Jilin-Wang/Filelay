import Foundation

struct DeviceInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
}

enum SyncItemStatus: String, Codable, CaseIterable {
    case synced
    case uploading
    case downloading
    case conflict
    case pending
    case error
    case disabled

    var title: String {
        switch self {
        case .synced:
            return "已同步"
        case .uploading:
            return "上传中"
        case .downloading:
            return "下载中"
        case .conflict:
            return "冲突"
        case .pending:
            return "等待同步"
        case .error:
            return "错误"
        case .disabled:
            return "已停用"
        }
    }
}

enum SyncEventAction: String, Codable, CaseIterable {
    case added
    case linked
    case upload
    case download
    case deleted
    case conflictDetected
    case conflictResolved
    case error

    var title: String {
        switch self {
        case .added:
            return "添加文件"
        case .linked:
            return "建立关联"
        case .upload:
            return "上传到云端"
        case .download:
            return "从云端应用"
        case .deleted:
            return "删除云端文件"
        case .conflictDetected:
            return "检测到冲突"
        case .conflictResolved:
            return "冲突已解决"
        case .error:
            return "同步错误"
        }
    }
}

struct CloudVersion: Codable, Hashable {
    var versionId: String
    var contentHash: String
    var updatedAt: String
    var updatedByDevice: DeviceInfo
    var sourceFileMtime: String
}

struct DeviceReceipt: Codable, Hashable {
    var device: DeviceInfo
    var lastAppliedVersionId: String
    var lastAppliedAt: String
    var localFileMtimeAfterApply: String
    var lastSyncStatus: SyncItemStatus
}

struct SyncEvent: Codable, Hashable, Identifiable {
    var id: String
    var timestamp: String
    var device: DeviceInfo
    var action: SyncEventAction
    var versionId: String?
    var note: String?
}

struct ConflictState: Codable, Hashable {
    var localHash: String
    var cloudHash: String
    var detectedAt: String
    var localPreview: String
    var cloudPreview: String
    var cloudVersionId: String?
}

struct SyncItem: Codable, Hashable, Identifiable {
    var id: String
    var localPath: String
    var cloudFilePath: String
    var cloudFileId: String
    var isEnabled: Bool
    var status: SyncItemStatus
    var lastKnownLocalHash: String?
    var lastSeenCloudVersionId: String?
    var conflictState: ConflictState?
    var cloudVersion: CloudVersion?
    var deviceReceipts: [String: DeviceReceipt]
    var history: [SyncEvent]
    var lastErrorMessage: String?
    var createdAt: String

    var displayName: String {
        let fileName = URL(fileURLWithPath: localPath).lastPathComponent
        if !fileName.isEmpty {
            return fileName
        }
        return URL(fileURLWithPath: cloudFilePath).lastPathComponent
    }
}

struct CloudFileMetadata: Codable, Hashable {
    var cloudFileId: String
    var cloudFilePath: String
    var cloudVersion: CloudVersion?
    var deviceReceipts: [String: DeviceReceipt]
    var eventLog: [SyncEvent]
    var deletedAt: String?
    var deletedByDevice: DeviceInfo?
}

struct CloudFileRecord: Hashable, Identifiable {
    var id: String { cloudFileId }
    var cloudFileId: String
    var cloudFilePath: String
    var displayName: String
    var localPath: String?
    var linkedItemID: String?
    var isLocallyLinked: Bool
    var status: SyncItemStatus?
    var cloudVersion: CloudVersion?
    var deviceReceipts: [String: DeviceReceipt]
    var history: [SyncEvent]
    var conflictState: ConflictState?
}

struct AppSettings: Codable, Hashable {
    var managedRootPath: String
    var syncIntervalSeconds: Int
    var launchAtLoginEnabled: Bool
    var associationHintsEnabled: Bool
    var language: AppLanguage

    static func `default`(managedRootPath: String) -> AppSettings {
        AppSettings(
            managedRootPath: managedRootPath,
            syncIntervalSeconds: 30,
            launchAtLoginEnabled: false,
            associationHintsEnabled: true,
            language: .zhHans
        )
    }
}

enum ConflictResolutionChoice {
    case keepLocal
    case useCloud
    case backupLocalThenUseCloud
}

enum AppSection: String, CaseIterable, Identifiable {
    case files
    case conflicts
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            return "同步文件"
        case .conflicts:
            return "冲突处理"
        case .history:
            return "同步历史"
        case .settings:
            return "设置"
        }
    }
}

struct DiscoveryCandidate: Identifiable, Hashable {
    enum Confidence: String, Hashable {
        case exactHash
        case uniqueName
        case discovered
    }

    var id: String { cloudFileId }
    var cloudFileId: String
    var cloudFilePath: String
    var fileName: String
    var confidence: Confidence
    var reason: String
    var cloudVersion: CloudVersion?
}

enum SyncStatus {
    case idle
    case syncing
    case warning(String)
    case error(String)

    var menuTitle: String {
        switch self {
        case .idle:
            return "状态：空闲"
        case .syncing:
            return "状态：同步中"
        case .warning(let message):
            return "状态：注意 - \(message)"
        case .error(let message):
            return "状态：错误 - \(message)"
        }
    }
}

struct AppSnapshot {
    var items: [SyncItem]
    var cloudFiles: [CloudFileRecord]
    var settings: AppSettings
    var aggregateStatus: SyncStatus
    var currentDevice: DeviceInfo
    var knownDevices: [DeviceInfo]
}

enum AddFileMode: String, CaseIterable, Identifiable {
    case upload
    case linkExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload:
            return "上传新文件"
        case .linkExisting:
            return "关联已有云端文件"
        }
    }
}

struct AddFileDraft {
    var mode: AddFileMode = .upload
    var localPath: String = ""
    var uploadRelativeFolder: String = ""
    var suggestions: [DiscoveryCandidate] = []
    var availableTargets: [DiscoveryCandidate] = []
    var selectedTargetID: String?
    var ignoredSuggestionIDs: Set<String> = []
}

struct AlertMessage: Identifiable {
    var id = UUID().uuidString
    var title: String
    var message: String
}

extension ISO8601DateFormatter {
    static let filelay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension Date {
    var filelayString: String {
        ISO8601DateFormatter.filelay.string(from: self)
    }
}
