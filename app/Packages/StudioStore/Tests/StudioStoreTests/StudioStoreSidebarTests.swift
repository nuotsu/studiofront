import Foundation
import Testing
@testable import StudioStore

@Suite("StudioStore sidebar: hidden organizations and recent documents")
@MainActor
struct StudioStoreSidebarTests {
    @Test("hiding an org removes its projects, favorites included, from the browse list")
    func hiddenOrganizationLeavesBrowseList() {
        let store = makeOrgStore()
        store.setOrganizationHidden("org-b", hidden: true)

        #expect(store.visibleRows.map(\.id).sorted() == ["a1", "a2"])
        #expect(!store.groups.contains { $0.id == "org-b" })
        #expect(!store.flatVisibleIDs.contains("b1"))
        #expect(store.hiddenOrganizations.map(\.name) == ["Beta"])
    }

    @Test("hidden orgs still show up in search")
    func hiddenOrganizationStillSearchable() {
        let store = makeOrgStore()
        store.setOrganizationHidden("org-b", hidden: true)
        store.query = "bravo"
        #expect(store.visibleRows.map(\.id) == ["b1"])
    }

    @Test("showing an org again restores its projects and fires the change callback once per change")
    func showOrganizationAgain() {
        let store = makeOrgStore()
        var changes = 0
        store.onHiddenOrganizationsChanged = { changes += 1 }

        store.setOrganizationHidden("org-b", hidden: true)
        store.setOrganizationHidden("org-b", hidden: true)
        store.setOrganizationHidden("org-b", hidden: false)

        #expect(changes == 2)
        #expect(store.visibleRows.count == 3)
    }

    @Test("selection moves off a project when its org is hidden")
    func selectionReconcilesOnHide() {
        let store = makeOrgStore()
        store.select("b1")
        store.setOrganizationHidden("org-b", hidden: true)
        #expect(store.selectedID != "b1")
        #expect(store.selectedID != nil)
    }

    @Test("hidden orgs are left out of presence connections")
    func hiddenOrganizationSkipsPresence() {
        let store = makeOrgStore()
        store.setOrganizationHidden("org-b", hidden: true)
        #expect(!store.eligibleProjectIDsForPresence().contains("b1"))
    }

    @Test("first item and containing group lookups for sidebar jumps")
    func groupLookups() {
        let store = makeOrgStore()
        let orgA = store.groups.first { $0.id == "org-a" }
        #expect(store.firstItemID(inGroup: "org-a") == orgA?.items.first?.id)
        #expect(store.groupID(containing: "a2") == "org-a")
        #expect(store.firstItemID(inGroup: "missing") == nil)
    }

    @Test("draft state comes from the title prefix or the drafts. id, and the prefix is stripped for display")
    func draftDetection() {
        let cachedDraft = EditedDocument(id: "home", title: "Draft: Home", typeName: "page", editedAt: Date())
        let liveDraft = EditedDocument(id: "drafts.about", title: "About", typeName: "page", editedAt: Date())
        let published = EditedDocument(id: "faq", title: "FAQ", typeName: "page", editedAt: Date())

        #expect(cachedDraft.isDraft)
        #expect(cachedDraft.displayTitle == "Home")
        #expect(liveDraft.isDraft)
        #expect(!published.isDraft)
        #expect(published.displayTitle == "FAQ")
    }

    @Test("copy feedback only shows on the chip that was clicked")
    func scopedCopyFeedback() {
        let store = makeOrgStore()
        store.copy("org-a", feedbackKey: "sidebar-org:org-a")
        #expect(store.isShowingCopied("sidebar-org:org-a"))
        #expect(!store.isShowingCopied("header-org:org-a"))
    }

    @Test("Pinned leads the Organizations view only; by date, pinned projects sit in their buckets")
    func pinnedOnlyInOrganizationsView() {
        let store = makeOrgStore()
        #expect(store.groups.first?.id == StudioStore.favoritesGroupID)
        store.groupBy = .lastEdited
        #expect(!store.groups.contains { $0.id == StudioStore.favoritesGroupID })
        #expect(store.flatVisibleIDs.contains("b1"))
    }

    @Test("revealing a hidden org isolates its projects, and Esc restores browsing")
    func revealedHiddenOrganization() {
        let store = makeOrgStore()
        store.setOrganizationHidden("org-b", hidden: true)
        store.revealedOrganizationID = "org-b"
        #expect(store.visibleRows.map(\.id) == ["b1"])
        #expect(store.groups.contains { $0.id == "org-b" })
        // Browse counts ignore the reveal.
        #expect(store.browseRows.map(\.id).sorted() == ["a1", "a2"])

        #expect(store.clearQueryOrSignalDismiss() == false)
        #expect(store.revealedOrganizationID == nil)
        #expect(!store.groups.contains { $0.id == "org-b" })
        #expect(store.clearQueryOrSignalDismiss() == true)
    }

    @Test("isolation preserves sidebar sections and excludes other orgs' hidden projects")
    func isolationKeepsSidebarStable() {
        let store = makeOrgStore()
        store.setProjectHidden("a2", hidden: true)
        store.setOrganizationHidden("org-b", hidden: true)
        let baseline = store.sidebarGroups.map(\.id)
        store.revealedOrganizationID = "org-b"
        #expect(store.sidebarGroups.map(\.id) == baseline)
        #expect(!store.groups.contains { $0.id == "org-a" })
        #expect(store.groups.flatMap(\.hiddenRows).isEmpty)
        store.revealedOrganizationID = "org-a"
        #expect(store.visibleRows.map(\.id) == ["a1"])
        #expect(store.groups.first { $0.id == "org-a" }?.hiddenRows.map(\.id) == ["a2"])
        #expect(store.sidebarGroups.map(\.id) == baseline)
        store.query = "Home"
        #expect(store.visibleRows.map(\.id) == ["a1"])
        store.groupBy = .lastEdited
        #expect(store.isolation == nil)
        #expect(store.visibleRows.map(\.id).sorted() == ["a1", "b1"])
        store.revealedOrganizationID = nil
        store.query = ""
        #expect(store.visibleRows.map(\.id) == ["a1"])
    }

    @Test("isolating the last pinned org retains its studios when pinned or unpinned")
    func isolateLastPinnedOrganization() {
        let store = makeOrgStore()
        store.toggleOrganizationFavorite("org-a")
        store.toggleOrganizationFavorite("org-b")
        #expect(store.orderedOrganizations.last?.id == "org-b")
        store.revealedOrganizationID = "org-b"
        #expect(store.visibleRows.map(\.id) == ["b1"])
        #expect(store.groups.first { $0.id == "org-b" }?.items.map(\.id) == ["b1"])
        #expect(store.flatVisibleIDs == ["b1"])
        #expect(!store.groups.contains { $0.id == StudioStore.favoritesGroupID })
        #expect(store.sidebarGroups.contains { $0.id == StudioStore.favoritesGroupID })
        store.jumpToFavorite(1)
        #expect(store.selectedID == "b1")
        store.toggleOrganizationFavorite("org-b")
        #expect(store.visibleRows.map(\.id) == ["b1"])
        store.revealedOrganizationID = nil
        #expect(store.visibleRows.count == 3)
        store.revealedOrganizationID = "org-b"
        #expect(store.visibleRows.map(\.id) == ["b1"])
    }

    @Test("unpinned orgs sort by title while pins keep their chosen order")
    func alphabeticOrganizationOrder() {
        let store = makeOrgStore()
        store.organizations.reverse()
        #expect(store.orderedOrganizations.map(\.name) == ["Acme", "Beta"])
        store.toggleOrganizationFavorite("org-b")
        #expect(store.orderedOrganizations.map(\.name) == ["Beta", "Acme"])
        store.toggleOrganizationFavorite("org-b")
        #expect(store.orderedOrganizations.map(\.name) == ["Acme", "Beta"])
    }

    @Test("date isolation filters studios and search, preserves sidebar, and clears with Esc")
    func dateIsolation() {
        let store = makeOrgStore()
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
        var rows = store.rows
        let doc = EditedDocument(id: "last-week-doc", title: "Home", typeName: "page", editedAt: lastWeek)
        rows[0].activity = ProjectActivity(lastEditedDocument: doc, recentDocuments: [doc])
        store.replaceRows(rows, organizations: store.organizations)
        store.groupBy = .lastEdited
        let baseline = store.sidebarGroups.map(\.id)
        store.isolatedRecencyBucket = .lastWeek
        #expect(store.visibleRows.map(\.id) == ["a1"])
        #expect(store.groups.map(\.id) == [RecencyBucket.lastWeek.rawValue])
        #expect(store.sidebarGroups.map(\.id) == baseline)
        store.query = "Home"
        #expect(store.visibleRows.map(\.id) == ["a1"])
        #expect(!store.clearQueryOrSignalDismiss())
        #expect(store.isolatedRecencyBucket == .lastWeek)
        #expect(!store.clearQueryOrSignalDismiss())
        #expect(store.isolation == nil)
        #expect(store.visibleRows.count == 3)
        store.isolatedRecencyBucket = .lastWeek
        store.groupBy = .organization
        #expect(store.isolation == nil)
    }

    @Test("pinned projects keep a hand-set order once moved")
    func pinnedProjectOrder() {
        let store = makeOrgStore()
        store.toggleFavorite("a1")
        // By recency: b1 (1m), a1 (5m).
        #expect(store.groups.first?.items.map(\.id) == ["pinned:b1", "pinned:a1"])
        store.movePinnedProject("a1", by: -1)
        #expect(store.groups.first?.items.map(\.id) == ["pinned:a1", "pinned:b1"])
        #expect(!store.canMovePinnedProject("a1", by: -1))
        store.toggleFavorite("a2")
        #expect(store.pinnedProjectOrder == ["a1", "b1", "a2"])
    }

    @Test("selection only shows as highlighted after arrow-key navigation")
    func keyboardNavigationFlag() {
        let store = makeOrgStore()
        #expect(!store.isKeyboardNavigating)
        store.selectNext()
        #expect(store.isKeyboardNavigating)
        store.select("a1")
        #expect(!store.isKeyboardNavigating)
        store.selectPrevious()
        store.prepareForOpen()
        #expect(!store.isKeyboardNavigating)
    }

    @Test("pinned orgs keep the user's order and move up or down")
    func pinnedOrganizationOrder() {
        let store = makeOrgStore()
        store.toggleOrganizationFavorite("org-a")
        store.toggleOrganizationFavorite("org-b")
        #expect(store.orderedOrganizations.map(\.id) == ["org-a", "org-b"])
        #expect(!store.canMovePinnedOrganization("org-a", by: -1))

        store.movePinnedOrganization("org-b", by: -1)
        #expect(store.orderedOrganizations.map(\.id) == ["org-b", "org-a"])
        #expect(store.pinnedOrganizationOrder == ["org-b", "org-a"])

        store.toggleOrganizationFavorite("org-b")
        #expect(store.pinnedOrganizationOrder == ["org-a"])
    }

    @Test("a pinned project shows under Pinned and still in its org section, with distinct ids")
    func pinnedProjectAppearsTwice() {
        let store = makeOrgStore()
        let ids = store.flatVisibleIDs
        #expect(ids.contains("pinned:b1"))
        #expect(ids.contains("b1"))
        #expect(store.groupID(containing: "b1") == "org-b")

        store.jumpToFavorite(1)
        #expect(store.selectedID == "pinned:b1")
        store.groupBy = .lastEdited
        store.jumpToFavorite(1)
        #expect(store.selectedID == "b1")
    }

    @Test("hiding a project drops it from the list into its org's hidden dropdown")
    func hideProject() {
        let store = makeOrgStore()
        store.setProjectHidden("a2", hidden: true)
        #expect(!store.flatVisibleIDs.contains("a2"))
        #expect(store.hiddenProjects.map(\.id) == ["a2"])
        #expect(store.groups.first { $0.id == "org-a" }?.hiddenRows.map(\.id) == ["a2"])

        // An org whose only projects are hidden keeps a section for the dropdown.
        store.setProjectHidden("a1", hidden: true)
        let orgA = store.groups.first { $0.id == "org-a" }
        #expect(orgA?.items.isEmpty == true)
        #expect(orgA?.hiddenRows.count == 2)
        store.setProjectHidden("a1", hidden: false)
        store.setProjectHidden("a2", hidden: false)
        #expect(store.flatVisibleIDs.contains("a2"))
    }

    @Test("org preview puts pinned projects first")
    func previewRowsPinnedFirst() {
        let store = makeOrgStore()
        store.toggleFavorite("a2")
        #expect(store.previewRows(forOrganization: "org-a").map(\.id) == ["a2", "a1"])
    }

    @Test("hidden preview candidates occupy spare quadrants without displacing visible projects")
    func hiddenPreviewSlots() {
        let store = makeOrgStore()
        store.setProjectHidden("a2", hidden: true)
        #expect(store.previewRows(forOrganization: "org-a").map(\.id) == ["a1", "a2"])
        var rows = store.rows
        for id in ["a3", "a4", "a5"] {
            rows.append(ProjectRow(
                project: SanityProject(id: id, displayName: id, organizationId: "org-a", organizationName: "Acme"),
                curation: ProjectCuration(projectId: id),
                activity: ProjectActivity()
            ))
        }
        store.replaceRows(rows, organizations: store.organizations)
        #expect(store.previewRows(forOrganization: "org-a").count == 4)
        #expect(!store.previewRows(forOrganization: "org-a").contains { $0.curation.isHidden })
        store.setProjectHidden("a5", hidden: true)
        let preview = store.previewRows(forOrganization: "org-a")
        #expect(preview.filter { !$0.curation.isHidden }.count == 3)
        #expect(preview.last?.curation.isHidden == true)
    }

    @Test("plan badge text drops the parenthetical")
    func planShortName() {
        #expect(ProjectPlan(name: "Enterprise (Community MVP)", typeID: "enterprise").shortName == "Enterprise")
        #expect(ProjectPlan(name: "Growth Trial", typeID: "growth").shortName == "Growth Trial")
    }

    @Test("display documents are newest first, deduped, and skip plugin types")
    func displayDocumentsOrdering() {
        let now = Date()
        let home = EditedDocument(id: "home", title: "Home", typeName: "page", editedAt: now.addingTimeInterval(-60))
        let about = EditedDocument(id: "about", title: "About", typeName: "page", editedAt: now.addingTimeInterval(-600))
        let pricing = EditedDocument(id: "pricing", title: "Pricing", typeName: "page", editedAt: now)
        let deploy = EditedDocument(id: "deploy", title: "Deploy", typeName: "vercel.deploymentTarget", editedAt: now)
        let activity = ProjectActivity(lastEditedDocument: home, recentDocuments: [about, home, deploy, pricing])

        #expect(activity.displayDocuments.map(\.id) == ["pricing", "home", "about"])
    }
}

@MainActor
private func makeOrgStore() -> StudioStore {
    let now = Date()
    func row(_ id: String, _ name: String, org: String, orgName: String, favorite: Bool = false, minutesAgo: Double) -> ProjectRow {
        let doc = EditedDocument(id: "\(id)-doc", title: "Home", typeName: "page", editedAt: now.addingTimeInterval(-minutesAgo * 60))
        return ProjectRow(
            project: SanityProject(id: id, displayName: name, organizationId: org, organizationName: orgName),
            curation: ProjectCuration(projectId: id, isFavorite: favorite),
            activity: ProjectActivity(lastEditedDocument: doc, recentDocuments: [doc])
        )
    }
    let rows = [
        row("a1", "Alpha One", org: "org-a", orgName: "Acme", minutesAgo: 5),
        row("a2", "Alpha Two", org: "org-a", orgName: "Acme", minutesAgo: 10),
        row("b1", "Bravo", org: "org-b", orgName: "Beta", favorite: true, minutesAgo: 1),
    ]
    return StudioStore(
        rows: rows,
        organizations: [
            OrganizationRecord(id: "org-a", name: "Acme"),
            OrganizationRecord(id: "org-b", name: "Beta"),
        ]
    )
}
