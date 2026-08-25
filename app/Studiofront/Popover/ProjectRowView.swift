import SwiftUI
import ThemeKit
import StudioStore

struct ProjectRowView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var row: ProjectRow
    var isSelected: Bool
    var favoriteIndex: Int?

    @State private var isHovered = false
    @State private var isDocumentHovered = false
    @State private var favicon: Image?

    var body: some View {
        let metrics = theme.metrics
        RowContainer(isSelected: isSelected, isHovered: isHovered) {
            HStack(alignment: .center, spacing: metrics.rowGap) {
                ProjectRowFavoriteButton(projectID: row.id, isFavorite: row.curation.isFavorite)
                Button {
                    openStudio()
                } label: {
                    ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex, favicon: favicon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Studio, \(row.displayTitle)")
                .task(id: faviconHost) {
                    favicon = nil
                    guard let faviconHost else { return }
                    if let image = await FaviconCache.shared.favicon(forHost: faviconHost) {
                        favicon = Image(nsImage: image)
                    }
                }
                identity
                Spacer(minLength: 8)
                ProjectRowTrailingActions(row: row)
            }
        }
        .contentShape(Rectangle())
        .opacity(row.isUnavailable || row.project.isArchived || store.isProjectLocked(row.id) ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .onTapGesture { store.select(row.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilityStatusLabel)
        .padding(.leading, metrics.listPadding.leading)
        .padding(.trailing, metrics.listPadding.trailing)
    }

    private var accessibilityStatusLabel: String {
        if row.isUnavailable { return "\(row.displayTitle), unavailable" }
        if row.project.isArchived { return "\(row.displayTitle), archived" }
        return row.displayTitle
    }

    private var faviconHost: String? {
        ProjectRowChrome.faviconHost(for: row)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            projectLine(emphasized: true)
            if let document = store.documentDisplay(for: row) {
                documentLine(document: document, emphasized: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The project name line in the primary (name-slot) position.
    private func projectLine(emphasized: Bool) -> some View {
        HStack(spacing: 6) {
            if let favoriteIndex {
                KeycapLegend([.symbol("command"), .text("\(favoriteIndex)")], compact: true)
            }
            Button {
                openStudio()
            } label: {
                Text(row.displayTitle)
                    .font(emphasized ? theme.typography.projectName : theme.typography.meta)
                    .foregroundStyle(emphasized ? theme.colors.text : theme.colors.sub)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Studio, \(row.displayTitle)")
            CopyChip(
                text: row.project.id,
                copied: store.copiedProjectID == row.project.id,
                accessibilityName: "Copy project ID \(row.project.id)"
            ) {
                store.copyProjectID(row.project.id)
            }
        }
    }

    /// The last-edited document caption beneath the project name.
    private func documentLine(document: EditedDocument, emphasized: Bool) -> some View {
        Button {
            if let url = document.deepLinkURL {
                AppDelegate.shared?.openUnlockedURL(url, projectID: row.id)
            }
        } label: {
            HStack(spacing: 5) {
                Text(document.title)
                    .font(emphasized ? theme.typography.projectName : theme.typography.meta)
                    .foregroundStyle(emphasized ? theme.colors.text : (isDocumentHovered ? theme.colors.text : theme.colors.sub))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .semibold))
                    Text(RelativeTimestamp.string(from: document.editedAt))
                }
                .font(theme.typography.timestamp)
                .foregroundStyle(isDocumentHovered ? theme.colors.sub : theme.colors.faint)
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .disabled(document.deepLinkURL == nil)
        .onHover { isDocumentHovered = $0 }
        .accessibilityLabel("Open document, \(document.title), edited \(RelativeTimestamp.string(from: document.editedAt))")
    }

    private func openStudio() {
        let preferExternal = settings.studioURLPreference == .external
        guard let url = row.project.resolvedStudioURL(preferExternal: preferExternal) else { return }
        AppDelegate.shared?.openUnlockedURL(url, projectID: row.id)
    }
}
