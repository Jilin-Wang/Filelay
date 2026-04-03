import SwiftUI

struct ConflictsPage: View {
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

struct ConflictButtons: View {
    let itemID: String
    @ObservedObject var store: AppStore
    let language: AppLanguage

    var body: some View {
        HStack {
            Button(L10n.text(.keepLocal, language)) {
                store.resolveConflict(itemID: itemID, choice: .keepLocal)
            }
            .hoverCursor(.pointingHand)
            Button(L10n.text(.useCloud, language)) {
                store.resolveConflict(itemID: itemID, choice: .useCloud)
            }
            .hoverCursor(.pointingHand)
            Button(L10n.text(.backupThenUseCloud, language)) {
                store.resolveConflict(itemID: itemID, choice: .backupLocalThenUseCloud)
            }
            .hoverCursor(.pointingHand)
        }
    }
}
