import SwiftUI
import UniformTypeIdentifiers

private enum AppChromeColor {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.035)
    static let subtleFillStrong = Color.primary.opacity(0.055)
    static let border = Color.primary.opacity(0.08)
    static let borderStrong = Color.primary.opacity(0.14)
    static let shadow = Color.black.opacity(0.12)
}

struct AppRootView: View {
    @ObservedObject var store: AppStore

    private var language: AppLanguage { store.settings.language }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store, language: language)
                .frame(width: 192)
                .background(AppChromeColor.sidebarBackground)
            Divider()
            Group {
                switch store.selectedSection {
                case .files:
                    CloudFilesPage(store: store, language: language)
                case .conflicts:
                    ConflictsPage(store: store, language: language)
                case .history:
                    HistoryPage(store: store, language: language)
                case .settings:
                    SettingsPage(store: store, language: language)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1120, minHeight: 720)
        .background(AppChromeColor.windowBackground)
        .navigationTitle(L10n.text(.appName, language))
        .sheet(isPresented: $store.isAddSheetPresented) {
            AddFileSheet(store: store, language: language)
        }
        .alert(
            store.alertMessage?.title ?? "",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            ),
            presenting: store.alertMessage
        ) { _ in
            Button("OK", role: .cancel) {
                store.alertMessage = nil
            }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            L10n.text(.deleteCloudFileTitle, language),
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.cancelDeleteCloudFile() } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.text(.delete, language), role: .destructive) {
                store.confirmDeleteCloudFile()
            }
            Button(L10n.text(.cancel, language), role: .cancel) {
                store.cancelDeleteCloudFile()
            }
        } message: {
            Text(L10n.text(.deleteCloudFileMessage, language))
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.appName, language))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.text(.cloudFileCount(store.cloudFiles.count), language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { section in
                    SidebarItemButton(
                        title: L10n.sectionTitle(section, language),
                        systemImage: iconName(for: section),
                        isSelected: store.selectedSection == section,
                        badgeCount: badgeCount(for: section)
                    ) {
                        store.selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 20)
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text(.currentDevice, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.currentDevice.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                StatusSummaryView(
                    status: store.aggregateStatus,
                    cloudFileCount: store.cloudFiles.count,
                    conflictCount: store.conflictItems.count,
                    language: language
                )
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppChromeColor.sidebarBackground)
    }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .files:
            return store.cloudFiles.count
        case .conflicts:
            return store.conflictItems.count
        case .history:
            return min(store.historyRecords.count, 99)
        case .settings:
            return 0
        }
    }

    private func iconName(for section: AppSection) -> String {
        switch section {
        case .files:
            return "icloud"
        case .conflicts:
            return "exclamationmark.triangle"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

private struct SidebarItemButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.accentColor.opacity(0.12) : AppChromeColor.subtleFillStrong)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        if isHovering {
            return AppChromeColor.subtleFillStrong
        }
        return Color.clear
    }
}

private struct StatusSummaryView: View {
    let status: SyncStatus
    let cloudFileCount: Int
    let conflictCount: Int
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.menuTitle(status, language).replacingOccurrences(of: language == .en ? "Status: " : "状态：", with: ""))
                .font(.caption)
                .foregroundStyle(statusColor(status))
            Text(L10n.text(.cloudFileCount(cloudFileCount), language))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if conflictCount > 0 {
                Text(L10n.text(.conflictCount(conflictCount), language))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct CloudFilesPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    @State private var search = ""
    @State private var filter: FileFilter = .all

    enum FileFilter: String, CaseIterable, Identifiable {
        case all
        case synced
        case syncing
        case unlinked
        case conflict

        var id: String { rawValue }
    }

    private var filteredFiles: [CloudFileRecord] {
        store.cloudFiles.filter { file in
            let matchesSearch = search.isEmpty
                || file.displayName.localizedCaseInsensitiveContains(search)
                || file.cloudFilePath.localizedCaseInsensitiveContains(search)
                || (file.localPath?.localizedCaseInsensitiveContains(search) ?? false)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .synced:
                matchesFilter = file.status == .synced
            case .syncing:
                matchesFilter = file.status == .pending || file.status == .uploading || file.status == .downloading
            case .unlinked:
                matchesFilter = !file.isLocallyLinked
            case .conflict:
                matchesFilter = file.status == .conflict
            }
            return matchesSearch && matchesFilter
        }
    }

    private var visibleSelectedFile: CloudFileRecord? {
        guard !filteredFiles.isEmpty else { return nil }
        if let selectedCloudFileID = store.selectedCloudFileID,
           let selected = filteredFiles.first(where: { $0.cloudFileId == selectedCloudFileID }) {
            return selected
        }
        return filteredFiles.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(.cloudFiles, language))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(L10n.text(.cloudFilesCountValue(store.cloudFiles.count), language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $filter) {
                        Text(L10n.text(.filterAll, language)).tag(FileFilter.all)
                        Text(L10n.text(.filterSynced, language)).tag(FileFilter.synced)
                        Text(L10n.text(.filterSyncing, language)).tag(FileFilter.syncing)
                        Text(L10n.text(.filterUnlinked, language)).tag(FileFilter.unlinked)
                        Text(L10n.text(.filterConflict, language)).tag(FileFilter.conflict)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 24)

                HStack(spacing: 10) {
                    Button {
                        store.presentAddSheet()
                    } label: {
                        Label(L10n.text(.addCloudFile, language), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.triggerManualSync()
                    } label: {
                        Label(L10n.text(.refresh, language), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if filteredFiles.isEmpty {
                EmptyStateView(
                    title: emptyStateTitle,
                    systemImage: emptyStateImage,
                    message: emptyStateMessage
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    CloudFileListPane(
                        store: store,
                        files: filteredFiles,
                        language: language,
                        searchQuery: $search
                    )
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 400)

                    if let file = visibleSelectedFile {
                        CloudFileDetailPanel(store: store, file: file, language: language)
                            .frame(minWidth: 500)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            selectFirstVisibleFile()
        }
        .onChange(of: filter) { _ in
            selectFirstVisibleFile()
        }
        .onChange(of: search) { _ in
            selectFirstVisibleFile()
        }
    }

    private var emptyStateTitle: String {
        if filter == .all && search.isEmpty {
            return L10n.text(.noCloudFiles, language)
        }
        return L10n.text(.noMatchingCloudFiles, language)
    }

    private var emptyStateMessage: String {
        if filter == .all && search.isEmpty {
            return L10n.text(.noCloudFilesMessage, language)
        }
        return L10n.text(.noMatchingCloudFilesMessage, language)
    }

    private var emptyStateImage: String {
        search.isEmpty && filter == .all ? "icloud.slash" : "magnifyingglass"
    }

    private func selectFirstVisibleFile() {
        store.selectedCloudFileID = filteredFiles.first?.cloudFileId
    }
}

private struct CloudFileListPane: View {
    @ObservedObject var store: AppStore
    let files: [CloudFileRecord]
    let language: AppLanguage
    @Binding var searchQuery: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                TextField(L10n.text(.searchCloudFiles, language), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(files) { file in
                        CloudFileRowView(
                            file: file,
                            language: language,
                            searchQuery: searchQuery,
                            isSelected: store.selectedCloudFileID == file.cloudFileId
                        ) {
                            store.selectedCloudFileID = file.cloudFileId
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppChromeColor.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppChromeColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.trailing, 16)
    }
}

private struct CloudFileRowView: View {
    let file: CloudFileRecord
    let language: AppLanguage
    let searchQuery: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: file.kind == .folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    highlightedText(file.displayName, query: searchQuery, font: .headline)
                        .lineLimit(1)
                        .help(file.displayName)
                    HStack(spacing: 8) {
                        if let version = file.cloudVersion?.versionId {
                            Text(displayVersion(version))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(L10n.text(.devicesCountValue(file.deviceReceipts.count), language))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    if let status = file.status {
                        StatusBadge(status: status, language: language)
                    } else {
                        Text(L10n.text(.unlinkedBadge, language))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(rowBorderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(file.displayName)
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.08)
        }
        if isHovering {
            return AppChromeColor.subtleFill
        }
        return AppChromeColor.cardBackground
    }

    private var rowBorderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.45)
        }
        if isHovering {
            return AppChromeColor.borderStrong
        }
        return AppChromeColor.border
    }
}

private struct AssociationBadge: View {
    let file: CloudFileRecord
    let language: AppLanguage

    var body: some View {
        Text(file.isLocallyLinked ? L10n.text(.linkedBadge, language) : L10n.text(.unlinkedBadge, language))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((file.isLocallyLinked ? Color.green : Color.orange).opacity(0.12))
            .foregroundStyle(file.isLocallyLinked ? Color.green : Color.orange)
            .clipShape(Capsule())
    }
}

private struct CloudFileDetailPanel: View {
    @ObservedObject var store: AppStore
    let file: CloudFileRecord
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label {
                                Text(file.displayName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            } icon: {
                                Image(systemName: file.kind == .folder ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            AssociationBadge(file: file, language: language)
                            Button(role: .destructive) {
                                store.requestDeleteCloudFile(file)
                            } label: {
                                Label(L10n.text(.deleteCloudFile, language), systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let linkedItemID = file.linkedItemID, file.status == .conflict {
                        ConflictButtons(itemID: linkedItemID, store: store, language: language)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 20) {
                    SectionCard(title: L10n.text(.syncStatusLabel, language)) {
                        DetailInfoRow(label: L10n.text(.cloudPath, language)) {
                            Text(file.cloudFilePath)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        DetailInfoRow(label: L10n.text(.localPath, language)) {
                            if let localPath = file.localPath, !localPath.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(localPath)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        store.revealLocalFileInFinder(localPath)
                                    } label: {
                                        Label(L10n.text(.showInFinder, language), systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            } else {
                                Text(L10n.text(.unlinkedLocalFile, language))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        DetailInfoRow(label: L10n.text(.syncStatusLabel, language)) {
                            if let status = file.status {
                                Text(L10n.statusTitle(status, language))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(L10n.text(.unlinkedBadge, language))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        DetailInfoRow(label: L10n.text(.cloudVersion, language)) {
                            Text(file.cloudVersion.map { displayVersion($0.versionId) } ?? "—")
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        DetailInfoRow(label: L10n.text(.lastUpdatedDevice, language)) {
                            Text(file.cloudVersion?.updatedByDevice.name ?? "—")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let updatedAt = file.cloudVersion?.updatedAt {
                            DetailInfoRow(label: L10n.text(.cloudUpdatedAt, language), showsDivider: false) {
                                Text(displayTime(updatedAt, language: language))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let conflict = file.conflictState {
                        SectionCard(title: L10n.text(.pendingConflict, language)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(L10n.text(.localHash, language))：\(conflict.localHash)")
                                    .font(.caption.monospaced())
                                Text("\(L10n.text(.cloudHash, language))：\(conflict.cloudHash)")
                                    .font(.caption.monospaced())
                                Text("\(L10n.text(.detectedAt, language))：\(displayTime(conflict.detectedAt, language: language))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .top, spacing: 12) {
                                    PreviewBlock(title: L10n.text(.localPreview, language), content: conflict.localPreview)
                                    PreviewBlock(title: L10n.text(.cloudPreview, language), content: conflict.cloudPreview)
                                }
                            }
                        }
                    }

                    SectionCard(title: L10n.text(.deviceSyncStatus, language)) {
                        if file.deviceReceipts.isEmpty {
                            Text(L10n.text(.noReceipts, language))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(file.deviceReceipts.values.sorted(by: { $0.device.name < $1.device.name }), id: \.device.id) { receipt in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(receipt.device.name)
                                                .fontWeight(.medium)
                                            Spacer()
                                            StatusBadge(status: receipt.lastSyncStatus, language: language)
                                        }
                                        Text(displayTime(receipt.lastAppliedAt, language: language))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppChromeColor.subtleFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    SectionCard(title: L10n.text(.syncHistory, language)) {
                        if file.history.isEmpty {
                            Text(L10n.text(.noHistory, language))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(file.history.prefix(20)) { event in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(L10n.eventActionTitle(event.action, language), systemImage: iconName(for: event.action))
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text(displayTime(event.timestamp, language: language))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(event.device.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let note = event.note, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppChromeColor.subtleFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(AppChromeColor.windowBackground)
    }
}

private struct DetailInfoRow<Content: View>: View {
    let label: String
    let showsDivider: Bool
    @ViewBuilder let content: Content

    init(label: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                content
            }
            if showsDivider {
                Divider()
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppChromeColor.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppChromeColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PreviewBlock: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ConflictButtons: View {
    let itemID: String
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        HStack {
            Button(L10n.text(.keepLocal, language)) {
                store.resolveConflict(itemID: itemID, choice: .keepLocal)
            }
            Button(L10n.text(.useCloud, language)) {
                store.resolveConflict(itemID: itemID, choice: .useCloud)
            }
            Button(L10n.text(.backupThenUseCloud, language)) {
                store.resolveConflict(itemID: itemID, choice: .backupLocalThenUseCloud)
            }
        }
    }
}

private struct ConflictsPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.conflictItems.isEmpty {
                    EmptyStateView(
                        title: L10n.text(.noConflicts, language),
                        systemImage: "checkmark.shield",
                        message: L10n.text(.noConflictsMessage, language)
                    )
                } else {
                    ForEach(store.conflictItems) { item in
                        SectionCard(title: item.displayName) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.localPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let conflict = item.conflictState {
                                    Text("\(L10n.text(.localHash, language))：\(conflict.localHash)")
                                        .font(.caption.monospaced())
                                    Text("\(L10n.text(.cloudHash, language))：\(conflict.cloudHash)")
                                        .font(.caption.monospaced())
                                    Text("\(L10n.text(.detectedAt, language))：\(displayTime(conflict.detectedAt, language: language))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ConflictButtons(itemID: item.id, store: store, language: language)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct HistoryPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        List(store.historyRecords) { record in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(L10n.eventActionTitle(record.event.action, language), systemImage: iconName(for: record.event.action))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(displayTime(record.event.timestamp, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.itemName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(record.event.device.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = record.event.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                }
            }
            .padding(.vertical, 6)
        }
        .listStyle(.inset)
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }
}

private struct SettingsPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        Form {
            Section(L10n.text(.about, language)) {
                HStack {
                    Text(L10n.text(.version, language))
                    Spacer()
                    Text(BuildInfo.version)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.text(.build, language))
                    Spacer()
                    Text(BuildInfo.build)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text(.managedRoot, language)) {
                Text(store.settings.managedRootPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section(L10n.text(.syncBehavior, language)) {
                Picker(L10n.text(.syncInterval, language), selection: Binding(
                    get: { store.settings.syncIntervalSeconds },
                    set: { store.updateSyncInterval($0) }
                )) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)

                Toggle(L10n.text(.autoHints, language), isOn: Binding(
                    get: { store.settings.associationHintsEnabled },
                    set: { store.updateAssociationHintsEnabled($0) }
                ))

                Toggle(L10n.text(.launchAtLogin, language), isOn: Binding(
                    get: { store.settings.launchAtLoginEnabled },
                    set: { store.updateLaunchAtLoginEnabled($0) }
                ))

                Picker(L10n.text(.language, language), selection: Binding(
                    get: { store.settings.language },
                    set: { store.updateLanguage($0) }
                )) {
                    Text("简体中文").tag(AppLanguage.zhHans)
                    Text("English").tag(AppLanguage.en)
                }
            }

            Section(L10n.text(.devices, language)) {
                ForEach(store.knownDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text(device.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.id == store.currentDevice.id {
                            Text(L10n.text(.currentMachine, language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AddFileSheet: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.addCloudFile, language))
                .font(.title2)
                .fontWeight(.semibold)

            SectionCard(title: L10n.text(.chooseLocalFile, language)) {
                VStack(alignment: .leading, spacing: 12) {
                    if !store.addDraft.localPath.isEmpty {
                        SelectedLocalFileCard(path: store.addDraft.localPath) {
                            store.chooseLocalFileForAdd()
                        }
                    }
                    LocalFileDropZone(store: store, language: language, compact: !store.addDraft.localPath.isEmpty)
                }
            }

            if !store.addDraft.localPath.isEmpty {
                Picker("", selection: Binding(
                    get: { store.addDraft.mode },
                    set: { store.updateAddMode($0) }
                )) {
                    Text(L10n.modeTitle(.upload, language)).tag(AddFileMode.upload)
                    Text(L10n.modeTitle(.linkExisting, language)).tag(AddFileMode.linkExisting)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if !store.addDraft.suggestions.isEmpty {
                    SectionCard(title: L10n.text(.detectedExistingCloudFile, language)) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(store.addDraft.suggestions) { candidate in
                                DiscoveryHintRow(candidate: candidate, language: language) {
                                    store.useSuggestion(candidate)
                                } onIgnore: {
                                    store.ignoreSuggestion(candidate)
                                }
                            }
                        }
                    }
                }

                if store.addDraft.mode == .upload {
                    SectionCard(title: L10n.text(.uploadSettings, language)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(L10n.text(.cloudRoot, language))：\(store.settings.cloudFilesRootPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(L10n.text(.subfolderOptional, language), text: Binding(
                                get: { store.addDraft.uploadRelativeFolder },
                                set: { store.updateUploadRelativeFolder($0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            HStack {
                                Spacer()
                                Button(L10n.text(.browseExistingFolder, language)) {
                                    store.chooseManagedFolderForAdd()
                                }
                            }
                        }
                    }
                } else {
                    SectionCard(title: L10n.text(.chooseExistingCloudFile, language)) {
                        if store.addDraft.availableTargets.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.text(.noCloudFilesMessage, language))
                                    .foregroundStyle(.secondary)
                                Button(L10n.text(.refreshList, language)) {
                                    store.refreshAvailableTargets()
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker(
                                    L10n.text(.chooseExistingCloudFile, language),
                                    selection: Binding(
                                        get: { store.addDraft.selectedTargetID ?? "" },
                                        set: { value in
                                            guard !value.isEmpty else { return }
                                            store.selectLinkTarget(value)
                                        }
                                    )
                                ) {
                                    Text(L10n.text(.chooseExistingCloudFile, language))
                                        .tag("")
                                    ForEach(store.addDraft.availableTargets) { target in
                                        Text(target.fileName)
                                            .tag(target.id)
                                    }
                                }
                                .pickerStyle(.menu)

                                if let selectedTarget = store.addDraft.availableTargets.first(where: { $0.id == store.addDraft.selectedTargetID }) {
                                    DiscoveryTargetRow(target: selectedTarget, isSelected: true)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button(L10n.text(.cancel, language)) {
                    store.dismissAddSheet()
                }
                Button(store.addDraft.mode == .upload ? L10n.text(.addAndUpload, language) : L10n.text(.createLink, language)) {
                    store.submitAddDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.addDraft.localPath.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 780, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LocalFileDropZone: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage
    let compact: Bool

    @State private var isTargeted = false

    var body: some View {
        Button {
            store.chooseLocalFileForAdd()
        } label: {
            VStack(spacing: compact ? 6 : 10) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: compact ? 20 : 26, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text(L10n.text(.dragLocalFileTitle, language))
                    .font(compact ? .subheadline : .headline)
                    .fontWeight(.medium)
                Text(L10n.text(.dragLocalFileMessage, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 18 : 28)
            .background(isTargeted ? Color.accentColor.opacity(0.08) : AppChromeColor.subtleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isTargeted ? Color.accentColor : AppChromeColor.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = extractFileURL(from: item) else { return }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            DispatchQueue.main.async {
                store.setLocalFilePathForAdd(url.path)
            }
        }
        return true
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
        }
        if let text = item as? String {
            return URL(string: text)
        }
        return nil
    }
}

private struct DiscoveryHintRow: View {
    let candidate: DiscoveryCandidate
    let language: AppLanguage
    let onUse: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: candidate.kind == .folder ? "folder.fill" : "doc.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.fileName)
                    .fontWeight(.medium)
                Text(candidate.cloudFilePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(candidate.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text(.useThisExistingFile, language), action: onUse)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(L10n.text(.ignore, language), action: onIgnore)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(AppChromeColor.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DiscoveryTargetRow: View {
    let target: DiscoveryCandidate
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text(target.fileName)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: target.kind == .folder ? "folder.fill" : "doc.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(target.cloudFilePath)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(target.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SelectedLocalFileCard: View {
    let path: String
    let action: () -> Void

    @State private var isHovering = false

    private var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    private var targetKind: SyncTargetKind {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        return .file
    }

    private var backgroundColor: Color {
        isHovering ? Color.accentColor.opacity(0.08) : AppChromeColor.subtleFill
    }

    private var borderColor: Color {
        isHovering ? Color.accentColor.opacity(0.65) : AppChromeColor.borderStrong
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: targetKind == .folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isHovering ? AppChromeColor.shadow : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct StatusBadge: View {
    let status: SyncItemStatus
    let language: AppLanguage

    var body: some View {
        Text(L10n.statusTitle(status, language))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private func highlightedText(_ text: String, query: String, font: Font, color: Color = .primary) -> Text {
    var attributed = AttributedString(text)
    attributed.font = font
    attributed.foregroundColor = color

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return Text(attributed)
    }

    let nsText = text as NSString
    var searchRange = NSRange(location: 0, length: nsText.length)
    while searchRange.location < nsText.length {
        let found = nsText.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
        guard found.location != NSNotFound,
              let range = Range(found, in: attributed) else {
            break
        }

        attributed[range].backgroundColor = Color.accentColor.opacity(0.18)
        attributed[range].foregroundColor = .primary
        attributed[range].font = font.weight(.semibold)

        let nextLocation = found.location + found.length
        searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
    }

    return Text(attributed)
}

private func displayVersion(_ versionID: String) -> String {
    guard versionID.count == 17,
          versionID.range(of: #"^\d{17}$"#, options: .regularExpression) != nil else {
        return versionID
    }

    let year = versionID.prefix(4)
    let month = versionID.dropFirst(4).prefix(2)
    let day = versionID.dropFirst(6).prefix(2)
    let hour = versionID.dropFirst(8).prefix(2)
    let minute = versionID.dropFirst(10).prefix(2)
    let second = versionID.dropFirst(12).prefix(2)
    let millisecond = versionID.suffix(3)
    return "\(year)-\(month)-\(day) \(hour):\(minute):\(second).\(millisecond)"
}

private func statusColor(_ status: SyncItemStatus) -> Color {
    switch status {
    case .synced:
        return .green
    case .uploading, .downloading:
        return .blue
    case .conflict:
        return .orange
    case .pending:
        return .secondary
    case .error:
        return .red
    case .disabled:
        return .secondary
    }
}

private func statusColor(_ status: SyncStatus) -> Color {
    switch status {
    case .idle:
        return .green
    case .syncing:
        return .blue
    case .warning:
        return .orange
    case .error:
        return .red
    }
}

private func iconName(for action: SyncEventAction) -> String {
    switch action {
    case .added:
        return "plus.circle"
    case .linked:
        return "link"
    case .upload:
        return "icloud.and.arrow.up"
    case .download:
        return "icloud.and.arrow.down"
    case .deleted:
        return "trash"
    case .conflictDetected:
        return "exclamationmark.triangle"
    case .conflictResolved:
        return "checkmark.circle"
    case .error:
        return "xmark.octagon"
    }
}

private func displayTime(_ isoString: String, language: AppLanguage) -> String {
    guard let date = ISO8601DateFormatter.filelay.date(from: isoString) else {
        return isoString
    }
    let formatter = DateFormatter()
    formatter.locale = language == .en ? Locale(identifier: "en_US_POSIX") : Locale(identifier: "zh_CN")
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
