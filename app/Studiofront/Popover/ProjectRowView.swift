import SwiftUI
import ThemeKit
import StudioStore

struct ProjectRowView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var row: ProjectRow
    var isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        let metrics = theme.metrics
        RowContainer(isSelected: isSelected, isHovered: isHovered) {
            HStack(alignment: .center, spacing: metrics.rowGap) {
                favoriteButton
                ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex)
                identity
                Spacer(minLength: 8)
                trailing
            }
        }
        .contentShape(Rectangle())
        .opacity(row.isUnavailable ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .onTapGesture { store.select(row.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(row.isUnavailable ? "\(row.displayTitle), unavailable" : row.displayTitle)
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
                HStack(spacing: 5) {
                    TypeBadge(typeName: document.typeName)
                    Text(document.title)
                        .font(theme.typography.meta)
                        .foregroundStyle(theme.colors.sub)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .semibold))
                        Text(RelativeTimestamp.string(from: document.editedAt))
                    }
                    .font(theme.typography.timestamp)
                    .foregroundStyle(theme.colors.faint)
                    .fixedSize()
                    .accessibilityLabel("Last edited \(RelativeTimestamp.string(from: document.editedAt))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailing: some View {
        HStack(spacing: 11) {
            AvatarStack(items: row.activity.activeUsers.map { member in
                AvatarStack.Item(
                    id: member.id,
                    initials: member.initials,
                    color: PresenceSwatch.color(for: member.id)
                )
            })

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
                    if let url = row.project.studioURL {
                        AppDelegate.shared?.openURL(url)
                    }
                }
            }
        }
    }
}
