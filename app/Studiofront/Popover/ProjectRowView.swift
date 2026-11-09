import SwiftUI
import ThemeKit
import StudioStore

/// One project in the list.
///
/// This body holds no state and reads nothing from the store, so it only
/// runs when the row is created or its project data changes. Hover,
/// selection, copy feedback, favicons and the ⌘1–9 legend each live in a
/// small child view (see `ProjectRowChrome.swift`).
struct ProjectRowView: View {
    @Environment(\.studioTheme) private var theme

    var row: ProjectRow
    /// Selection id when it differs from the project id (the Pinned copy and
    /// the search "Studios" group list the same project under their own ids).
    var listItemID: String?
    var favoriteIndex: Int?
    /// Shown where the row sits outside its organization's section (Pinned,
    /// search "Studios"), so the org id isn't otherwise visible.
    var showsOrganizationID = false

    /// Two 18pt lines with 5pt between them (taller than the 38pt favicon),
    /// plus the row's 8pt padding top and bottom. The list uses this instead
    /// of measuring the row, so keep it in step with `identity` below.
    static let height: CGFloat = 18 + 5 + 18 + 2 * 8

    var body: some View {
        let itemID = listItemID ?? row.id
        SelectableRow(itemID: itemID) {
            HStack(alignment: .center, spacing: theme.metrics.rowGap) {
                ProjectRowFavoriteButton(projectID: row.id, isFavorite: row.curation.isFavorite)
                StudioFaviconButton(row: row) {
                    if let favoriteIndex {
                        FavoriteShortcutLegend(index: favoriteIndex)
                    }
                }
                identity(itemID: itemID)
            }
        }
        .opacity(row.isUnavailable || row.project.isArchived ? 0.45 : 1)
        .contextMenu { ProjectContextMenu(row: row, listItemID: itemID) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityStatusLabel)
    }

    private var accessibilityStatusLabel: String {
        if row.isUnavailable { return "\(row.displayTitle), unavailable" }
        if row.project.isArchived { return "\(row.displayTitle), archived" }
        return row.displayTitle
    }

    /// Two lines: name, plan badge, and Site icon, then the ids and Manage at
    /// the right edge; then the recent document pills with live editors at
    /// the right.
    private func identity(itemID: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                nameLine(itemID: itemID)
            }
            HStack(spacing: 6) {
                let documents = row.activity.displayDocuments
                if documents.isEmpty {
                    Text("No recent edits")
                        .font(theme.typography.meta)
                        .foregroundStyle(theme.colors.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    RecentDocumentPills(documents: documents)
                }
                ProjectPresenceStack(projectID: row.id)
            }
            .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func nameLine(itemID: String) -> some View {
        ProjectNameLink(row: row)
        if let plan = row.project.plan {
            PlanBadge(plan: plan)
        }
        ProjectLinkButtons(row: row, showsManage: false)
        Spacer(minLength: 0)
        ProjectIDChips(
            projectID: row.project.id,
            organizationID: showsOrganizationID ? row.project.organizationId : nil,
            itemID: itemID
        )
        ProjectLinkButtons(row: row, showsSite: false)
            .padding(.trailing, -3)
    }
}
