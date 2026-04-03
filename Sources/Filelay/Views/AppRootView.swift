import SwiftUI

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

struct SidebarView: View {
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
        case .files: return store.cloudFiles.count
        case .conflicts: return store.conflictItems.count
        case .history: return min(store.historyRecords.count, 99)
        case .settings: return 0
        }
    }

    private func iconName(for section: AppSection) -> String {
        switch section {
        case .files: return "icloud"
        case .conflicts: return "exclamationmark.triangle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
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
        .hoverCursor(.pointingHand)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.1) }
        if isHovering { return AppChromeColor.subtleFillStrong }
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
