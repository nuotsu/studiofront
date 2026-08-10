import SwiftUI
import ThemeKit
import StudioStore

struct ProjectRowView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var row: ProjectRow
    var isSelected: Bool

    @State private var isHovered = false
    @State private var isDocumentHovered = false
    @State private var favicon: Image?

    var body: some View {
        let metrics = theme.metrics
        RowContainer(isSelected: isSelected, isHovered: isHovered) {
            HStack(alignment: .center, spacing: metrics.rowGap) {
                favoriteButton
                ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex, favicon: favicon)
                    .task(id: faviconHost) {
                        favicon = nil
                        guard let faviconHost else { return }
                        if let image = await FaviconCache.shared.favicon(forHost: faviconHost) {
                            favicon = Image(nsImage: image)
                        }
                    }
                identity
                Spacer(minLength: 8)
                trailing
            }
        }
        .contentShape(Rectangle())
        .opacity(row.isUnavailable || row.project.isArchived ? 0.45 : 1)
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
        if let frontendHost = row.curation.primaryFrontendURL?.host, !frontendHost.isEmpty {
            return frontendHost
        }
        if let externalHost = row.project.externalStudioHost?.host, !externalHost.isEmpty {
            return externalHost
        }
        if let studioHost = row.project.studioHost, !studioHost.isEmpty {
            return "\(studioHost).sanity.studio"
        }
        return nil
    }

    private var isFavorite: Bool {
        store.rows.first(where: { $0.id == row.id })?.curation.isFavorite ?? row.curation.isFavorite
    }

    private var favoriteButton: some View {
        Button {
            store.toggleFavorite(row.id)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundStyle(isFavorite ? theme.colors.star : theme.colors.faint)
                .frame(width: theme.metrics.starColumnWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.displayTitle)
                    .font(theme.typography.projectName)
                    .foregroundStyle(theme.colors.text)
                    .lineLimit(1)
                CopyChip(
                    text: row.project.id,
                    copied: store.copiedProjectID == row.project.id,
                    accessibilityName: "Copy project ID \(row.project.id)"
                ) {
                    store.copyProjectID(row.project.id)
                }
            }

            if let document = row.activity.lastEditedDocument {
                Button {
                    if let url = document.deepLinkURL {
                        AppDelegate.shared?.openURL(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(document.title)
                            .font(theme.typography.meta)
                            .foregroundStyle(isDocumentHovered ? theme.colors.text : theme.colors.sub)
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
                .accessibilityLabel("Open last edited document, \(document.title), edited \(RelativeTimestamp.string(from: document.editedAt))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailing: some View {
        HStack(spacing: 11) {
            AvatarStack(
                items: row.activity.activeUsers.map { member in
                    AvatarStack.Item(
                        id: member.id,
                        initials: member.initials,
                        color: PresenceSwatch.color(for: member.id),
                        imageURL: member.imageURL,
                        deepLinkURL: member.deepLinkURL
                    )
                },
                onSelect: { item in
                    if let url = item.deepLinkURL {
                        AppDelegate.shared?.openURL(url)
                    }
                }
            )

            HStack(spacing: 5) {
                if let site = row.curation.primaryFrontendURL {
                    IconButton(systemName: "globe", accessibilityLabel: "Open frontend") {
                        AppDelegate.shared?.openURL(site)
                    }
                }
                if let manage = row.project.manageURL {
                    IconButton(systemName: "gearshape", accessibilityLabel: "Open in Sanity Manage") {
                        AppDelegate.shared?.openURL(manage)
                    }
                }
                PrimaryButton("Studio") {
                    if let url = row.resolvedStudioURL {
                        AppDelegate.shared?.openURL(url)
                    }
                }
            }
        }
    }
}
