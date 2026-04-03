import SwiftUI

struct HistoryPage: View {
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
        .scrollContentBackground(.hidden)
        .background(AppChromeColor.windowBackground)
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }
}
