import SwiftUI
import ThemeKit
import StudioStore

enum ProjectRowChrome {
    static func faviconHost(for row: ProjectRow) -> String? {
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
}

extension View {
    /// Loads the row's favicon into `favicon`, synchronously from the shared
    /// cache when it's already there so a recycled row never flashes its
    /// letter avatar.
    func projectFavicon(for row: ProjectRow, into favicon: Binding<Image?>) -> some View {
        let host = ProjectRowChrome.faviconHost(for: row)
        return task(id: host) {
            guard let host else {
                favicon.wrappedValue = nil
                return
            }
            if let cached = FaviconCache.peekCached(forHost: host) {
                favicon.wrappedValue = Image(nsImage: cached)
                return
            }
            favicon.wrappedValue = nil
            if let image = await FaviconCache.shared.favicon(forHost: host) {
                favicon.wrappedValue = Image(nsImage: image)
            }
        }
    }
}

struct ProjectRowFavoriteButton: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var projectID: String
    var isFavorite: Bool

    var body: some View {
        Button {
            store.toggleFavorite(projectID)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundStyle(isFavorite ? theme.colors.star : theme.colors.faint)
                .frame(width: theme.metrics.starColumnWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}

struct ProjectRowTrailingActions: View {
    @Environment(StudioStore.self) private var store

    var row: ProjectRow
    /// When false, skip the presence avatar stack (document search rows share
    /// the parent project's avatars on the project row above).
    var showPresence: Bool = true

    var body: some View {
        HStack(spacing: 11) {
            if showPresence {
                let members = store.presenceSlice(for: row.id).members
                AvatarStack(
                    items: members.map { member in
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
            }

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

    @ViewBuilder
    private var studioButton: some View {
        let menuItems: [SplitPrimaryButton.MenuItem] = row.project.studioApps.compactMap { app in
            guard let url = app.resolvedURL else { return nil }
            let label = app.title ?? (app.isExternal ? (url.host ?? app.host) : "\(app.host).sanity.studio")
            return SplitPrimaryButton.MenuItem(id: app.id, title: label) {
                AppDelegate.shared?.openURL(url)
            }
        }

        if menuItems.count > 1 {
            SplitPrimaryButton("Studio", action: openStudio, menuItems: menuItems)
        } else {
            PrimaryButton("Studio", action: openStudio)
        }
    }

    private func openStudio() {
        AppDelegate.shared?.openStudio(for: row)
    }
}
