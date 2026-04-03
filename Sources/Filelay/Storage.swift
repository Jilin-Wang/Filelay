import Foundation

final class Storage {
    private enum Legacy {
        static let appSupportDirectoryName = "AutoiCloud"
        static let legacyDefaultsDeviceIDKey = "autoiCloud.deviceId"
    }

    private let fm: FileManager
    private let defaults: UserDefaults
    private let appSupportBaseURL: URL
    private let iCloudDriveBaseURL: URL
    private let allowsLegacyAppSupportLookup: Bool

    var logger: StructuredLogger?

    private func logError(_ message: String, path: String? = nil) {
        guard let logger else { return }
        logger.log(SyncLogEntry(
            timestamp: Date().filelayString,
            level: .error,
            category: "storage",
            message: message,
            trigger: nil,
            device: DeviceInfo(id: "storage", name: "Storage"),
            itemID: nil,
            cloudFileId: nil,
            localPath: path,
            cloudPath: nil,
            metadata: [:]
        ))
    }

    struct DiscoveredCloudMetadata {
        var metadata: CloudFileMetadata
        var metadataURL: URL
    }

    struct LoadedMetadata {
        var metadata: CloudFileMetadata
        var destinationURL: URL
    }

    private var appSupportDir: URL {
        appSupportBaseURL
    }

    private var syncItemsURL: URL {
        appSupportDir.appendingPathComponent("sync_items.json")
    }

    private var settingsURL: URL {
        appSupportDir.appendingPathComponent("settings.json")
    }

    private var deviceIdentityURL: URL {
        appSupportDir.appendingPathComponent("device_identity.json")
    }

    private var legacyAppSupportDir: URL {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // 理论上不应该发生，但避免 .first! 导致的潜在崩溃。
            return appSupportBaseURL.appendingPathComponent(Legacy.appSupportDirectoryName, isDirectory: true)
        }
        return base.appendingPathComponent(Legacy.appSupportDirectoryName, isDirectory: true)
    }

    private var legacySettingsURL: URL {
        legacyAppSupportDir.appendingPathComponent("settings.json")
    }

    private var legacySyncItemsURL: URL {
        legacyAppSupportDir.appendingPathComponent("sync_items.json")
    }

    private var legacyDeviceIdentityURL: URL {
        legacyAppSupportDir.appendingPathComponent("device_identity.json")
    }

    private var legacyConfigURL: URL {
        appSupportDir.appendingPathComponent("config.json")
    }

    private var legacyLocalStateURL: URL {
        appSupportDir.appendingPathComponent("local_state.json")
    }

    private var iCloudDriveRootURL: URL {
        iCloudDriveBaseURL
    }

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        appSupportDir: URL? = nil,
        iCloudDriveRootURL: URL? = nil
    ) {
        self.fm = fileManager
        self.defaults = userDefaults
        self.allowsLegacyAppSupportLookup = appSupportDir == nil
        let appSupportBaseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportBaseURL = appSupportDir ?? appSupportBaseDirectory.appendingPathComponent("Filelay", isDirectory: true)
        self.iCloudDriveBaseURL = iCloudDriveRootURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try? fm.createDirectory(at: self.appSupportBaseURL, withIntermediateDirectories: true)
        if allowsLegacyAppSupportLookup {
            migrateLegacyAppSupportIfNeeded()
        }
        _ = ensureManagedRoot(path: defaultManagedRootURL.path)
    }

    var defaultManagedRootURL: URL {
        iCloudDriveRootURL.appendingPathComponent("Filelay", isDirectory: true)
    }

    var legacyManagedRootURL: URL {
        iCloudDriveRootURL.appendingPathComponent(Legacy.appSupportDirectoryName, isDirectory: true)
    }

    var logsDirectoryURL: URL {
        appSupportDir.appendingPathComponent("Logs", isDirectory: true)
    }

    func currentDevice() -> DeviceInfo {
        let name = Host.current().localizedName ?? "Unknown-Mac"

        if let data = try? Data(contentsOf: deviceIdentityURL),
           let stored = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
            let normalized = DeviceInfo(id: stored.id, name: name)
            if normalized != stored {
                saveCurrentDevice(normalized)
            }
            defaults.set(normalized.id, forKey: "filelay.deviceId")
            return normalized
        }

        if allowsLegacyAppSupportLookup,
           let data = try? Data(contentsOf: legacyDeviceIdentityURL),
           let stored = try? JSONDecoder().decode(DeviceInfo.self, from: data) {
            let normalized = DeviceInfo(id: stored.id, name: name)
            saveCurrentDevice(normalized)
            defaults.set(normalized.id, forKey: "filelay.deviceId")
            return normalized
        }

        let deviceId = defaults.string(forKey: "filelay.deviceId")
            ?? (allowsLegacyAppSupportLookup ? defaults.string(forKey: Legacy.legacyDefaultsDeviceIDKey) : nil)
            ?? UUID().uuidString
        let device = DeviceInfo(id: deviceId, name: name)
        saveCurrentDevice(device)
        defaults.set(device.id, forKey: "filelay.deviceId")
        return device
    }

    func loadSettings() -> AppSettings {
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            _ = ensureManagedRoot(path: decoded.managedRootPath)
            return decoded
        }

        if allowsLegacyAppSupportLookup,
           let data = try? Data(contentsOf: legacySettingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            saveSettings(decoded)
            _ = ensureManagedRoot(path: decoded.managedRootPath)
            return decoded
        }

        let settings = AppSettings.default(managedRootPath: defaultManagedRootURL.path)
        saveSettings(settings)
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        _ = ensureManagedRoot(path: settings.managedRootPath)
        do {
            let data = try JSONEncoder.pretty.encode(settings)
            try data.writeAtomically(to: settingsURL)
        } catch {
            logError("Failed to save settings: \(error.localizedDescription)", path: settingsURL.path)
        }
    }

    func loadSyncItems() -> [SyncItem] {
        if let data = try? Data(contentsOf: syncItemsURL),
           let decoded = try? JSONDecoder().decode([SyncItem].self, from: data) {
            let normalized = decoded.map(normalizeSyncItem)
            if normalized != decoded {
                saveSyncItems(normalized)
            }
            return normalized
        }

        if allowsLegacyAppSupportLookup,
           let data = try? Data(contentsOf: legacySyncItemsURL),
           let decoded = try? JSONDecoder().decode([SyncItem].self, from: data) {
            let normalized = decoded.map(normalizeSyncItem)
            saveSyncItems(normalized)
            return normalized
        }

        return migrateLegacySyncItem()
    }

    func saveSyncItems(_ items: [SyncItem]) {
        do {
            let data = try JSONEncoder.pretty.encode(items)
            try data.writeAtomically(to: syncItemsURL)
        } catch {
            logError("Failed to save sync items: \(error.localizedDescription)", path: syncItemsURL.path)
        }
    }

    func ensureManagedRoot(path: String) -> URL {
        let rootURL = URL(fileURLWithPath: path)
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: FilelayLayout.cloudFilesRootURL(rootPath: path), withIntermediateDirectories: true)
        try? fm.createDirectory(at: FilelayLayout.metadataRootURL(rootPath: path), withIntermediateDirectories: true)
        return rootURL
    }

    func cloudFilesRootURL(rootPath: String) -> URL {
        let rootURL = ensureManagedRoot(path: rootPath)
        let cloudFilesURL = rootURL.appendingPathComponent(FilelayLayout.cloudFilesDirectoryName, isDirectory: true)
        try? fm.createDirectory(at: cloudFilesURL, withIntermediateDirectories: true)
        return cloudFilesURL
    }

    func metadataURL(for cloudFileURL: URL, cloudFileId: String) -> URL {
        if let managedRootURL = managedRootURL(for: cloudFileURL) {
            let metadataDir = managedRootURL.appendingPathComponent(FilelayLayout.metadataDirectoryName, isDirectory: true)
            return metadataDir.appendingPathComponent("\(cloudFileId).json")
        }
        let sidecarDir = cloudFileURL.deletingLastPathComponent().appendingPathComponent(FilelayLayout.metadataDirectoryName, isDirectory: true)
        return sidecarDir.appendingPathComponent("\(cloudFileId).json")
    }

    func legacySidecarMetadataURL(for cloudFileURL: URL, cloudFileId: String) -> URL {
        let sidecarDir = cloudFileURL.deletingLastPathComponent().appendingPathComponent(FilelayLayout.legacyMetadataDirectoryName, isDirectory: true)
        return sidecarDir.appendingPathComponent("\(cloudFileId).json")
    }

    func legacyMetadataURL(for cloudFileURL: URL) -> URL {
        cloudFileURL.deletingLastPathComponent().appendingPathComponent(".sync.meta.json")
    }

    func loadMetadata(for cloudFileURL: URL, cloudFileId: String) -> LoadedMetadata {
        let destinationURL = metadataURL(for: cloudFileURL, cloudFileId: cloudFileId)
        for candidateURL in [destinationURL, legacySidecarMetadataURL(for: cloudFileURL, cloudFileId: cloudFileId)] {
            if let data = try? Data(contentsOf: candidateURL),
               let decoded = try? JSONDecoder().decode(CloudFileMetadata.self, from: data) {
                let normalized = normalizeMetadata(decoded)
                if normalized != decoded || candidateURL != destinationURL,
                   let encoded = try? JSONEncoder.pretty.encode(normalized) {
                    try? encoded.writeAtomically(to: destinationURL)
                }
                return LoadedMetadata(metadata: normalized, destinationURL: destinationURL)
            }
        }

        let legacyURL = legacyMetadataURL(for: cloudFileURL)
        if let data = try? Data(contentsOf: legacyURL),
           let decoded = try? JSONDecoder().decode(LegacySyncMetadata.self, from: data) {
            let migrated = CloudFileMetadata(
                cloudFileId: decoded.fileId.isEmpty ? cloudFileId : decoded.fileId,
                kind: inferredTargetKind(for: cloudFileURL),
                cloudFilePath: cloudFileURL.path,
                cloudVersion: decoded.cloudVersion.map {
                    CloudVersion(
                        versionId: $0.versionId,
                        contentHash: $0.contentHash,
                        updatedAt: $0.updatedAt,
                        updatedByDevice: $0.updatedByDevice,
                        sourceFileMtime: $0.sourceFileMtime
                    )
                },
                deviceReceipts: decoded.deviceReceipts.mapValues {
                    DeviceReceipt(
                        device: DeviceInfo(id: $0.deviceId, name: $0.deviceName),
                        lastAppliedVersionId: $0.lastAppliedVersionId,
                        lastAppliedAt: $0.lastAppliedAt,
                        localFileMtimeAfterApply: $0.localFileMtimeAfterApply,
                        lastSyncStatus: .synced
                    )
                },
                eventLog: [],
                deletedAt: nil,
                deletedByDevice: nil
            )
            let normalized = normalizeMetadata(migrated)
            if let encoded = try? JSONEncoder.pretty.encode(normalized) {
                try? encoded.writeAtomically(to: destinationURL)
            }
            return LoadedMetadata(metadata: normalized, destinationURL: destinationURL)
        }

        let empty = CloudFileMetadata(
            cloudFileId: cloudFileId,
            kind: inferredTargetKind(for: cloudFileURL),
            cloudFilePath: cloudFileURL.path,
            cloudVersion: nil,
            deviceReceipts: [:],
            eventLog: [],
            deletedAt: nil,
            deletedByDevice: nil
        )
        return LoadedMetadata(metadata: empty, destinationURL: destinationURL)
    }

    func saveMetadata(_ metadata: CloudFileMetadata, for cloudFileURL: URL) throws {
        let destinationURL = metadataURL(for: cloudFileURL, cloudFileId: metadata.cloudFileId)
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var merged = normalizeMetadata(metadata)
        if let data = try? Data(contentsOf: destinationURL),
           let existing = try? JSONDecoder().decode(CloudFileMetadata.self, from: data) {
            merged = merge(existing: normalizeMetadata(existing), incoming: merged)
        }

        merged = normalizeMetadata(merged)
        let encoded = try JSONEncoder.pretty.encode(merged)
        try encoded.writeAtomically(to: destinationURL)
    }

    func replaceItemAtomically(at destinationURL: URL, withContentsOf sourceURL: URL) throws {
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp.\(UUID().uuidString).\(destinationURL.lastPathComponent)")
        if fm.fileExists(atPath: tempURL.path) {
            try? fm.removeItem(at: tempURL)
        }
        try fm.copyItem(at: sourceURL, to: tempURL)
        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: destinationURL)
        }
    }

    func replaceFileAtomically(at destinationURL: URL, withContentsOf sourceURL: URL) throws {
        try replaceItemAtomically(at: destinationURL, withContentsOf: sourceURL)
    }

    func replaceDirectoryContents(at destinationURL: URL, withContentsOf sourceURL: URL) throws {
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let sourceEntries = Set((try? fm.contentsOfDirectory(atPath: sourceURL.path)) ?? [])
        let destinationEntries = Set((try? fm.contentsOfDirectory(atPath: destinationURL.path)) ?? [])

        for staleEntry in destinationEntries.subtracting(sourceEntries) {
            let staleURL = destinationURL.appendingPathComponent(staleEntry)
            try? fm.removeItem(at: staleURL)
        }

        for entry in sourceEntries {
            let sourceChildURL = sourceURL.appendingPathComponent(entry)
            let destinationChildURL = destinationURL.appendingPathComponent(entry)
            var isDirectory = ObjCBool(false)
            guard fm.fileExists(atPath: sourceChildURL.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                try replaceDirectoryContents(at: destinationChildURL, withContentsOf: sourceChildURL)
            } else {
                try replaceItemAtomically(at: destinationChildURL, withContentsOf: sourceChildURL)
            }
        }
    }

    func discoverManagedMetadata(rootPath: String) -> [DiscoveredCloudMetadata] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard fm.fileExists(atPath: rootURL.path) else { return [] }

        let candidateDirectories = [
            rootURL.appendingPathComponent(FilelayLayout.metadataDirectoryName, isDirectory: true),
            rootURL.appendingPathComponent(FilelayLayout.legacyMetadataDirectoryName, isDirectory: true)
        ]

        // Resolve iCloud conflict copies before discovery
        for directory in candidateDirectories where fm.fileExists(atPath: directory.path) {
            resolveICloudConflictCopies(in: directory)
        }

        var discovered: [DiscoveredCloudMetadata] = []

        for directory in candidateDirectories where fm.fileExists(atPath: directory.path) {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants],
                errorHandler: nil
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "json" else { continue }
                // Skip any remaining conflict copies
                guard !isICloudConflictCopy(url) else { continue }
                guard let data = try? Data(contentsOf: url),
                      let metadata = try? JSONDecoder().decode(CloudFileMetadata.self, from: data) else {
                    continue
                }
                let normalized = normalizeMetadata(metadata)
                let destinationURL = metadataURL(for: URL(fileURLWithPath: normalized.cloudFilePath), cloudFileId: normalized.cloudFileId)
                if normalized != metadata || destinationURL != url,
                   let encoded = try? JSONEncoder.pretty.encode(normalized) {
                    try? encoded.writeAtomically(to: destinationURL)
                }
                discovered.append(DiscoveredCloudMetadata(metadata: normalized, metadataURL: destinationURL))
            }
        }

        return discovered.sorted { lhs, rhs in
            let leftDate = lhs.metadata.cloudVersion?.updatedAt ?? ""
            let rightDate = rhs.metadata.cloudVersion?.updatedAt ?? ""
            return leftDate > rightDate
        }
    }

    private func isICloudConflictCopy(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasSuffix(".json"), !name.hasPrefix(".") else { return false }
        // iCloud creates files like "uuid (conflicted copy 2026-04-02).json"
        let lowered = name.lowercased()
        return lowered.contains("conflicted copy") || lowered.contains("conflict version")
    }

    /// Scans a metadata directory for iCloud conflict copy files and merges them
    /// back into the primary metadata file, then removes the conflict copy.
    private func resolveICloudConflictCopies(in directory: URL) {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "json", isICloudConflictCopy(url) else { continue }

            guard let conflictData = try? Data(contentsOf: url),
                  let conflictMetadata = try? JSONDecoder().decode(CloudFileMetadata.self, from: conflictData) else {
                // Can't parse conflict copy — remove it to prevent repeated processing
                try? fm.removeItem(at: url)
                logError("Removed unparseable iCloud conflict copy", path: url.path)
                continue
            }

            let primaryURL = metadataURL(
                for: URL(fileURLWithPath: conflictMetadata.cloudFilePath),
                cloudFileId: conflictMetadata.cloudFileId
            )

            if let primaryData = try? Data(contentsOf: primaryURL),
               let primaryMetadata = try? JSONDecoder().decode(CloudFileMetadata.self, from: primaryData) {
                // Merge conflict into primary
                let merged = merge(existing: normalizeMetadata(primaryMetadata), incoming: normalizeMetadata(conflictMetadata))
                if let encoded = try? JSONEncoder.pretty.encode(normalizeMetadata(merged)) {
                    try? encoded.writeAtomically(to: primaryURL)
                }
            } else {
                // No primary exists — promote conflict copy to primary
                let normalized = normalizeMetadata(conflictMetadata)
                if let encoded = try? JSONEncoder.pretty.encode(normalized) {
                    try? fm.createDirectory(at: primaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? encoded.writeAtomically(to: primaryURL)
                }
            }

            try? fm.removeItem(at: url)
        }
    }

    func migrateManagedRootIfNeeded(settings: AppSettings, items: [SyncItem]) -> (settings: AppSettings, items: [SyncItem], didMigrate: Bool) {
        let legacyRoot = legacyManagedRootURL.standardizedFileURL.path
        let currentRoot = URL(fileURLWithPath: settings.managedRootPath).standardizedFileURL.path
        let newRoot = defaultManagedRootURL.standardizedFileURL.path

        guard currentRoot == legacyRoot else {
            return (settings, items, false)
        }

        var updatedSettings = settings
        updatedSettings.managedRootPath = newRoot
        _ = ensureManagedRoot(path: newRoot)

        let legacyRootURL = URL(fileURLWithPath: legacyRoot, isDirectory: true)
        let newCloudFilesRootURL = cloudFilesRootURL(rootPath: newRoot)
        var updatedItems = items

        for index in updatedItems.indices {
            let oldCloudURL = URL(fileURLWithPath: updatedItems[index].cloudFilePath)
            guard oldCloudURL.path.hasPrefix(legacyRootURL.path + "/") || oldCloudURL.path == legacyRootURL.path else {
                continue
            }

            let relativePath = String(oldCloudURL.path.dropFirst(legacyRootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }

            let newCloudURL = newCloudFilesRootURL.appendingPathComponent(relativePath)
            try? fm.createDirectory(at: newCloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fm.fileExists(atPath: oldCloudURL.path), !fm.fileExists(atPath: newCloudURL.path) {
                try? fm.moveItem(at: oldCloudURL, to: newCloudURL)
            }

            var metadata = loadMetadata(for: oldCloudURL, cloudFileId: updatedItems[index].cloudFileId).metadata
            metadata.cloudFilePath = newCloudURL.path
            try? saveMetadata(metadata, for: newCloudURL)

            updatedItems[index].cloudFilePath = newCloudURL.path
        }

        saveSettings(updatedSettings)
        saveSyncItems(updatedItems)
        return (updatedSettings, updatedItems, true)
    }

    private func merge(existing: CloudFileMetadata, incoming: CloudFileMetadata) -> CloudFileMetadata {
        var merged = existing
        merged.cloudFilePath = incoming.cloudFilePath
        if incoming.deletedAt != nil {
            merged.deletedAt = incoming.deletedAt
            merged.deletedByDevice = incoming.deletedByDevice
        }

        if shouldUseIncomingVersion(current: existing.cloudVersion, incoming: incoming.cloudVersion) {
            merged.cloudVersion = incoming.cloudVersion
        }

        for (deviceId, receipt) in incoming.deviceReceipts {
            if let current = merged.deviceReceipts[deviceId] {
                merged.deviceReceipts[deviceId] = newerReceipt(current: current, incoming: receipt)
            } else {
                merged.deviceReceipts[deviceId] = receipt
            }
        }

        var eventMap = Dictionary(uniqueKeysWithValues: merged.eventLog.map { ($0.id, $0) })
        for event in incoming.eventLog {
            if let current = eventMap[event.id] {
                eventMap[event.id] = newerEvent(current: current, incoming: event)
            } else {
                eventMap[event.id] = event
            }
        }
        merged.eventLog = Array(eventMap.values).sorted { $0.timestamp > $1.timestamp }
        if merged.eventLog.count > 200 {
            merged.eventLog = Array(merged.eventLog.prefix(200))
        }

        return merged
    }

    private func saveCurrentDevice(_ device: DeviceInfo) {
        do {
            let data = try JSONEncoder.pretty.encode(device)
            try data.writeAtomically(to: deviceIdentityURL)
        } catch {
            logError("Failed to save device identity: \(error.localizedDescription)", path: deviceIdentityURL.path)
        }
    }

    private func managedRootURL(for cloudFileURL: URL) -> URL? {
        let standardizedPath = cloudFileURL.standardizedFileURL.path
        let marker = "/\(FilelayLayout.cloudFilesDirectoryName)/"
        guard let markerRange = standardizedPath.range(of: marker) else {
            return nil
        }
        let rootPath = String(standardizedPath[..<markerRange.lowerBound])
        guard !rootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    private func migrateLegacyAppSupportIfNeeded() {
        guard appSupportBaseURL.path != legacyAppSupportDir.path else { return }
        guard fm.fileExists(atPath: legacyAppSupportDir.path) else { return }

        let candidateFiles: [(URL, URL)] = [
            (legacySettingsURL, settingsURL),
            (legacySyncItemsURL, syncItemsURL),
            (legacyDeviceIdentityURL, deviceIdentityURL),
            (legacyAppSupportDir.appendingPathComponent("config.json"), legacyConfigURL),
            (legacyAppSupportDir.appendingPathComponent("local_state.json"), legacyLocalStateURL)
        ]

        for (source, destination) in candidateFiles {
            guard fm.fileExists(atPath: source.path) else { continue }
            guard !fm.fileExists(atPath: destination.path) else { continue }
            guard let data = try? Data(contentsOf: source) else { continue }
            try? data.writeAtomically(to: destination)
        }
    }

    private func normalizeSyncItem(_ item: SyncItem) -> SyncItem {
        var normalized = item
        let versionMap = buildVersionMap(
            cloudVersion: item.cloudVersion,
            receipts: item.deviceReceipts,
            history: item.history,
            conflictState: item.conflictState,
            fallbackVersionId: item.lastSeenCloudVersionId
        )

        if var cloudVersion = normalized.cloudVersion {
            cloudVersion.versionId = versionMap[cloudVersion.versionId] ?? cloudVersion.versionId
            normalized.cloudVersion = cloudVersion
        }

        normalized.deviceReceipts = normalized.deviceReceipts.mapValues { receipt in
            var updatedReceipt = receipt
            updatedReceipt.lastAppliedVersionId = versionMap[receipt.lastAppliedVersionId] ?? receipt.lastAppliedVersionId
            return updatedReceipt
        }

        normalized.history = normalized.history.map { event in
            var updatedEvent = event
            if let versionId = event.versionId {
                updatedEvent.versionId = versionMap[versionId] ?? versionId
            }
            return updatedEvent
        }

        if var conflictState = normalized.conflictState, let cloudVersionId = conflictState.cloudVersionId {
            conflictState.cloudVersionId = versionMap[cloudVersionId] ?? cloudVersionId
            normalized.conflictState = conflictState
        }

        if let lastSeenCloudVersionId = normalized.lastSeenCloudVersionId {
            normalized.lastSeenCloudVersionId = versionMap[lastSeenCloudVersionId] ?? normalizedVersionId(lastSeenCloudVersionId, timestamp: normalized.cloudVersion?.updatedAt ?? normalized.conflictState?.detectedAt)
        }

        return normalized
    }

    private func normalizeMetadata(_ metadata: CloudFileMetadata) -> CloudFileMetadata {
        var normalized = metadata
        let versionMap = buildVersionMap(
            cloudVersion: metadata.cloudVersion,
            receipts: metadata.deviceReceipts,
            history: metadata.eventLog,
            conflictState: nil,
            fallbackVersionId: nil
        )

        if var cloudVersion = normalized.cloudVersion {
            cloudVersion.versionId = versionMap[cloudVersion.versionId] ?? cloudVersion.versionId
            normalized.cloudVersion = cloudVersion
        }

        normalized.deviceReceipts = normalized.deviceReceipts.mapValues { receipt in
            var updatedReceipt = receipt
            updatedReceipt.lastAppliedVersionId = versionMap[receipt.lastAppliedVersionId] ?? receipt.lastAppliedVersionId
            return updatedReceipt
        }

        normalized.eventLog = normalized.eventLog.map { event in
            var updatedEvent = event
            if let versionId = event.versionId {
                updatedEvent.versionId = versionMap[versionId] ?? versionId
            }
            return updatedEvent
        }

        return normalized
    }

    private func buildVersionMap(
        cloudVersion: CloudVersion?,
        receipts: [String: DeviceReceipt],
        history: [SyncEvent],
        conflictState: ConflictState?,
        fallbackVersionId: String?
    ) -> [String: String] {
        var map: [String: String] = [:]

        if let cloudVersion {
            map[cloudVersion.versionId] = normalizedVersionId(cloudVersion.versionId, timestamp: cloudVersion.updatedAt)
        }

        for receipt in receipts.values {
            map[receipt.lastAppliedVersionId] = normalizedVersionId(receipt.lastAppliedVersionId, timestamp: receipt.lastAppliedAt)
        }

        for event in history {
            guard let versionId = event.versionId else { continue }
            map[versionId] = normalizedVersionId(versionId, timestamp: event.timestamp)
        }

        if let conflictState, let cloudVersionId = conflictState.cloudVersionId {
            map[cloudVersionId] = normalizedVersionId(cloudVersionId, timestamp: conflictState.detectedAt)
        }

        if let fallbackVersionId {
            map[fallbackVersionId] = normalizedVersionId(fallbackVersionId, timestamp: cloudVersion?.updatedAt ?? conflictState?.detectedAt)
        }

        return map
    }

    private func normalizedVersionId(_ versionId: String, timestamp: String?) -> String {
        guard !versionId.isEmpty else { return versionId }
        if versionId.range(of: #"^\d{17}$"#, options: .regularExpression) != nil {
            return versionId
        }
        guard let timestamp, let normalizedTimestamp = formattedVersionTimestamp(timestamp) else {
            return versionId
        }
        return normalizedTimestamp
    }

    private func formattedVersionTimestamp(_ isoString: String) -> String? {
        guard let date = ISO8601DateFormatter.filelay.date(from: isoString)
            ?? ISO8601DateFormatter().date(from: isoString) else {
            return nil
        }
        return Storage.versionFormatter.string(from: date)
    }

    private func newerReceipt(current: DeviceReceipt, incoming: DeviceReceipt) -> DeviceReceipt {
        incoming.lastAppliedAt >= current.lastAppliedAt ? incoming : current
    }

    private func newerEvent(current: SyncEvent, incoming: SyncEvent) -> SyncEvent {
        incoming.timestamp >= current.timestamp ? incoming : current
    }

    private func shouldUseIncomingVersion(current: CloudVersion?, incoming: CloudVersion?) -> Bool {
        guard let incoming else { return false }
        guard let current else { return true }
        return incoming.updatedAt >= current.updatedAt
    }

    private func migrateLegacySyncItem() -> [SyncItem] {
        guard let configData = try? Data(contentsOf: legacyConfigURL),
              let config = try? JSONDecoder().decode(LegacySyncConfig.self, from: configData),
              let localPath = config.localFilePath,
              let cloudPath = config.cloudFilePath else {
            return []
        }

        let cloudURL = URL(fileURLWithPath: cloudPath)
        let legacyMetaURL = legacyMetadataURL(for: cloudURL)
        let legacyFileId: String
        let legacyCloudVersion: CloudVersion?
        let legacyReceipts: [String: DeviceReceipt]

        if let data = try? Data(contentsOf: legacyMetaURL),
           let legacyMeta = try? JSONDecoder().decode(LegacySyncMetadata.self, from: data) {
            legacyFileId = legacyMeta.fileId.isEmpty ? UUID().uuidString : legacyMeta.fileId
            legacyCloudVersion = legacyMeta.cloudVersion.map {
                CloudVersion(
                    versionId: normalizedVersionId($0.versionId, timestamp: $0.updatedAt),
                    contentHash: $0.contentHash,
                    updatedAt: $0.updatedAt,
                    updatedByDevice: $0.updatedByDevice,
                    sourceFileMtime: $0.sourceFileMtime
                )
            }
            legacyReceipts = legacyMeta.deviceReceipts.mapValues {
                DeviceReceipt(
                    device: DeviceInfo(id: $0.deviceId, name: $0.deviceName),
                    lastAppliedVersionId: $0.lastAppliedVersionId,
                    lastAppliedAt: $0.lastAppliedAt,
                    localFileMtimeAfterApply: $0.localFileMtimeAfterApply,
                    lastSyncStatus: .synced
                )
            }
        } else {
            legacyFileId = UUID().uuidString
            legacyCloudVersion = nil
            legacyReceipts = [:]
        }

        let localState: LegacyLocalState?
        if let stateData = try? Data(contentsOf: legacyLocalStateURL) {
            localState = try? JSONDecoder().decode(LegacyLocalState.self, from: stateData)
        } else {
            localState = nil
        }

        let item = SyncItem(
            id: UUID().uuidString,
            kind: inferredTargetKind(for: cloudURL),
            localPath: localPath,
            cloudFilePath: cloudPath,
            cloudFileId: legacyFileId,
            isEnabled: config.isSyncEnabled,
            status: config.isSyncEnabled ? .pending : .disabled,
            lastKnownLocalHash: localState?.lastSyncedLocalHash,
            lastSeenCloudVersionId: localState?.lastSeenCloudVersionId,
            conflictState: nil,
            cloudVersion: legacyCloudVersion,
            deviceReceipts: legacyReceipts,
            history: [],
            lastErrorMessage: nil,
            createdAt: Date().filelayString
        )

        let normalized = normalizeSyncItem(item)
        saveSyncItems([normalized])
        return [normalized]
    }

    private func inferredTargetKind(for url: URL) -> SyncTargetKind {
        var isDirectory = ObjCBool(false)
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        return .file
    }
}

private extension Storage {
    static let versionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter
    }()
}

private struct LegacySyncConfig: Codable {
    var localFilePath: String?
    var cloudFilePath: String?
    var isSyncEnabled: Bool
}

private struct LegacyLocalState: Codable {
    var lastSyncedLocalHash: String?
    var lastSeenCloudVersionId: String?
}

private struct LegacySyncMetadata: Codable {
    struct CloudVersion: Codable {
        var versionId: String
        var contentHash: String
        var updatedAt: String
        var updatedByDevice: DeviceInfo
        var sourceFileMtime: String
    }

    struct DeviceReceipt: Codable {
        var deviceId: String
        var deviceName: String
        var lastAppliedVersionId: String
        var lastAppliedAt: String
        var localFileMtimeAfterApply: String
    }

    var fileId: String
    var cloudVersion: CloudVersion?
    var deviceReceipts: [String: DeviceReceipt]
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension Data {
    func writeAtomically(to destinationURL: URL) throws {
        let dir = destinationURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".tmp.\(UUID().uuidString).json")
        try write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }
    }
}
