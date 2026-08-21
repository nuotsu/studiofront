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
    @Environment(\.studioTheme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(StudioStore.self) private var store

    var row: ProjectRow

    var body: some View {
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
                if store.isProjectLocked(row.id) {
                    IconButton(systemName: "lock.fill", accessibilityLabel: "Locked — upgrade to unlock") {
                        AppDelegate.shared?.openSettingsWindow(pane: .license)
                    }
                } else {
                    studioButton
                }
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
        let preferExternal = settings.studioURLPreference == .external
        guard let url = row.project.resolvedStudioURL(preferExternal: preferExternal) else { return }
        AppDelegate.shared?.openURL(url)
    }
}
