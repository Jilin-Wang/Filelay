import SwiftUI
import AppKit

enum AppChromeColor {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.035)
    static let subtleFillStrong = Color.primary.opacity(0.055)
    static let border = Color.primary.opacity(0.08)
    static let borderStrong = Color.primary.opacity(0.14)
    static let shadow = Color.black.opacity(0.12)
}

struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                cursor.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}

func dismissAnyTextFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

struct StatusBadge: View {
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

struct EmptyStateView: View {
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

struct SectionCard<Content: View>: View {
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

struct PreviewBlock: View {
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

struct DetailInfoRow<Content: View>: View {
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

func highlightedText(_ text: String, query: String, font: Font, color: Color = .primary) -> Text {
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

        attributed[range].backgroundColor = Color.yellow.opacity(0.6)
        attributed[range].foregroundColor = .primary
        attributed[range].font = font.weight(.semibold)

        let nextLocation = found.location + found.length
        searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
    }

    return Text(attributed)
}

func displayVersion(_ versionID: String) -> String {
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

func statusColor(_ status: SyncItemStatus) -> Color {
    switch status {
    case .synced: return .green
    case .uploading, .downloading: return .blue
    case .conflict: return .orange
    case .pending: return .secondary
    case .error: return .red
    case .disabled: return .secondary
    }
}

func statusColor(_ status: SyncStatus) -> Color {
    switch status {
    case .idle: return .green
    case .syncing: return .blue
    case .warning: return .orange
    case .error: return .red
    }
}

func iconName(for action: SyncEventAction) -> String {
    switch action {
    case .added: return "plus.circle"
    case .linked: return "link"
    case .upload: return "icloud.and.arrow.up"
    case .download: return "icloud.and.arrow.down"
    case .deleted: return "trash"
    case .conflictDetected: return "exclamationmark.triangle"
    case .conflictResolved: return "checkmark.circle"
    case .error: return "xmark.octagon"
    }
}

func displayTime(_ isoString: String, language: AppLanguage) -> String {
    guard let date = ISO8601DateFormatter.filelay.date(from: isoString) else {
        return isoString
    }
    let formatter = DateFormatter()
    formatter.locale = language == .en ? Locale(identifier: "en_US_POSIX") : Locale(identifier: "zh_CN")
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
