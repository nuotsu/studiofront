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
        row.curation.isFavorite
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
        let display = store.documentDisplay(for: row)
        return VStack(alignment: .leading, spacing: 4) {
            if display.isSearchMatch, let document = display.document {
                documentLine(document: document, emphasized: true)
                projectLine(emphasized: false)
            } else {
                projectLine(emphasized: true)
                if let document = display.document {
                    documentLine(document: document, emphasized: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The project name line — promoted (name-slot font/color) when this row
    /// isn't a document search result, demoted to a muted caption beneath the
    /// document title when it is.
    private func projectLine(emphasized: Bool) -> some View {
        HStack(spacing: 6) {
            if let favoriteIndex {
                KeycapLegend([.symbol("command"), .text("\(favoriteIndex)")], compact: true)
            }
            Text(row.displayTitle)
                .font(emphasized ? theme.typography.projectName : theme.typography.meta)
                .foregroundStyle(emphasized ? theme.colors.text : theme.colors.sub)
                .lineLimit(1)
            CopyChip(
                text: row.project.id,
                copied: store.copiedProjectID == row.project.id,
                accessibilityName: "Copy project ID \(row.project.id)"
            ) {
                store.copyProjectID(row.project.id)
            }
        }
    }

    /// The document line — promoted to the name slot (same font/color as
    /// the project name) when this row is a document search result,
    /// otherwise the usual muted "last edited" caption beneath the name.
    private func documentLine(document: EditedDocument, emphasized: Bool) -> some View {
        Button {
            if let url = document.deepLinkURL {
                AppDelegate.shared?.openURL(url)
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

    private var trailing: some View {
        HStack(spacing: 11) {
            AvatarStack(
                items: row.activity.activeUsers.map { member in
                    AvatarStack.Item(
                        id: member.id,
                        name: member.displayName,
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
                    IconButton(imageName: "MasterDetail", accessibilityLabel: "Open in Sanity Manage") {
                        AppDelegate.shared?.openURL(manage)
                    }
                }
                studioButton
            }
        }
    }

    private var studioButton: some View {
        let preferExternal = settings.studioURLPreference == .external
        let primaryURL = row.project.resolvedStudioURL(preferExternal: preferExternal)
        let menuItems: [SplitPrimaryButton.MenuItem] = row.project.studioApps.compactMap { app in
            guard let url = app.resolvedURL else { return nil }
            let label = app.title ?? (app.isExternal ? (url.host ?? app.host) : "\(app.host).sanity.studio")
            return SplitPrimaryButton.MenuItem(id: app.id, title: label) {
                AppDelegate.shared?.openURL(url)
            }
        }

        return Group {
            if menuItems.count > 1 {
                SplitPrimaryButton("Studio", action: {
                    if let primaryURL { AppDelegate.shared?.openURL(primaryURL) }
                }, menuItems: menuItems)
            } else {
                PrimaryButton("Studio") {
                    if let primaryURL { AppDelegate.shared?.openURL(primaryURL) }
                }
            }
        }
    }
}
