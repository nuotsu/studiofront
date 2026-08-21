import SwiftUI
import ThemeKit
import StudioStore

struct DocumentRowView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var row: ProjectRow
    var document: EditedDocument
    var listItemID: String
    var isSelected: Bool

    @State private var isHovered = false
    @State private var favicon: Image?

    var body: some View {
        let metrics = theme.metrics
        RowContainer(isSelected: isSelected, isHovered: isHovered) {
            HStack(alignment: .center, spacing: metrics.rowGap) {
                ProjectRowFavoriteButton(projectID: row.id, isFavorite: row.curation.isFavorite)
                Button {
                    openDocument()
                } label: {
                    DocumentProjectAvatar(
                        name: row.displayTitle,
                        brandHex: row.project.brandColorHex,
                        favicon: favicon
                    )
                }
                .buttonStyle(.plain)
                .disabled(document.deepLinkURL == nil)
                .accessibilityLabel("Open document, \(document.title)")
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
        .onTapGesture { store.select(listItemID) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(document.typeName.isEmpty ? "" : "\(document.typeName), ")\(document.title), \(row.displayTitle)")
        .padding(.leading, metrics.listPadding.leading)
        .padding(.trailing, metrics.listPadding.trailing)
    }

    private var faviconHost: String? {
        ProjectRowChrome.faviconHost(for: row)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                openDocument()
            } label: {
                HStack(spacing: 5) {
                    if !document.typeName.isEmpty {
                        DocumentTypeChip(document.typeName)
                    }
                    Text(document.title)
                        .font(theme.typography.projectName)
                        .foregroundStyle(theme.colors.text)
                        .lineLimit(1)
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
            .buttonStyle(.plain)
            .disabled(document.deepLinkURL == nil)

            Button {
                openStudio()
            } label: {
                Text(row.displayTitle)
                    .font(theme.typography.meta)
                    .foregroundStyle(theme.colors.sub)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Studio, \(row.displayTitle)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openDocument() {
        guard !store.isProjectLocked(row.id) else {
            AppDelegate.shared?.openSettingsWindow(pane: .license)
            return
        }
        if let url = document.deepLinkURL {
            AppDelegate.shared?.openURL(url)
        }
    }

    private func openStudio() {
        guard !store.isProjectLocked(row.id) else {
            AppDelegate.shared?.openSettingsWindow(pane: .license)
            return
        }
        let preferExternal = settings.studioURLPreference == .external
        guard let url = row.project.resolvedStudioURL(preferExternal: preferExternal) else { return }
        AppDelegate.shared?.openURL(url)
    }
}
