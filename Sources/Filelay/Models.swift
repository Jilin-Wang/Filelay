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

enum FilelayLayout {
    static let cloudFilesDirectoryName = "CloudFiles"
    static let metadataDirectoryName = ".filelay"
    static let legacyMetadataDirectoryName = ".autoicloud"

    static func cloudFilesRootURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(cloudFilesDirectoryName, isDirectory: true)
    }

    static func metadataRootURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(metadataDirectoryName, isDirectory: true)
    }
}

enum SyncItemStatus: String, Codable, CaseIterable {
    case synced
    case uploading
    case downloading
    case conflict
    case pending
    case error
    case disabled
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
}

enum SyncTargetKind: String, Codable, Hashable, CaseIterable {
    case file
    case folder

    var isDirectory: Bool {
        self == .folder
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
    var kind: SyncTargetKind
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

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case localPath
        case cloudFilePath
        case cloudFileId
        case isEnabled
        case status
        case lastKnownLocalHash
        case lastSeenCloudVersionId
        case conflictState
        case cloudVersion
        case deviceReceipts
        case history
        case lastErrorMessage
        case createdAt
    }

    init(
        id: String,
        kind: SyncTargetKind,
        localPath: String,
        cloudFilePath: String,
        cloudFileId: String,
        isEnabled: Bool,
        status: SyncItemStatus,
        lastKnownLocalHash: String?,
        lastSeenCloudVersionId: String?,
        conflictState: ConflictState?,
        cloudVersion: CloudVersion?,
        deviceReceipts: [String: DeviceReceipt],
        history: [SyncEvent],
        lastErrorMessage: String?,
        createdAt: String
    ) {
        self.id = id
        self.kind = kind
        self.localPath = localPath
        self.cloudFilePath = cloudFilePath
        self.cloudFileId = cloudFileId
        self.isEnabled = isEnabled
        self.status = status
        self.lastKnownLocalHash = lastKnownLocalHash
        self.lastSeenCloudVersionId = lastSeenCloudVersionId
        self.conflictState = conflictState
        self.cloudVersion = cloudVersion
        self.deviceReceipts = deviceReceipts
        self.history = history
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(SyncTargetKind.self, forKey: .kind) ?? .file
        localPath = try container.decode(String.self, forKey: .localPath)
        cloudFilePath = try container.decode(String.self, forKey: .cloudFilePath)
        cloudFileId = try container.decode(String.self, forKey: .cloudFileId)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        status = try container.decode(SyncItemStatus.self, forKey: .status)
        lastKnownLocalHash = try container.decodeIfPresent(String.self, forKey: .lastKnownLocalHash)
        lastSeenCloudVersionId = try container.decodeIfPresent(String.self, forKey: .lastSeenCloudVersionId)
        conflictState = try container.decodeIfPresent(ConflictState.self, forKey: .conflictState)
        cloudVersion = try container.decodeIfPresent(CloudVersion.self, forKey: .cloudVersion)
        deviceReceipts = try container.decodeIfPresent([String: DeviceReceipt].self, forKey: .deviceReceipts) ?? [:]
        history = try container.decodeIfPresent([SyncEvent].self, forKey: .history) ?? []
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

struct CloudFileMetadata: Codable, Hashable {
    var cloudFileId: String
    var kind: SyncTargetKind
    var cloudFilePath: String
    var cloudVersion: CloudVersion?
    var deviceReceipts: [String: DeviceReceipt]
    var eventLog: [SyncEvent]
    var deletedAt: String?
    var deletedByDevice: DeviceInfo?

    private enum CodingKeys: String, CodingKey {
        case cloudFileId
        case kind
        case cloudFilePath
        case cloudVersion
        case deviceReceipts
        case eventLog
        case deletedAt
        case deletedByDevice
    }

    init(
        cloudFileId: String,
        kind: SyncTargetKind,
        cloudFilePath: String,
        cloudVersion: CloudVersion?,
        deviceReceipts: [String: DeviceReceipt],
        eventLog: [SyncEvent],
        deletedAt: String?,
        deletedByDevice: DeviceInfo?
    ) {
        self.cloudFileId = cloudFileId
        self.kind = kind
        self.cloudFilePath = cloudFilePath
        self.cloudVersion = cloudVersion
        self.deviceReceipts = deviceReceipts
        self.eventLog = eventLog
        self.deletedAt = deletedAt
        self.deletedByDevice = deletedByDevice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloudFileId = try container.decode(String.self, forKey: .cloudFileId)
        kind = try container.decodeIfPresent(SyncTargetKind.self, forKey: .kind) ?? .file
        cloudFilePath = try container.decode(String.self, forKey: .cloudFilePath)
        cloudVersion = try container.decodeIfPresent(CloudVersion.self, forKey: .cloudVersion)
        deviceReceipts = try container.decodeIfPresent([String: DeviceReceipt].self, forKey: .deviceReceipts) ?? [:]
        eventLog = try container.decodeIfPresent([SyncEvent].self, forKey: .eventLog) ?? []
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        deletedByDevice = try container.decodeIfPresent(DeviceInfo.self, forKey: .deletedByDevice)
    }
}

struct CloudFileRecord: Hashable, Identifiable {
    var id: String { cloudFileId }
    var cloudFileId: String
    var kind: SyncTargetKind
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

    var cloudFilesRootPath: String {
        FilelayLayout.cloudFilesRootURL(rootPath: managedRootPath).path
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
}

struct DiscoveryCandidate: Identifiable, Hashable {
    enum Confidence: String, Hashable {
        case exactHash
        case uniqueName
        case discovered
    }

    var id: String { cloudFileId }
    var cloudFileId: String
    var kind: SyncTargetKind
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
