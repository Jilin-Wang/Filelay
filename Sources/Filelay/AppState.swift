import AppKit
import SwiftUI

struct HistoryRecord: Identifiable {
    var id: String { event.id }
    var itemID: String
    var itemName: String
    var event: SyncEvent
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var items: [SyncItem] = []
    @Published private(set) var cloudFiles: [CloudFileRecord] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var aggregateStatus: SyncStatus = .idle
    @Published private(set) var currentDevice: DeviceInfo
    @Published private(set) var knownDevices: [DeviceInfo] = []

    @Published var selectedSection: AppSection = .files
    @Published var selectedCloudFileID: String?
    @Published var isAddSheetPresented = false
    @Published var addDraft = AddFileDraft()
    @Published var alertMessage: AlertMessage?
    @Published var pendingDeletion: CloudFileRecord?

    private let coordinator: SyncCoordinator

    var onStateChange: ((AppStore) -> Void)?

    init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
        let snapshot = coordinator.snapshot()
        self.settings = snapshot.settings
        self.currentDevice = snapshot.currentDevice
        apply(snapshot: snapshot)

        coordinator.onSnapshotChange = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.apply(snapshot: snapshot)
            }
        }
    }

    var selectedCloudFile: CloudFileRecord? {
        guard let selectedCloudFileID else { return cloudFiles.first }
        return cloudFiles.first(where: { $0.cloudFileId == selectedCloudFileID }) ?? cloudFiles.first
    }

    var conflictItems: [SyncItem] {
        items.filter { $0.status == .conflict }
    }

    var historyRecords: [HistoryRecord] {
        cloudFiles
            .flatMap { file in
                file.history.map { HistoryRecord(itemID: file.linkedItemID ?? file.cloudFileId, itemName: file.displayName, event: $0) }
            }
            .sorted { $0.event.timestamp > $1.event.timestamp }
    }

    var managedRootName: String {
        URL(fileURLWithPath: settings.managedRootPath).lastPathComponent
    }

    func start() {
        coordinator.start()
    }

    func openFilesSection() {
        selectedSection = .files
    }

    func openConflictsSection() {
        selectedSection = .conflicts
    }

    func triggerManualSync() {
        coordinator.triggerManualSync()
    }

    func presentAddSheet() {
        addDraft = AddFileDraft()
        addDraft.availableTargets = coordinator.allLinkTargets()
        isAddSheetPresented = true
    }

    func dismissAddSheet() {
        isAddSheetPresented = false
        addDraft = AddFileDraft()
    }

    func chooseLocalFileForAdd() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.selectLocalFilePanel, settings.language)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setLocalFilePathForAdd(url.path)
        }
    }

    func setLocalFilePathForAdd(_ path: String) {
        addDraft.localPath = path
        if addDraft.uploadRelativeFolder.isEmpty {
            addDraft.uploadRelativeFolder = ""
        }
        refreshAddDraftDiscovery()
    }

    func chooseManagedFolderForAdd() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.selectManagedFolderPanel, settings.language)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.cloudFilesRootPath)
        if panel.runModal() == .OK, let url = panel.url {
            let rootURL = URL(fileURLWithPath: settings.cloudFilesRootPath)
            guard url.path.hasPrefix(rootURL.path) else {
                alertMessage = AlertMessage(
                    title: L10n.text(.invalidDirectory, settings.language),
                    message: L10n.text(.invalidDirectoryMessage, settings.language)
                )
                return
            }
            let relative = String(url.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            addDraft.uploadRelativeFolder = relative
        }
    }

    func refreshAvailableTargets() {
        let targets = coordinator.allLinkTargets()
        addDraft.availableTargets = mergeTargets(primary: addDraft.suggestions, secondary: targets)
    }

    func refreshAddDraftDiscovery() {
        let suggestions = coordinator
            .discoveryCandidates(for: addDraft.localPath)
            .filter { !addDraft.ignoredSuggestionIDs.contains($0.id) }
        addDraft.suggestions = suggestions
        addDraft.availableTargets = mergeTargets(primary: suggestions, secondary: coordinator.allLinkTargets())
        if let firstSuggestion = suggestions.first, addDraft.selectedTargetID == nil {
            addDraft.selectedTargetID = firstSuggestion.cloudFileId
        }
    }

    func ignoreSuggestion(_ candidate: DiscoveryCandidate) {
        addDraft.ignoredSuggestionIDs.insert(candidate.id)
        addDraft.suggestions.removeAll { $0.id == candidate.id }
        addDraft.availableTargets = mergeTargets(primary: addDraft.suggestions, secondary: coordinator.allLinkTargets())
    }

    func useSuggestion(_ candidate: DiscoveryCandidate) {
        addDraft.mode = .linkExisting
        addDraft.selectedTargetID = candidate.cloudFileId
        addDraft.availableTargets = mergeTargets(primary: addDraft.suggestions, secondary: coordinator.allLinkTargets())
    }

    func selectLinkTarget(_ id: String) {
        addDraft.selectedTargetID = id
    }

    func updateAddMode(_ mode: AddFileMode) {
        addDraft.mode = mode
    }

    func updateUploadRelativeFolder(_ value: String) {
        addDraft.uploadRelativeFolder = value
    }

    func updateSyncInterval(_ seconds: Int) {
        coordinator.updateSyncInterval(seconds)
    }

    func updateAssociationHintsEnabled(_ enabled: Bool) {
        coordinator.updateAssociationHintsEnabled(enabled)
    }

    func updateLanguage(_ language: AppLanguage) {
        coordinator.updateLanguage(language)
    }

    func updateLaunchAtLoginEnabled(_ enabled: Bool) {
        if let warning = coordinator.updateLaunchAtLoginEnabled(enabled) {
            alertMessage = AlertMessage(title: L10n.text(.launchAtLoginTitle, settings.language), message: warning)
        }
    }

    func submitAddDraft() {
        guard !addDraft.localPath.isEmpty else {
            alertMessage = AlertMessage(
                title: L10n.text(.localFileMissing, settings.language),
                message: L10n.text(.localFileMissingMessage, settings.language)
            )
            return
        }

        do {
            switch addDraft.mode {
            case .upload:
                try coordinator.addUploadItem(localPath: addDraft.localPath, relativeFolder: addDraft.uploadRelativeFolder)
            case .linkExisting:
                guard let selectedTargetID = addDraft.selectedTargetID else {
                    alertMessage = AlertMessage(
                        title: L10n.text(.missingCloudTarget, settings.language),
                        message: L10n.text(.missingCloudTargetMessage, settings.language)
                    )
                    return
                }
                try coordinator.linkExistingItem(localPath: addDraft.localPath, cloudFileId: selectedTargetID)
            }
            dismissAddSheet()
        } catch {
            alertMessage = AlertMessage(
                title: L10n.text(.addFailed, settings.language),
                message: error.filelayLocalizedDescription(language: settings.language)
            )
        }
    }

    func resolveConflict(itemID: String, choice: ConflictResolutionChoice) {
        coordinator.resolveConflict(itemID: itemID, choice: choice)
    }

    func requestDeleteCloudFile(_ file: CloudFileRecord) {
        pendingDeletion = file
    }

    func cancelDeleteCloudFile() {
        pendingDeletion = nil
    }

    func confirmDeleteCloudFile() {
        guard let pendingDeletion else { return }
        do {
            try coordinator.deleteCloudFile(cloudFileId: pendingDeletion.cloudFileId)
            self.pendingDeletion = nil
        } catch {
            alertMessage = AlertMessage(
                title: L10n.text(.deleteCloudFile, settings.language),
                message: error.filelayLocalizedDescription(language: settings.language)
            )
        }
    }

    func revealLocalFileInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func apply(snapshot: AppSnapshot) {
        items = snapshot.items
        cloudFiles = snapshot.cloudFiles
        settings = snapshot.settings
        aggregateStatus = snapshot.aggregateStatus
        currentDevice = snapshot.currentDevice
        knownDevices = snapshot.knownDevices

        if selectedCloudFileID == nil || !cloudFiles.contains(where: { $0.cloudFileId == selectedCloudFileID }) {
            selectedCloudFileID = cloudFiles.first?.cloudFileId
        }

        onStateChange?(self)
    }

    private func mergeTargets(primary: [DiscoveryCandidate], secondary: [DiscoveryCandidate]) -> [DiscoveryCandidate] {
        var map = Dictionary(uniqueKeysWithValues: secondary.map { ($0.id, $0) })
        for candidate in primary {
            map[candidate.id] = candidate
        }
        return Array(map.values).sorted { lhs, rhs in
            if confidenceRank(lhs.confidence) != confidenceRank(rhs.confidence) {
                return confidenceRank(lhs.confidence) < confidenceRank(rhs.confidence)
            }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
    }

    private func confidenceRank(_ confidence: DiscoveryCandidate.Confidence) -> Int {
        switch confidence {
        case .exactHash:
            return 0
        case .uniqueName:
            return 1
        case .discovered:
            return 2
        }
    }
}
