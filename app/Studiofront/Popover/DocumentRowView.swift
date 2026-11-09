import SwiftUI
import ThemeKit
import StudioStore

/// A matching document in search results, listed under its project.
struct DocumentRowView: View {
    @Environment(\.studioTheme) private var theme

    var row: ProjectRow
    var document: EditedDocument
    var listItemID: String

    /// Drives the timestamp tint and the trailing links; the row background
    /// tracks hover on its own.
    @State private var isHovered = false

    /// The 33pt badge avatar plus the row's 8pt padding top and bottom. The
    /// list uses this instead of measuring the row.
    static let height: CGFloat = 33 + 2 * 8

    var body: some View {
        SelectableRow(itemID: listItemID) {
            HStack(alignment: .center, spacing: theme.metrics.rowGap) {
                ProjectRowFavoriteButton(projectID: row.id, isFavorite: row.curation.isFavorite)
                FaviconSource(host: ProjectRowChrome.faviconHost(for: row)) { favicon in
                    DocumentProjectAvatar(
                        name: row.displayTitle,
                        brandHex: row.project.brandColorHex,
                        favicon: favicon
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: openDocument)
                .accessibilityLabel("Open document, \(document.title)")
                .accessibilityAddTraits(.isButton)
                identity
                Spacer(minLength: 8)
                DocumentRowLinks(row: row, itemID: listItemID, isHovered: isHovered)
            }
        }
        .opacity(row.isUnavailable || row.project.isArchived ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(document.typeName.isEmpty ? "" : "\(document.typeName), ")\(document.title), \(row.displayTitle)")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                DocumentStatusDot(isDraft: document.isDraft)
                Text(document.displayTitle)
                    .font(theme.typography.projectName)
                    .foregroundStyle(theme.colors.text)
                    .lineLimit(1)
                if !document.typeName.isEmpty {
                    DocumentTypeChip(document.typeName)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openDocument)
            .accessibilityAddTraits(.isButton)

            HStack(spacing: 6) {
                Text(row.displayTitle)
                    .font(theme.typography.meta)
                    .foregroundStyle(theme.colors.sub)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { AppDelegate.shared?.openStudio(for: row) }
                    .accessibilityLabel("Open Studio, \(row.displayTitle)")
                    .accessibilityAddTraits(.isButton)
                HStack(spacing: 3) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .semibold))
                    Text(RelativeTimestamp.string(from: document.editedAt))
                }
                .font(theme.typography.timestamp)
                .foregroundStyle(isHovered ? theme.colors.sub : theme.colors.faint)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openDocument() {
        if let url = document.deepLinkURL {
            AppDelegate.shared?.openURL(url)
        }
    }
}
