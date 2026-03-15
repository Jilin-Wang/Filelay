import CryptoKit
import Foundation

final class SyncCoordinator {
    private let storage: Storage
    private var settings: AppSettings
    private var items: [SyncItem]
    private let queue = DispatchQueue(label: "Filelay.SyncCoordinator")
    private var timer: DispatchSourceTimer?
    private var fileMonitors: [String: FileSystemMonitor] = [:]
    private var watchSyncGeneration: UInt = 0

    private let currentDevice: DeviceInfo
    private let logger: StructuredLogger

    var onSnapshotChange: ((AppSnapshot) -> Void)?

    init(storage: Storage) {
        self.storage = storage
        self.currentDevice = storage.currentDevice()
        self.settings = storage.loadSettings()
        self.logger = StructuredLogger(logsDirectoryURL: storage.logsDirectoryURL)
        let loadedItems = storage.loadSyncItems()
        self.items = loadedItems
        self.items = loadedItems.map(canonicalize(item:))
        if self.items != loadedItems {
            storage.saveSyncItems(self.items)
        }
    }

    func snapshot() -> AppSnapshot {
        queue.sync { makeSnapshot() }
    }

    func start() {
        queue.sync {
            guard timer == nil else {
                publishSnapshot()
                return
            }
            resetTimerLocked()
            rebuildWatchersLocked()
            publishSnapshot()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            invalidateWatchersLocked()
            publishSnapshot()
        }
    }

    func triggerManualSync() {
        queue.async { [weak self] in
            self?.runSyncCycle(trigger: "manual")
        }
    }

    func waitForIdleForTesting() {
        queue.sync {}
    }

    func runManualSyncForTesting() {
        queue.sync {
            runSyncCycle(trigger: "manual")
        }
    }

    func triggerWatchedSyncForTesting() {
        queue.sync {
            scheduleWatchDrivenSyncLocked()
        }
    }

    func updateSyncInterval(_ seconds: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.settings.syncIntervalSeconds = max(seconds, 5)
            self.storage.saveSettings(self.settings)
            if self.timer != nil {
                self.resetTimerLocked()
            }
            self.publishSnapshot()
        }
    }

    func updateAssociationHintsEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.settings.associationHintsEnabled = enabled
            self.storage.saveSettings(self.settings)
            self.publishSnapshot()
        }
    }

    func updateLanguage(_ language: AppLanguage) {
        queue.async { [weak self] in
            guard let self else { return }
            self.settings.language = language
            self.storage.saveSettings(self.settings)
            self.publishSnapshot()
        }
    }

    func updateLaunchAtLoginEnabled(_ enabled: Bool) -> String? {
        queue.sync {
            settings.launchAtLoginEnabled = enabled
            storage.saveSettings(settings)
            publishSnapshot()
        }

        let scriptName = enabled ? "install_menu_app_autostart.sh" : "uninstall_menu_app_autostart.sh"
        guard let scriptURL = findRepositoryScript(named: scriptName) else {
            return "已保存设置，但找不到登录项脚本。"
        }

        if enabled {
            guard let appPath = currentAppBundlePath() else {
                return "已保存设置，但当前不是 .app 运行，未执行登录项脚本。"
            }
            return runProcess(executableURL: scriptURL, arguments: ["--app", appPath])
        }

        return runProcess(executableURL: scriptURL, arguments: [])
    }

    private func resetTimerLocked() {
        timer?.cancel()
        timer = nil

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(pollingIntervalSeconds))
        timer.setEventHandler { [weak self] in
            self?.runSyncCycle(trigger: "timer")
        }
        self.timer = timer
        timer.resume()
    }

    private var pollingIntervalSeconds: Int {
        max(settings.syncIntervalSeconds, 30)
    }

    private func scheduleWatchDrivenSyncLocked() {
        watchSyncGeneration &+= 1
        let generation = watchSyncGeneration
        queue.asyncAfter(deadline: .now() + .milliseconds(450)) { [weak self] in
            guard let self else { return }
            guard self.watchSyncGeneration == generation else { return }
            self.runSyncCycle(trigger: "watch")
        }
    }

    private func rebuildWatchersLocked() {
        invalidateWatchersLocked()

        let targets = watchTargetsLocked()
        for target in targets {
            guard let monitor = FileSystemMonitor(target: target, queue: queue, handler: { [weak self] in
                self?.scheduleWatchDrivenSyncLocked()
            }) else {
                continue
            }
            fileMonitors[target.key] = monitor
        }
    }

    private func invalidateWatchersLocked() {
        for monitor in fileMonitors.values {
            monitor.invalidate()
        }
        fileMonitors.removeAll()
    }

    private func watchTargetsLocked() -> [WatchTarget] {
        var targets: [String: WatchTarget] = [:]

        func insertTarget(path: String, kind: WatchTarget.Kind) {
            guard !path.isEmpty else { return }
            guard FileManager.default.fileExists(atPath: path) else { return }
            let target = WatchTarget(path: path, kind: kind)
            targets[target.key] = target
        }

        insertTarget(path: settings.managedRootPath, kind: .directory)

        for item in items {
            let localURL = URL(fileURLWithPath: item.localPath)
            let cloudURL = URL(fileURLWithPath: item.cloudFilePath)
            let metadataURL = storage.metadataURL(for: cloudURL, cloudFileId: item.cloudFileId)

            insertTarget(path: localURL.deletingLastPathComponent().path, kind: .directory)
            insertTarget(path: cloudURL.deletingLastPathComponent().path, kind: .directory)
            insertTarget(path: metadataURL.deletingLastPathComponent().path, kind: .directory)

            insertTarget(path: localURL.path, kind: .file)
            insertTarget(path: cloudURL.path, kind: .file)
            insertTarget(path: metadataURL.path, kind: .file)
        }

        return Array(targets.values)
    }

    func allLinkTargets() -> [DiscoveryCandidate] {
        queue.sync {
            let discovered = storage
                .discoverManagedMetadata(rootPath: settings.managedRootPath)
                .map { discovered -> Storage.DiscoveredCloudMetadata in
                    var discovered = discovered
                    discovered.metadata = canonicalize(metadata: discovered.metadata)
                    return discovered
                }
                .filter { $0.metadata.deletedAt == nil }
            return discovered.map { discovered in
                DiscoveryCandidate(
                    cloudFileId: discovered.metadata.cloudFileId,
                    cloudFilePath: discovered.metadata.cloudFilePath,
                    fileName: URL(fileURLWithPath: discovered.metadata.cloudFilePath).lastPathComponent,
                    confidence: .discovered,
                    reason: settings.language == .en ? "Existing cloud file" : "已存在云端文件",
                    cloudVersion: discovered.metadata.cloudVersion
                )
            }
        }
    }

    func discoveryCandidates(for localPath: String) -> [DiscoveryCandidate] {
        queue.sync {
            guard settings.associationHintsEnabled else { return [] }
            guard !localPath.isEmpty else { return [] }
            let localURL = URL(fileURLWithPath: localPath)
            guard FileManager.default.fileExists(atPath: localURL.path) else { return [] }

            let discovered = storage
                .discoverManagedMetadata(rootPath: settings.managedRootPath)
                .map { discovered -> Storage.DiscoveredCloudMetadata in
                    var discovered = discovered
                    discovered.metadata = canonicalize(metadata: discovered.metadata)
                    return discovered
                }
                .filter { $0.metadata.deletedAt == nil }
            guard !discovered.isEmpty else { return [] }

            let localHash = fileHash(url: localURL)
            if let localHash {
                let exactMatches = discovered
                    .filter { $0.metadata.cloudVersion?.contentHash == localHash }
                    .map { discovered in
                        DiscoveryCandidate(
                            cloudFileId: discovered.metadata.cloudFileId,
                            cloudFilePath: discovered.metadata.cloudFilePath,
                            fileName: URL(fileURLWithPath: discovered.metadata.cloudFilePath).lastPathComponent,
                            confidence: .exactHash,
                            reason: settings.language == .en ? "Exact content hash match" : "内容哈希一致",
                            cloudVersion: discovered.metadata.cloudVersion
                        )
                    }
                if !exactMatches.isEmpty {
                    return exactMatches
                }
            }

            let sameNameMatches = discovered.filter {
                URL(fileURLWithPath: $0.metadata.cloudFilePath).lastPathComponent.caseInsensitiveCompare(localURL.lastPathComponent) == .orderedSame
            }
            if sameNameMatches.count == 1, let match = sameNameMatches.first {
                return [
                    DiscoveryCandidate(
                        cloudFileId: match.metadata.cloudFileId,
                        cloudFilePath: match.metadata.cloudFilePath,
                        fileName: URL(fileURLWithPath: match.metadata.cloudFilePath).lastPathComponent,
                        confidence: .uniqueName,
                        reason: settings.language == .en ? "Unique same-name candidate" : "同名文件且是唯一候选",
                        cloudVersion: match.metadata.cloudVersion
                    )
                ]
            }
            return []
        }
    }

    func addUploadItem(localPath: String, relativeFolder: String) throws {
        try queue.sync {
            let localURL = URL(fileURLWithPath: localPath)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw CoordinatorError.invalidLocalFile
            }

            let rootURL = storage.ensureManagedRoot(path: settings.managedRootPath)
            let sanitizedFolder = sanitizeRelativeFolder(relativeFolder)
            let targetDirectory = sanitizedFolder.isEmpty
                ? rootURL
                : rootURL.appendingPathComponent(sanitizedFolder, isDirectory: true)

            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            let cloudURL = targetDirectory.appendingPathComponent(localURL.lastPathComponent)
            guard !items.contains(where: { $0.localPath == localURL.path }) else {
                throw CoordinatorError.localFileAlreadyManaged
            }
            let activeMetadataExists = storage
                .discoverManagedMetadata(rootPath: settings.managedRootPath)
                .contains { $0.metadata.cloudFilePath == cloudURL.path && $0.metadata.deletedAt == nil }
            guard !FileManager.default.fileExists(atPath: cloudURL.path), !activeMetadataExists else {
                throw CoordinatorError.cloudTargetAlreadyExists
            }
            guard !items.contains(where: { $0.cloudFilePath == cloudURL.path }) else {
                throw CoordinatorError.cloudFileAlreadyManaged
            }

            let event = makeEvent(action: .added, versionId: nil, note: "通过上传模式添加")
            let item = SyncItem(
                id: UUID().uuidString,
                localPath: localURL.path,
                cloudFilePath: cloudURL.path,
                cloudFileId: UUID().uuidString,
                isEnabled: true,
                status: .pending,
                lastKnownLocalHash: nil,
                lastSeenCloudVersionId: nil,
                conflictState: nil,
                cloudVersion: nil,
                deviceReceipts: [:],
                history: [event],
                lastErrorMessage: nil,
                createdAt: Date().filelayString
            )
            items.insert(item, at: 0)
            log(.info, category: "item.added", message: "Added local file in upload mode", item: item, metadata: [
                "relativeFolder": sanitizedFolder
            ])
            persistItems()
            publishSnapshot()
        }
        triggerManualSync()
    }

    func linkExistingItem(localPath: String, cloudFileId: String) throws {
        try queue.sync {
            let localURL = URL(fileURLWithPath: localPath)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw CoordinatorError.invalidLocalFile
            }
            guard !items.contains(where: { $0.localPath == localURL.path }) else {
                throw CoordinatorError.localFileAlreadyManaged
            }

            let discovered = storage
                .discoverManagedMetadata(rootPath: settings.managedRootPath)
                .map { discovered -> Storage.DiscoveredCloudMetadata in
                    var discovered = discovered
                    discovered.metadata = canonicalize(metadata: discovered.metadata)
                    return discovered
                }
                .first(where: { $0.metadata.cloudFileId == cloudFileId })
            guard let discovered else {
                throw CoordinatorError.cloudMetadataNotFound
            }

            guard !items.contains(where: { $0.cloudFilePath == discovered.metadata.cloudFilePath }) else {
                throw CoordinatorError.cloudFileAlreadyManaged
            }

            let cloudURL = URL(fileURLWithPath: discovered.metadata.cloudFilePath)
            let localHash = fileHash(url: localURL)
            let cloudHash = discovered.metadata.cloudVersion?.contentHash ?? fileHash(url: cloudURL)
            let createdAt = Date().filelayString
            var metadata = canonicalize(metadata: discovered.metadata)
            metadata.eventLog = mergeEvents(
                current: metadata.eventLog,
                newEvent: makeEvent(action: .linked, versionId: metadata.cloudVersion?.versionId, note: "新设备建立关联")
            )

            var item = SyncItem(
                id: UUID().uuidString,
                localPath: localURL.path,
                cloudFilePath: cloudURL.path,
                cloudFileId: metadata.cloudFileId,
                isEnabled: true,
                status: .pending,
                lastKnownLocalHash: localHash,
                lastSeenCloudVersionId: metadata.cloudVersion?.versionId,
                conflictState: nil,
                cloudVersion: metadata.cloudVersion,
                deviceReceipts: metadata.deviceReceipts,
                history: metadata.eventLog,
                lastErrorMessage: nil,
                createdAt: createdAt
            )

                if let localHash, let cloudHash, localHash == cloudHash {
                    updateReceipt(metadata: &metadata, versionId: metadata.cloudVersion?.versionId ?? makeVersionId(hash: localHash), localURL: localURL, status: .synced)
                    try storage.saveMetadata(metadata, for: cloudURL)
                item.deviceReceipts = metadata.deviceReceipts
                item.history = metadata.eventLog
                item.status = .synced
                item.lastSeenCloudVersionId = metadata.cloudVersion?.versionId
            } else {
                item.status = .conflict
                item.conflictState = makeConflictState(
                    localURL: localURL,
                    cloudURL: cloudURL,
                    localHash: localHash ?? "unknown",
                    cloudHash: cloudHash ?? "unknown",
                    cloudVersionId: metadata.cloudVersion?.versionId
                )
                metadata.eventLog = mergeEvents(
                    current: metadata.eventLog,
                    newEvent: makeEvent(action: .conflictDetected, versionId: metadata.cloudVersion?.versionId, note: "首次关联时发现本地与云端内容不同")
                )
                item.history = metadata.eventLog
                try storage.saveMetadata(metadata, for: cloudURL)
            }

            items.insert(item, at: 0)
            log(.info, category: "item.linked", message: "Linked local file to existing cloud file", item: item)
            persistItems()
            publishSnapshot()
        }
    }

    func resolveConflict(itemID: String, choice: ConflictResolutionChoice) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == itemID }) else { return }
            var item = self.items[index]
            guard item.conflictState != nil else { return }

            let localURL = URL(fileURLWithPath: item.localPath)
            let cloudURL = URL(fileURLWithPath: item.cloudFilePath)

            do {
                let loaded = self.storage.loadMetadata(for: cloudURL, cloudFileId: item.cloudFileId)
                var metadata = self.canonicalize(metadata: loaded.metadata)
                switch choice {
                case .keepLocal:
                    try self.push(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "冲突解决：保留本地")
                case .useCloud:
                    try self.pull(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "冲突解决：采用云端")
                case .backupLocalThenUseCloud:
                    try self.backupLocalFile(localURL: localURL)
                    try self.pull(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "冲突解决：备份后采用云端")
                }
                metadata.eventLog = self.mergeEvents(
                    current: metadata.eventLog,
                    newEvent: self.makeEvent(action: .conflictResolved, versionId: item.cloudVersion?.versionId, note: "冲突已手动解决")
                )
                try self.storage.saveMetadata(metadata, for: cloudURL)
                item.history = metadata.eventLog
                item.conflictState = nil
                item.lastErrorMessage = nil
                self.items[index] = item
                self.log(.info, category: "conflict.resolved", message: "Resolved conflict", item: item, metadata: [
                    "choice": "\(choice)"
                ])
                self.persistItems()
                self.publishSnapshot()
            } catch {
                item.status = .error
                item.lastErrorMessage = error.localizedDescription
                item.history = self.mergeEvents(
                    current: item.history,
                    newEvent: self.makeEvent(action: .error, versionId: item.cloudVersion?.versionId, note: "冲突处理失败：\(error.localizedDescription)")
                )
                self.items[index] = item
                self.log(.error, category: "conflict.resolve_failed", message: error.localizedDescription, item: item)
                self.persistItems()
                self.publishSnapshot()
            }
        }
    }

    func deleteCloudFile(cloudFileId: String) throws {
        try queue.sync {
            let linkedItemIndex = items.firstIndex(where: { $0.cloudFileId == cloudFileId })
            let linkedItem = linkedItemIndex.flatMap { items[$0] }
            let discovered = storage
                .discoverManagedMetadata(rootPath: settings.managedRootPath)
                .first(where: { $0.metadata.cloudFileId == cloudFileId })

            guard let cloudPath = linkedItem?.cloudFilePath ?? discovered?.metadata.cloudFilePath else {
                throw CoordinatorError.cloudMetadataNotFound
            }

            let cloudURL = URL(fileURLWithPath: cloudPath)
            var metadata = canonicalize(metadata: storage.loadMetadata(for: cloudURL, cloudFileId: cloudFileId).metadata)
            metadata.deletedAt = Date().filelayString
            metadata.deletedByDevice = currentDevice
            metadata.eventLog = mergeEvents(
                current: metadata.eventLog,
                newEvent: makeEvent(action: .deleted, versionId: metadata.cloudVersion?.versionId, note: "删除云端文件")
            )
            try storage.saveMetadata(metadata, for: cloudURL)

            if FileManager.default.fileExists(atPath: cloudURL.path) {
                try FileManager.default.removeItem(at: cloudURL)
            }

            if let linkedItemIndex {
                items.remove(at: linkedItemIndex)
            }

            log(.info, category: "item.deleted", message: "Deleted cloud file", cloudFileId: cloudFileId, localPath: linkedItem?.localPath, cloudPath: cloudURL.path)
            persistItems()
            publishSnapshot()
        }
    }

    private func runSyncCycle(trigger: String) {
        guard !items.isEmpty else {
            publishSnapshot()
            return
        }

        var index = 0
        while index < items.count {
            let countBefore = items.count
            syncItem(at: index, trigger: trigger)
            if items.count == countBefore {
                index += 1
            }
        }
        publishSnapshot()
    }

    private func syncItem(at index: Int, trigger: String) {
        guard items.indices.contains(index) else { return }

        var item = canonicalize(item: items[index])
        guard item.isEnabled else {
            item.status = .disabled
            items[index] = item
            return
        }

        if item.conflictState != nil {
            item.status = .conflict
            items[index] = item
            return
        }

        let localURL = URL(fileURLWithPath: item.localPath)
        let cloudURL = URL(fileURLWithPath: item.cloudFilePath)

        do {
            try validate(localURL: localURL, cloudURL: cloudURL)
            let loadedMetadata = storage.loadMetadata(for: cloudURL, cloudFileId: item.cloudFileId)
            var metadata = canonicalize(metadata: loadedMetadata.metadata)
            if metadata.deletedAt != nil {
                log(.info, category: "item.deleted_remote", message: "Observed remote deletion and removed local link", item: item)
                items.remove(at: index)
                persistItems()
                return
            }
            item.cloudVersion = metadata.cloudVersion
            item.deviceReceipts = metadata.deviceReceipts
            item.history = metadata.eventLog

            let localExists = FileManager.default.fileExists(atPath: localURL.path)
            let cloudExists = FileManager.default.fileExists(atPath: cloudURL.path)

            if !localExists && !cloudExists {
                throw CoordinatorError.bothFilesMissing
            }

            if localExists && !cloudExists {
                item.status = .uploading
                try push(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: trigger == "manual" ? "手动触发上传" : "检测到本地更新")
                items[index] = item
                persistItems()
                return
            }

            if !localExists && cloudExists {
                item.status = .downloading
                try pull(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "本地缺失，自动从云端恢复")
                items[index] = item
                persistItems()
                return
            }

            guard let localHash = fileHash(url: localURL),
                  let cloudHash = fileHash(url: cloudURL) else {
                throw CoordinatorError.hashFailed
            }

            if metadata.cloudVersion == nil {
                metadata.cloudVersion = CloudVersion(
                    versionId: makeVersionId(hash: cloudHash),
                    contentHash: cloudHash,
                    updatedAt: Date().filelayString,
                    updatedByDevice: currentDevice,
                    sourceFileMtime: fileMtime(url: cloudURL)?.filelayString ?? Date().filelayString
                )
            }

            if localHash == cloudHash {
                if let version = metadata.cloudVersion?.versionId {
                    updateReceipt(metadata: &metadata, versionId: version, localURL: localURL, status: .synced)
                    try storage.saveMetadata(metadata, for: cloudURL)
                    item.lastSeenCloudVersionId = version
                }
                item.lastKnownLocalHash = localHash
                item.cloudVersion = metadata.cloudVersion
                item.deviceReceipts = metadata.deviceReceipts
                item.history = metadata.eventLog
                item.status = .synced
                item.lastErrorMessage = nil
                items[index] = item
                persistItems()
                return
            }

            let cloudVersionId = metadata.cloudVersion?.versionId
            let cloudNewForDevice = cloudVersionId != nil && cloudVersionId != item.lastSeenCloudVersionId
            let localChanged = item.lastKnownLocalHash != nil && localHash != item.lastKnownLocalHash
            let hasNoBaseline = item.lastKnownLocalHash == nil && item.lastSeenCloudVersionId == nil

            let decision: SyncDecision
            if hasNoBaseline {
                decision = .conflict
            } else if cloudNewForDevice && localChanged {
                decision = .conflict
            } else if cloudNewForDevice {
                decision = .pullCloudToLocal
            } else if localChanged {
                decision = .pushLocalToCloud
            } else {
                decision = fallbackDecision(localURL: localURL, cloudURL: cloudURL)
            }

            switch decision {
            case .none:
                item.status = .synced
            case .pushLocalToCloud:
                item.status = .uploading
                log(.info, category: "sync.push_requested", message: "Detected local change and preparing upload", item: item, trigger: trigger)
                try push(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "检测到本地变更")
            case .pullCloudToLocal:
                item.status = .downloading
                log(.info, category: "sync.pull_requested", message: "Detected cloud change and preparing local apply", item: item, trigger: trigger)
                try pull(item: &item, metadata: &metadata, localURL: localURL, cloudURL: cloudURL, note: "检测到云端新版本")
            case .conflict:
                item.status = .conflict
                item.conflictState = makeConflictState(
                    localURL: localURL,
                    cloudURL: cloudURL,
                    localHash: localHash,
                    cloudHash: cloudHash,
                    cloudVersionId: metadata.cloudVersion?.versionId
                )
                metadata.eventLog = mergeEvents(
                    current: metadata.eventLog,
                    newEvent: makeEvent(action: .conflictDetected, versionId: metadata.cloudVersion?.versionId, note: "检测到双端内容冲突")
                )
                try storage.saveMetadata(metadata, for: cloudURL)
                item.history = metadata.eventLog
                log(.warning, category: "sync.conflict", message: "Detected conflict between local and cloud content", item: item, trigger: trigger)
            }

            item.cloudVersion = metadata.cloudVersion
            item.deviceReceipts = metadata.deviceReceipts
            item.lastErrorMessage = nil
            items[index] = item
            persistItems()
        } catch {
            item.status = .error
            item.lastErrorMessage = error.localizedDescription
            item.history = mergeEvents(
                current: item.history,
                newEvent: makeEvent(action: .error, versionId: item.cloudVersion?.versionId, note: error.localizedDescription)
            )
            items[index] = item
            log(.error, category: "sync.error", message: error.localizedDescription, item: item, trigger: trigger)
            persistItems()
        }
    }

    private func push(item: inout SyncItem, metadata: inout CloudFileMetadata, localURL: URL, cloudURL: URL, note: String) throws {
        try storage.replaceFileAtomically(at: cloudURL, withContentsOf: localURL)

        guard let hash = fileHash(url: localURL) else {
            throw CoordinatorError.hashFailed
        }

        let versionId = makeVersionId(hash: hash)
        metadata.deletedAt = nil
        metadata.deletedByDevice = nil
        metadata.cloudVersion = CloudVersion(
            versionId: versionId,
            contentHash: hash,
            updatedAt: Date().filelayString,
            updatedByDevice: currentDevice,
            sourceFileMtime: fileMtime(url: localURL)?.filelayString ?? Date().filelayString
        )
        updateReceipt(metadata: &metadata, versionId: versionId, localURL: localURL, status: .synced)
        metadata.eventLog = mergeEvents(
            current: metadata.eventLog,
            newEvent: makeEvent(action: .upload, versionId: versionId, note: note)
        )
        try storage.saveMetadata(metadata, for: cloudURL)

        item.lastKnownLocalHash = hash
        item.lastSeenCloudVersionId = versionId
        item.conflictState = nil
        item.cloudVersion = metadata.cloudVersion
        item.deviceReceipts = metadata.deviceReceipts
        item.history = metadata.eventLog
        item.status = .synced
        item.lastErrorMessage = nil
        log(.info, category: "sync.push_completed", message: note, item: item, metadata: [
            "versionId": versionId
        ])
    }

    private func pull(item: inout SyncItem, metadata: inout CloudFileMetadata, localURL: URL, cloudURL: URL, note: String) throws {
        try storage.replaceFileAtomically(at: localURL, withContentsOf: cloudURL)

        guard let localHash = fileHash(url: localURL) else {
            throw CoordinatorError.hashFailed
        }

        if metadata.cloudVersion == nil {
            metadata.cloudVersion = CloudVersion(
                versionId: makeVersionId(hash: localHash),
                contentHash: localHash,
                updatedAt: Date().filelayString,
                updatedByDevice: currentDevice,
                sourceFileMtime: fileMtime(url: cloudURL)?.filelayString ?? Date().filelayString
            )
        }

        let versionId = metadata.cloudVersion?.versionId ?? makeVersionId(hash: localHash)
        metadata.deletedAt = nil
        metadata.deletedByDevice = nil
        updateReceipt(metadata: &metadata, versionId: versionId, localURL: localURL, status: .synced)
        metadata.eventLog = mergeEvents(
            current: metadata.eventLog,
            newEvent: makeEvent(action: .download, versionId: versionId, note: note)
        )
        try storage.saveMetadata(metadata, for: cloudURL)

        item.lastKnownLocalHash = localHash
        item.lastSeenCloudVersionId = versionId
        item.conflictState = nil
        item.cloudVersion = metadata.cloudVersion
        item.deviceReceipts = metadata.deviceReceipts
        item.history = metadata.eventLog
        item.status = .synced
        item.lastErrorMessage = nil
        log(.info, category: "sync.pull_completed", message: note, item: item, metadata: [
            "versionId": versionId
        ])
    }

    private func updateReceipt(metadata: inout CloudFileMetadata, versionId: String, localURL: URL, status: SyncItemStatus) {
        metadata.deviceReceipts[currentDevice.id] = DeviceReceipt(
            device: currentDevice,
            lastAppliedVersionId: versionId,
            lastAppliedAt: Date().filelayString,
            localFileMtimeAfterApply: fileMtime(url: localURL)?.filelayString ?? Date().filelayString,
            lastSyncStatus: status
        )
    }

    private func validate(localURL: URL, cloudURL: URL) throws {
        let managedRootPath = settings.managedRootPath
        if !cloudURL.path.hasPrefix(managedRootPath + "/") && cloudURL.path != managedRootPath {
            throw CoordinatorError.invalidManagedPath
        }

        var isDir = ObjCBool(false)
        let localDir = localURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: localDir.path, isDirectory: &isDir) || !isDir.boolValue {
            throw CoordinatorError.invalidLocalDirectory
        }

        let cloudDir = cloudURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cloudDir.path, isDirectory: &isDir) || !isDir.boolValue {
            try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        }
    }

    private func fallbackDecision(localURL: URL, cloudURL: URL) -> SyncDecision {
        guard let localDate = fileMtime(url: localURL),
              let cloudDate = fileMtime(url: cloudURL) else {
            return .none
        }
        if localDate == cloudDate {
            return .none
        }
        return localDate > cloudDate ? .pushLocalToCloud : .pullCloudToLocal
    }

    private func makeConflictState(localURL: URL, cloudURL: URL, localHash: String, cloudHash: String, cloudVersionId: String?) -> ConflictState {
        ConflictState(
            localHash: localHash,
            cloudHash: cloudHash,
            detectedAt: Date().filelayString,
            localPreview: filePreview(url: localURL),
            cloudPreview: filePreview(url: cloudURL),
            cloudVersionId: cloudVersionId
        )
    }

    private func canonicalize(item: SyncItem) -> SyncItem {
        var canonical = item
        canonical.cloudVersion = canonicalize(cloudVersion: item.cloudVersion)
        canonical.deviceReceipts = canonicalize(deviceReceipts: item.deviceReceipts)
        canonical.history = item.history.map(canonicalize(event:))
        return canonical
    }

    private func canonicalize(metadata: CloudFileMetadata) -> CloudFileMetadata {
        var canonical = metadata
        canonical.cloudVersion = canonicalize(cloudVersion: metadata.cloudVersion)
        canonical.deviceReceipts = canonicalize(deviceReceipts: metadata.deviceReceipts)
        canonical.eventLog = metadata.eventLog.map(canonicalize(event:))
        if let deletedByDevice = metadata.deletedByDevice {
            canonical.deletedByDevice = canonicalize(device: deletedByDevice)
        }
        return canonical
    }

    private func canonicalize(cloudVersion: CloudVersion?) -> CloudVersion? {
        guard var cloudVersion else { return nil }
        cloudVersion.updatedByDevice = canonicalize(device: cloudVersion.updatedByDevice)
        return cloudVersion
    }

    private func canonicalize(event: SyncEvent) -> SyncEvent {
        var event = event
        event.device = canonicalize(device: event.device)
        return event
    }

    private func canonicalize(deviceReceipts: [String: DeviceReceipt]) -> [String: DeviceReceipt] {
        var merged: [String: DeviceReceipt] = [:]

        for receipt in deviceReceipts.values {
            let canonicalDevice = canonicalize(device: receipt.device)
            var canonicalReceipt = receipt
            canonicalReceipt.device = canonicalDevice

            if let current = merged[canonicalDevice.id] {
                merged[canonicalDevice.id] = newerReceipt(current: current, incoming: canonicalReceipt)
            } else {
                merged[canonicalDevice.id] = canonicalReceipt
            }
        }

        return merged
    }

    private func canonicalize(device: DeviceInfo) -> DeviceInfo {
        if device.id == currentDevice.id {
            return currentDevice
        }
        if device.name == currentDevice.name {
            return currentDevice
        }
        return device
    }

    private func newerReceipt(current: DeviceReceipt, incoming: DeviceReceipt) -> DeviceReceipt {
        incoming.lastAppliedAt >= current.lastAppliedAt ? incoming : current
    }

    private func log(
        _ level: SyncLogLevel,
        category: String,
        message: String,
        item: SyncItem? = nil,
        trigger: String? = nil,
        cloudFileId: String? = nil,
        localPath: String? = nil,
        cloudPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        logger.log(
            SyncLogEntry(
                timestamp: Date().filelayString,
                level: level,
                category: category,
                message: message,
                trigger: trigger,
                device: currentDevice,
                itemID: item?.id,
                cloudFileId: cloudFileId ?? item?.cloudFileId,
                localPath: localPath ?? item?.localPath,
                cloudPath: cloudPath ?? item?.cloudFilePath,
                metadata: metadata
            )
        )
    }

    private func makeSnapshot() -> AppSnapshot {
        AppSnapshot(
            items: items,
            cloudFiles: buildCloudFiles(),
            settings: settings,
            aggregateStatus: aggregateStatus(),
            currentDevice: currentDevice,
            knownDevices: knownDevices()
        )
    }

    private func buildCloudFiles() -> [CloudFileRecord] {
        var records: [String: CloudFileRecord] = [:]

        for discovered in storage.discoverManagedMetadata(rootPath: settings.managedRootPath) {
            let metadata = canonicalize(metadata: discovered.metadata)
            guard metadata.deletedAt == nil else { continue }
            records[metadata.cloudFileId] = CloudFileRecord(
                cloudFileId: metadata.cloudFileId,
                cloudFilePath: metadata.cloudFilePath,
                displayName: URL(fileURLWithPath: metadata.cloudFilePath).lastPathComponent,
                localPath: nil,
                linkedItemID: nil,
                isLocallyLinked: false,
                status: nil,
                cloudVersion: metadata.cloudVersion,
                deviceReceipts: metadata.deviceReceipts,
                history: metadata.eventLog,
                conflictState: nil
            )
        }

        for item in items {
            let item = canonicalize(item: item)
            records[item.cloudFileId] = CloudFileRecord(
                cloudFileId: item.cloudFileId,
                cloudFilePath: item.cloudFilePath,
                displayName: item.displayName,
                localPath: item.localPath,
                linkedItemID: item.id,
                isLocallyLinked: true,
                status: item.status,
                cloudVersion: item.cloudVersion,
                deviceReceipts: item.deviceReceipts,
                history: item.history,
                conflictState: item.conflictState
            )
        }

        return Array(records.values).sorted { lhs, rhs in
            if lhs.isLocallyLinked != rhs.isLocallyLinked {
                return lhs.isLocallyLinked && !rhs.isLocallyLinked
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func publishSnapshot() {
        let snapshot = makeSnapshot()
        DispatchQueue.main.async { [onSnapshotChange] in
            onSnapshotChange?(snapshot)
        }
    }

    private func knownDevices() -> [DeviceInfo] {
        var devices: [String: DeviceInfo] = [currentDevice.id: currentDevice]
        for item in items {
            for receipt in item.deviceReceipts.values {
                devices[receipt.device.id] = receipt.device
            }
            if let device = item.cloudVersion?.updatedByDevice {
                devices[device.id] = device
            }
            for event in item.history {
                devices[event.device.id] = event.device
            }
        }
        return Array(devices.values).sorted { lhs, rhs in
            if lhs.id == currentDevice.id { return true }
            if rhs.id == currentDevice.id { return false }
            return lhs.name < rhs.name
        }
    }

    private func aggregateStatus() -> SyncStatus {
        if items.contains(where: { $0.status == .conflict }) {
            return .warning(settings.language == .en ? "Pending conflicts" : "存在待处理冲突")
        }
        if items.contains(where: { $0.status == .uploading || $0.status == .downloading }) {
            return .syncing
        }
        if items.contains(where: { $0.status == .error }) {
            return .error(settings.language == .en ? "Synchronization errors" : "存在同步错误")
        }
        return .idle
    }

    private func persistItems() {
        items = items.map(canonicalize(item:))
        storage.saveSyncItems(items)
        rebuildWatchersLocked()
    }

    private func makeEvent(action: SyncEventAction, versionId: String?, note: String?) -> SyncEvent {
        SyncEvent(
            id: UUID().uuidString,
            timestamp: Date().filelayString,
            device: currentDevice,
            action: action,
            versionId: versionId,
            note: note
        )
    }

    private func mergeEvents(current: [SyncEvent], newEvent: SyncEvent) -> [SyncEvent] {
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        merged[newEvent.id] = newEvent
        return Array(merged.values).sorted { $0.timestamp > $1.timestamp }.prefix(200).map { $0 }
    }

    private func fileHash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        let chunkSize = 64 * 1024

        while true {
            let data: Data
            do {
                data = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                return nil
            }
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileMtime(url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func filePreview(url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "无法读取文件内容" }
        if let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(400))
        }
        return "(二进制内容已省略)"
    }

    private func makeVersionId(hash _: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter.string(from: Date())
    }

    private func backupLocalFile(localURL: URL) throws {
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let ext = localURL.pathExtension
        let base = localURL.deletingPathExtension().lastPathComponent
        let suffix = Int(Date().timeIntervalSince1970)
        let backupName: String
        if ext.isEmpty {
            backupName = "\(base).conflict-backup-\(suffix)"
        } else {
            backupName = "\(base).conflict-backup-\(suffix).\(ext)"
        }
        let backupURL = localURL.deletingLastPathComponent().appendingPathComponent(backupName)
        try FileManager.default.copyItem(at: localURL, to: backupURL)
    }

    private func sanitizeRelativeFolder(_ folder: String) -> String {
        folder
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .map(String.init)
            .joined(separator: "/")
    }

    private func currentAppBundlePath() -> String? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return nil }
        return bundleURL.path
    }

    private func findRepositoryScript(named name: String) -> URL? {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let direct = currentDirectory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: direct.path) {
            return direct
        }

        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidate = executableDirectory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private func runProcess(executableURL: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return nil
            }
            return "已保存设置，但登录项脚本执行失败。"
        } catch {
            return "已保存设置，但无法执行登录项脚本：\(error.localizedDescription)"
        }
    }
}

private enum SyncDecision {
    case none
    case pushLocalToCloud
    case pullCloudToLocal
    case conflict
}

enum CoordinatorError: LocalizedError {
    case invalidLocalFile
    case invalidLocalDirectory
    case invalidManagedPath
    case cloudMetadataNotFound
    case bothFilesMissing
    case hashFailed
    case localFileAlreadyManaged
    case cloudFileAlreadyManaged
    case cloudTargetAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidLocalFile:
            return "本地文件不存在或不可读。"
        case .invalidLocalDirectory:
            return "本地文件所在目录不存在。"
        case .invalidManagedPath:
            return "iCloud 目标路径不在 Filelay 管理区内。"
        case .cloudMetadataNotFound:
            return "找不到对应的云端同步元数据。"
        case .bothFilesMissing:
            return "本地和云端文件都不存在。"
        case .hashFailed:
            return "无法计算文件哈希。"
        case .localFileAlreadyManaged:
            return "这个本地文件已经在同步列表中。"
        case .cloudFileAlreadyManaged:
            return "这个云端文件已经与本机条目建立关联。"
        case .cloudTargetAlreadyExists:
            return "目标目录里已经有同名云端文件。请换一个名称、换一个目录，或改用“关联已有云端文件”。"
        }
    }
}
