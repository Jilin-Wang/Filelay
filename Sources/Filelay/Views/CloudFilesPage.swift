import SwiftUI

struct CloudFilesPage: View {
    @ObservedObject var store: AppStore
    let language: AppLanguage

    @State private var search = ""
    @State private var filter: FileFilter = .all

    enum FileFilter: String, CaseIterable, Identifiable {
        case all, synced, syncing, unlinked, conflict
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
            case .all: matchesFilter = true
            case .synced: matchesFilter = file.status == .synced
            case .syncing: matchesFilter = file.status == .pending || file.status == .uploading || file.status == .downloading
            case .unlinked: matchesFilter = !file.isLocallyLinked
            case .conflict: matchesFilter = file.status == .conflict
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

    private var detailFileForCurrentState: CloudFileRecord? {
        if !search.isEmpty { return store.selectedCloudFile }
        return visibleSelectedFile
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
                    .hoverCursor(.pointingHand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { dismissAnyTextFocus() }

                Spacer(minLength: 24)

                HStack(spacing: 10) {
                    Button { store.presentAddSheet() } label: {
                        Label(L10n.text(.addCloudFile, language), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverCursor(.pointingHand)

                    Button { store.triggerManualSync() } label: {
                        Label(L10n.text(.refresh, language), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .hoverCursor(.pointingHand)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if search.isEmpty && filteredFiles.isEmpty {
                EmptyStateView(title: emptyStateTitle, systemImage: emptyStateImage, message: emptyStateMessage)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    CloudFileListPane(
                        store: store, files: filteredFiles, language: language,
                        searchQuery: $search,
                        emptyStateTitle: emptyStateTitle, emptyStateImage: emptyStateImage, emptyStateMessage: emptyStateMessage
                    )
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 400)

                    if let file = detailFileForCurrentState {
                        CloudFileDetailPanel(store: store, file: file, language: language)
                            .frame(minWidth: 500)
                            .onTapGesture { dismissAnyTextFocus() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear { if store.selectedCloudFileID == nil { selectFirstVisibleFile() } }
        .onChange(of: filter) { _ in selectFirstVisibleFile() }
        .onTapGesture { dismissAnyTextFocus() }
    }

    private var emptyStateTitle: String {
        filter == .all && search.isEmpty ? L10n.text(.noCloudFiles, language) : L10n.text(.noMatchingCloudFiles, language)
    }

    private var emptyStateMessage: String {
        filter == .all && search.isEmpty ? L10n.text(.noCloudFilesMessage, language) : L10n.text(.noMatchingCloudFilesMessage, language)
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
    @FocusState private var searchFieldFocused: Bool
    let emptyStateTitle: String
    let emptyStateImage: String
    let emptyStateMessage: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField(L10n.text(.searchCloudFiles, language), text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFieldFocused)
                        .hoverCursor(.iBeam)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            dismissAnyTextFocus()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.text(.cancel, language))
                        .hoverCursor(.pointingHand)
                    }
                }
            }
            .padding(16)

            ScrollView {
                if files.isEmpty {
                    EmptyStateView(title: emptyStateTitle, systemImage: emptyStateImage, message: emptyStateMessage)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(files) { file in
                            CloudFileRowView(
                                file: file, language: language, searchQuery: searchQuery,
                                isSelected: store.selectedCloudFileID == file.cloudFileId
                            ) {
                                store.selectedCloudFileID = file.cloudFileId
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .onTapGesture { dismissAnyTextFocus() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppChromeColor.panelBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppChromeColor.border, lineWidth: 1))
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
            .background(isSelected ? Color.accentColor.opacity(0.08) : isHovering ? AppChromeColor.subtleFill : AppChromeColor.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : isHovering ? AppChromeColor.borderStrong : AppChromeColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(file.displayName)
        .hoverCursor(.pointingHand)
    }
}

struct AssociationBadge: View {
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

struct CloudFileDetailPanel: View {
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
                                Text(file.displayName).font(.title2).fontWeight(.semibold)
                            } icon: {
                                Image(systemName: file.kind == .folder ? "folder.fill" : "doc.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            AssociationBadge(file: file, language: language)
                            Button(role: .destructive) { store.requestDeleteCloudFile(file) } label: {
                                Label(L10n.text(.deleteCloudFile, language), systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .hoverCursor(.pointingHand)
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
                            Text(file.cloudFilePath).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DetailInfoRow(label: L10n.text(.localPath, language)) {
                            if let localPath = file.localPath, !localPath.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(localPath).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    Button { store.revealLocalFileInFinder(localPath) } label: {
                                        Label(L10n.text(.showInFinder, language), systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered).controlSize(.small).hoverCursor(.pointingHand)
                                }
                            } else {
                                Text(L10n.text(.unlinkedLocalFile, language)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        DetailInfoRow(label: L10n.text(.syncStatusLabel, language)) {
                            if let status = file.status {
                                Text(L10n.statusTitle(status, language)).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(L10n.text(.unlinkedBadge, language)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        DetailInfoRow(label: L10n.text(.cloudVersion, language)) {
                            Text(file.cloudVersion.map { displayVersion($0.versionId) } ?? "—").font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DetailInfoRow(label: L10n.text(.lastUpdatedDevice, language)) {
                            Text(file.cloudVersion?.updatedByDevice.name ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let updatedAt = file.cloudVersion?.updatedAt {
                            DetailInfoRow(label: L10n.text(.cloudUpdatedAt, language), showsDivider: false) {
                                Text(displayTime(updatedAt, language: language)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let conflict = file.conflictState {
                        SectionCard(title: L10n.text(.pendingConflict, language)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(L10n.text(.localHash, language))：\(conflict.localHash)").font(.caption.monospaced())
                                Text("\(L10n.text(.cloudHash, language))：\(conflict.cloudHash)").font(.caption.monospaced())
                                Text("\(L10n.text(.detectedAt, language))：\(displayTime(conflict.detectedAt, language: language))").font(.caption).foregroundStyle(.secondary)
                                HStack(alignment: .top, spacing: 12) {
                                    PreviewBlock(title: L10n.text(.localPreview, language), content: conflict.localPreview)
                                    PreviewBlock(title: L10n.text(.cloudPreview, language), content: conflict.cloudPreview)
                                }
                            }
                        }
                    }

                    SectionCard(title: L10n.text(.deviceSyncStatus, language)) {
                        if file.deviceReceipts.isEmpty {
                            Text(L10n.text(.noReceipts, language)).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(file.deviceReceipts.values.sorted(by: { $0.device.name < $1.device.name }), id: \.device.id) { receipt in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(receipt.device.name).fontWeight(.medium)
                                            Spacer()
                                            StatusBadge(status: receipt.lastSyncStatus, language: language)
                                        }
                                        Text(displayTime(receipt.lastAppliedAt, language: language)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppChromeColor.subtleFill).clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    SectionCard(title: L10n.text(.syncHistory, language)) {
                        if file.history.isEmpty {
                            Text(L10n.text(.noHistory, language)).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(file.history.prefix(20)) { event in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(L10n.eventActionTitle(event.action, language), systemImage: iconName(for: event.action)).font(.subheadline).fontWeight(.medium)
                                            Spacer()
                                            Text(displayTime(event.timestamp, language: language)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(event.device.name).font(.caption).foregroundStyle(.secondary)
                                        if let note = event.note, !note.isEmpty { Text(note).font(.caption) }
                                    }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppChromeColor.subtleFill).clipShape(RoundedRectangle(cornerRadius: 12))
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
