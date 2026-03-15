import Foundation

enum CopyKey {
    case appName
    case cloudFiles
    case conflicts
    case history
    case settings
    case currentDevice
    case cloudFileCount(Int)
    case conflictCount(Int)
    case openApp
    case openConflicts
    case syncNow
    case quit
    case statusIdle
    case statusSyncing
    case statusWarning(String)
    case statusError(String)
    case filterAll
    case filterSynced
    case filterSyncing
    case filterUnlinked
    case filterConflict
    case searchCloudFiles
    case noCloudFiles
    case noCloudFilesMessage
    case noMatchingCloudFiles
    case noMatchingCloudFilesMessage
    case noConflicts
    case noConflictsMessage
    case cloudPath
    case localPath
    case notLinked
    case cloudVersion
    case lastUpdatedDevice
    case cloudUpdatedAt
    case pendingConflict
    case localHash
    case cloudHash
    case detectedAt
    case localPreview
    case cloudPreview
    case deviceSyncStatus
    case noReceipts
    case syncHistory
    case noHistory
    case deleteCloudFile
    case deleteCloudFileTitle
    case deleteCloudFileMessage
    case delete
    case keepLocal
    case useCloud
    case backupThenUseCloud
    case managedRoot
    case syncBehavior
    case syncInterval
    case autoHints
    case launchAtLogin
    case language
    case devices
    case currentMachine
    case addCloudFile
    case chooseLocalFile
    case recheckHints
    case detectedExistingCloudFile
    case useThisExistingFile
    case ignore
    case uploadSettings
    case cloudRoot
    case subfolderOptional
    case browseExistingFolder
    case chooseExistingCloudFile
    case refresh
    case refreshList
    case cancel
    case addAndUpload
    case createLink
    case localFileMissing
    case localFileMissingMessage
    case missingCloudTarget
    case missingCloudTargetMessage
    case addFailed
    case invalidDirectory
    case invalidDirectoryMessage
    case launchAtLoginTitle
    case selectLocalFilePanel
    case selectManagedFolderPanel
    case uploadNewFile
    case linkExistingFile
    case linkedBadge
    case unlinkedBadge
    case syncStatusLabel
    case cloudFilesCountValue(Int)
    case devicesCountValue(Int)
    case linkedLocalFile
    case unlinkedLocalFile
    case showInFinder
    case dragLocalFileTitle
    case dragLocalFileMessage
}

enum L10n {
    static func text(_ key: CopyKey, _ language: AppLanguage) -> String {
        switch (language, key) {
        case (.zhHans, .appName): return "Filelay"
        case (.en, .appName): return "Filelay"

        case (.zhHans, .cloudFiles): return "云端文件"
        case (.en, .cloudFiles): return "Cloud Files"
        case (.zhHans, .conflicts): return "冲突处理"
        case (.en, .conflicts): return "Conflicts"
        case (.zhHans, .history): return "同步历史"
        case (.en, .history): return "History"
        case (.zhHans, .settings): return "设置"
        case (.en, .settings): return "Settings"
        case (.zhHans, .currentDevice): return "当前设备"
        case (.en, .currentDevice): return "Current Device"
        case (.zhHans, .cloudFileCount(let count)): return "\(count) 个云端文件"
        case (.en, .cloudFileCount(let count)): return "\(count) cloud files"
        case (.zhHans, .conflictCount(let count)): return "\(count) 个待处理冲突"
        case (.en, .conflictCount(let count)): return "\(count) pending conflicts"
        case (.zhHans, .openApp): return "打开 Filelay"
        case (.en, .openApp): return "Open Filelay"
        case (.zhHans, .openConflicts): return "查看冲突"
        case (.en, .openConflicts): return "Open Conflicts"
        case (.zhHans, .syncNow): return "立即同步"
        case (.en, .syncNow): return "Sync Now"
        case (.zhHans, .quit): return "退出"
        case (.en, .quit): return "Quit"
        case (.zhHans, .statusIdle): return "状态：空闲"
        case (.en, .statusIdle): return "Status: Idle"
        case (.zhHans, .statusSyncing): return "状态：同步中"
        case (.en, .statusSyncing): return "Status: Syncing"
        case (.zhHans, .statusWarning(let message)): return "状态：注意 - \(message)"
        case (.en, .statusWarning(let message)): return "Status: Warning - \(message)"
        case (.zhHans, .statusError(let message)): return "状态：错误 - \(message)"
        case (.en, .statusError(let message)): return "Status: Error - \(message)"
        case (.zhHans, .filterAll): return "全部"
        case (.en, .filterAll): return "All"
        case (.zhHans, .filterSynced): return "已同步"
        case (.en, .filterSynced): return "Synced"
        case (.zhHans, .filterSyncing): return "同步中"
        case (.en, .filterSyncing): return "Syncing"
        case (.zhHans, .filterUnlinked): return "未关联"
        case (.en, .filterUnlinked): return "Unlinked"
        case (.zhHans, .filterConflict): return "冲突"
        case (.en, .filterConflict): return "Conflict"
        case (.zhHans, .searchCloudFiles): return "搜索云端文件"
        case (.en, .searchCloudFiles): return "Search cloud files"
        case (.zhHans, .noCloudFiles): return "还没有云端文件"
        case (.en, .noCloudFiles): return "No Cloud Files Yet"
        case (.zhHans, .noCloudFilesMessage): return "先选择一个本地文件，再决定上传为新云端文件还是关联已有云端文件。"
        case (.en, .noCloudFilesMessage): return "Choose a local file first, then decide whether to upload it as a new cloud file or link it to an existing one."
        case (.zhHans, .noMatchingCloudFiles): return "当前分类下没有文件"
        case (.en, .noMatchingCloudFiles): return "No Files in This Filter"
        case (.zhHans, .noMatchingCloudFilesMessage): return "切换筛选条件或搜索关键词后再试。"
        case (.en, .noMatchingCloudFilesMessage): return "Try another filter or search term."
        case (.zhHans, .noConflicts): return "暂无冲突"
        case (.en, .noConflicts): return "No Conflicts"
        case (.zhHans, .noConflictsMessage): return "当前所有已关联到本地的云端文件都没有待处理冲突。"
        case (.en, .noConflictsMessage): return "All locally linked cloud files are currently conflict free."
        case (.zhHans, .cloudPath): return "云端路径"
        case (.en, .cloudPath): return "Cloud Path"
        case (.zhHans, .localPath): return "本地路径"
        case (.en, .localPath): return "Local Path"
        case (.zhHans, .notLinked): return "未关联本地"
        case (.en, .notLinked): return "Not Linked Locally"
        case (.zhHans, .cloudVersion): return "云端版本"
        case (.en, .cloudVersion): return "Cloud Version"
        case (.zhHans, .lastUpdatedDevice): return "最近更新设备"
        case (.en, .lastUpdatedDevice): return "Last Updated By"
        case (.zhHans, .cloudUpdatedAt): return "云端更新时间"
        case (.en, .cloudUpdatedAt): return "Cloud Updated At"
        case (.zhHans, .pendingConflict): return "待处理冲突"
        case (.en, .pendingConflict): return "Pending Conflict"
        case (.zhHans, .localHash): return "本地哈希"
        case (.en, .localHash): return "Local Hash"
        case (.zhHans, .cloudHash): return "云端哈希"
        case (.en, .cloudHash): return "Cloud Hash"
        case (.zhHans, .detectedAt): return "检测时间"
        case (.en, .detectedAt): return "Detected At"
        case (.zhHans, .localPreview): return "本地预览"
        case (.en, .localPreview): return "Local Preview"
        case (.zhHans, .cloudPreview): return "云端预览"
        case (.en, .cloudPreview): return "Cloud Preview"
        case (.zhHans, .deviceSyncStatus): return "设备同步状态"
        case (.en, .deviceSyncStatus): return "Device Sync Status"
        case (.zhHans, .noReceipts): return "暂无设备回执"
        case (.en, .noReceipts): return "No device receipts yet"
        case (.zhHans, .syncHistory): return "同步历史"
        case (.en, .syncHistory): return "Sync History"
        case (.zhHans, .noHistory): return "暂无历史记录"
        case (.en, .noHistory): return "No history yet"
        case (.zhHans, .deleteCloudFile): return "删除云端文件"
        case (.en, .deleteCloudFile): return "Delete Cloud File"
        case (.zhHans, .deleteCloudFileTitle): return "确认删除这个云端文件？"
        case (.en, .deleteCloudFileTitle): return "Delete this cloud file?"
        case (.zhHans, .deleteCloudFileMessage): return "这会删除 iCloud 中的文件，并让已关联的设备停止同步这个文件。本地文件不会被删除。"
        case (.en, .deleteCloudFileMessage): return "This deletes the file from iCloud and stops syncing it on linked devices. The local file is not deleted."
        case (.zhHans, .delete): return "删除"
        case (.en, .delete): return "Delete"
        case (.zhHans, .keepLocal): return "保留本地"
        case (.en, .keepLocal): return "Keep Local"
        case (.zhHans, .useCloud): return "采用云端"
        case (.en, .useCloud): return "Use Cloud"
        case (.zhHans, .backupThenUseCloud): return "备份后采用云端"
        case (.en, .backupThenUseCloud): return "Backup Then Use Cloud"
        case (.zhHans, .managedRoot): return "Filelay 管理区"
        case (.en, .managedRoot): return "Filelay Managed Root"
        case (.zhHans, .syncBehavior): return "同步行为"
        case (.en, .syncBehavior): return "Sync Behavior"
        case (.zhHans, .syncInterval): return "同步检查间隔"
        case (.en, .syncInterval): return "Sync Interval"
        case (.zhHans, .autoHints): return "自动识别已有云端文件"
        case (.en, .autoHints): return "Suggest Existing Cloud Files"
        case (.zhHans, .launchAtLogin): return "开机自动启动"
        case (.en, .launchAtLogin): return "Launch At Login"
        case (.zhHans, .language): return "语言"
        case (.en, .language): return "Language"
        case (.zhHans, .devices): return "设备列表"
        case (.en, .devices): return "Devices"
        case (.zhHans, .currentMachine): return "本机"
        case (.en, .currentMachine): return "This Mac"
        case (.zhHans, .addCloudFile): return "添加云端文件"
        case (.en, .addCloudFile): return "Add Cloud File"
        case (.zhHans, .chooseLocalFile): return "选择本地文件"
        case (.en, .chooseLocalFile): return "Choose Local File"
        case (.zhHans, .recheckHints): return "重新识别"
        case (.en, .recheckHints): return "Refresh Suggestions"
        case (.zhHans, .detectedExistingCloudFile): return "发现可能已存在的云端文件"
        case (.en, .detectedExistingCloudFile): return "Possible Existing Cloud Files"
        case (.zhHans, .useThisExistingFile): return "关联这个文件"
        case (.en, .useThisExistingFile): return "Link This File"
        case (.zhHans, .ignore): return "忽略"
        case (.en, .ignore): return "Ignore"
        case (.zhHans, .uploadSettings): return "上传设置"
        case (.en, .uploadSettings): return "Upload Settings"
        case (.zhHans, .cloudRoot): return "云端根目录"
        case (.en, .cloudRoot): return "Cloud Root"
        case (.zhHans, .subfolderOptional): return "子目录（可留空）"
        case (.en, .subfolderOptional): return "Subfolder (optional)"
        case (.zhHans, .browseExistingFolder): return "浏览现有目录…"
        case (.en, .browseExistingFolder): return "Browse Existing Folder…"
        case (.zhHans, .chooseExistingCloudFile): return "选择已有云端文件"
        case (.en, .chooseExistingCloudFile): return "Choose Existing Cloud File"
        case (.zhHans, .refresh): return "刷新"
        case (.en, .refresh): return "Refresh"
        case (.zhHans, .refreshList): return "刷新列表"
        case (.en, .refreshList): return "Refresh List"
        case (.zhHans, .cancel): return "取消"
        case (.en, .cancel): return "Cancel"
        case (.zhHans, .addAndUpload): return "添加并上传"
        case (.en, .addAndUpload): return "Add and Upload"
        case (.zhHans, .createLink): return "建立关联"
        case (.en, .createLink): return "Create Link"
        case (.zhHans, .localFileMissing): return "缺少本地文件"
        case (.en, .localFileMissing): return "Missing Local File"
        case (.zhHans, .localFileMissingMessage): return "请先选择一个本地文件。"
        case (.en, .localFileMissingMessage): return "Choose a local file first."
        case (.zhHans, .missingCloudTarget): return "缺少云端目标"
        case (.en, .missingCloudTarget): return "Missing Cloud Target"
        case (.zhHans, .missingCloudTargetMessage): return "请先选择要关联的已有云端文件。"
        case (.en, .missingCloudTargetMessage): return "Choose an existing cloud file to link."
        case (.zhHans, .addFailed): return "添加失败"
        case (.en, .addFailed): return "Add Failed"
        case (.zhHans, .invalidDirectory): return "目录无效"
        case (.en, .invalidDirectory): return "Invalid Directory"
        case (.zhHans, .invalidDirectoryMessage): return "目标目录必须位于 Filelay 管理区内。"
        case (.en, .invalidDirectoryMessage): return "The selected directory must stay inside the Filelay managed root."
        case (.zhHans, .launchAtLoginTitle): return "开机自启"
        case (.en, .launchAtLoginTitle): return "Launch At Login"
        case (.zhHans, .selectLocalFilePanel): return "选择要同步的本地文件"
        case (.en, .selectLocalFilePanel): return "Choose a local file to sync"
        case (.zhHans, .selectManagedFolderPanel): return "选择 Filelay 管理区内的目标目录"
        case (.en, .selectManagedFolderPanel): return "Choose a target folder inside the Filelay managed root"
        case (.zhHans, .uploadNewFile): return "新建云端文件"
        case (.en, .uploadNewFile): return "Create New Cloud File"
        case (.zhHans, .linkExistingFile): return "关联已有云端文件"
        case (.en, .linkExistingFile): return "Link Existing Cloud File"
        case (.zhHans, .linkedBadge): return "已关联"
        case (.en, .linkedBadge): return "Linked"
        case (.zhHans, .unlinkedBadge): return "未关联"
        case (.en, .unlinkedBadge): return "Unlinked"
        case (.zhHans, .syncStatusLabel): return "同步状态"
        case (.en, .syncStatusLabel): return "Sync Status"
        case (.zhHans, .cloudFilesCountValue(let count)): return "云端文件 \(count)"
        case (.en, .cloudFilesCountValue(let count)): return "Cloud files \(count)"
        case (.zhHans, .devicesCountValue(let count)): return "设备 \(count)"
        case (.en, .devicesCountValue(let count)): return "Devices \(count)"
        case (.zhHans, .linkedLocalFile): return "已关联本地"
        case (.en, .linkedLocalFile): return "Linked Locally"
        case (.zhHans, .unlinkedLocalFile): return "未关联本地"
        case (.en, .unlinkedLocalFile): return "Not Linked Locally"
        case (.zhHans, .showInFinder): return "在 Finder 中查看"
        case (.en, .showInFinder): return "Show in Finder"
        case (.zhHans, .dragLocalFileTitle): return "拖拽文件到这里"
        case (.en, .dragLocalFileTitle): return "Drop a file here"
        case (.zhHans, .dragLocalFileMessage): return "或点击选择一个本地文件"
        case (.en, .dragLocalFileMessage): return "or click to choose a local file"
        }
    }

    static func statusTitle(_ status: SyncItemStatus, _ language: AppLanguage) -> String {
        switch status {
        case .synced:
            return language == .en ? "Synced" : "已同步"
        case .uploading:
            return language == .en ? "Uploading" : "上传中"
        case .downloading:
            return language == .en ? "Downloading" : "下载中"
        case .conflict:
            return language == .en ? "Conflict" : "冲突"
        case .pending:
            return language == .en ? "Queued" : "等待同步"
        case .error:
            return language == .en ? "Error" : "错误"
        case .disabled:
            return language == .en ? "Disabled" : "已停用"
        }
    }

    static func sectionTitle(_ section: AppSection, _ language: AppLanguage) -> String {
        switch section {
        case .files:
            return text(.cloudFiles, language)
        case .conflicts:
            return text(.conflicts, language)
        case .history:
            return text(.history, language)
        case .settings:
            return text(.settings, language)
        }
    }

    static func eventActionTitle(_ action: SyncEventAction, _ language: AppLanguage) -> String {
        switch action {
        case .added:
            return language == .en ? "Added" : "添加文件"
        case .linked:
            return language == .en ? "Linked" : "建立关联"
        case .upload:
            return language == .en ? "Uploaded" : "上传到云端"
        case .download:
            return language == .en ? "Downloaded" : "从云端应用"
        case .deleted:
            return language == .en ? "Deleted" : "删除云端文件"
        case .conflictDetected:
            return language == .en ? "Conflict Detected" : "检测到冲突"
        case .conflictResolved:
            return language == .en ? "Conflict Resolved" : "冲突已解决"
        case .error:
            return language == .en ? "Error" : "同步错误"
        }
    }

    static func modeTitle(_ mode: AddFileMode, _ language: AppLanguage) -> String {
        switch mode {
        case .upload:
            return text(.uploadNewFile, language)
        case .linkExisting:
            return text(.linkExistingFile, language)
        }
    }

    static func menuTitle(_ status: SyncStatus, _ language: AppLanguage) -> String {
        switch status {
        case .idle:
            return text(.statusIdle, language)
        case .syncing:
            return text(.statusSyncing, language)
        case .warning(let message):
            return text(.statusWarning(message), language)
        case .error(let message):
            return text(.statusError(message), language)
        }
    }
}
