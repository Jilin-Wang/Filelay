import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct AddFileSheet: View {
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
                .hoverCursor(.pointingHand)

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
                                .font(.caption).foregroundStyle(.secondary)
                            TextField(L10n.text(.subfolderOptional, language), text: Binding(
                                get: { store.addDraft.uploadRelativeFolder },
                                set: { store.updateUploadRelativeFolder($0) }
                            ))
                            .textFieldStyle(.roundedBorder).hoverCursor(.iBeam)
                            HStack {
                                Spacer()
                                Button(L10n.text(.browseExistingFolder, language)) {
                                    store.chooseManagedFolderForAdd()
                                }
                                .hoverCursor(.pointingHand)
                            }
                        }
                    }
                } else {
                    SectionCard(title: L10n.text(.chooseExistingCloudFile, language)) {
                        if store.addDraft.availableTargets.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.text(.noCloudFilesMessage, language)).foregroundStyle(.secondary)
                                Button(L10n.text(.refreshList, language)) {
                                    store.refreshAvailableTargets()
                                }.hoverCursor(.pointingHand)
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
                                    Text(L10n.text(.chooseExistingCloudFile, language)).tag("")
                                    ForEach(store.addDraft.availableTargets) { target in
                                        Text(target.fileName).tag(target.id)
                                    }
                                }
                                .pickerStyle(.menu).hoverCursor(.pointingHand)

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
                Button(L10n.text(.cancel, language)) { store.dismissAddSheet() }.hoverCursor(.pointingHand)
                Button(store.addDraft.mode == .upload ? L10n.text(.addAndUpload, language) : L10n.text(.createLink, language)) {
                    store.submitAddDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.addDraft.localPath.isEmpty)
                .hoverCursor(.pointingHand)
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
        Button { store.chooseLocalFileForAdd() } label: {
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
        .hoverCursor(.pointingHand)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = extractFileURL(from: item) else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            DispatchQueue.main.async { store.setLocalFilePathForAdd(url.path) }
        }
        return true
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? }
        if let text = item as? String { return URL(string: text) }
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
                Text(candidate.fileName).fontWeight(.medium)
                Text(candidate.cloudFilePath).font(.caption).foregroundStyle(.secondary)
                Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text(.useThisExistingFile, language), action: onUse)
                .buttonStyle(.borderedProminent).controlSize(.small).hoverCursor(.pointingHand)
            Button(L10n.text(.ignore, language), action: onIgnore)
                .buttonStyle(.bordered).controlSize(.small).hoverCursor(.pointingHand)
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
                    Text(target.fileName).fontWeight(.medium)
                } icon: {
                    Image(systemName: target.kind == .folder ? "folder.fill" : "doc.fill").foregroundStyle(Color.accentColor)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            Text(target.cloudFilePath).font(.caption).foregroundStyle(.secondary)
            Text(target.reason).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SelectedLocalFileCard: View {
    let path: String
    let action: () -> Void

    @State private var isHovering = false

    private var fileURL: URL { URL(fileURLWithPath: path) }

    private var targetKind: SyncTargetKind {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        return .file
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: targetKind == .folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(fileURL.lastPathComponent).font(.headline).lineLimit(1)
                    Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isHovering ? Color.accentColor.opacity(0.08) : AppChromeColor.subtleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovering ? Color.accentColor.opacity(0.65) : AppChromeColor.borderStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isHovering ? AppChromeColor.shadow : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
        .onHover { isHovering = $0 }
    }
}
