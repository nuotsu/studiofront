import Foundation
import Testing
@testable import StudioStore

@Suite("StudioStore free-tier locks")
@MainActor
struct StudioStoreLockTests {
    @Test("unlimited entitlement locks nothing")
    func unlimited() {
        let store = makeStore(projects: [
            ("p1", "org-a", favorite: false, editedHoursAgo: 1),
            ("p2", "org-b", favorite: false, editedHoursAgo: 2),
            ("p3", "org-c", favorite: false, editedHoursAgo: 3),
            ("p4", "org-d", favorite: false, editedHoursAgo: 4),
        ])
        store.entitlement = .unlimited
        #expect(!store.isProjectLocked("p1"))
        #expect(!store.isProjectLocked("p4"))
        #expect(!store.isOrganizationLocked("org-d"))
    }

    @Test("free tier unlocks three most recent projects across three orgs")
    func freeCapsByRecency() {
        let store = makeStore(projects: [
            ("p1", "org-a", favorite: false, editedHoursAgo: 1),
            ("p2", "org-b", favorite: false, editedHoursAgo: 2),
            ("p3", "org-c", favorite: false, editedHoursAgo: 3),
            ("p4", "org-d", favorite: false, editedHoursAgo: 4),
        ])
        store.entitlement = .free
        #expect(!store.isProjectLocked("p1"))
        #expect(!store.isProjectLocked("p2"))
        #expect(!store.isProjectLocked("p3"))
        #expect(store.isProjectLocked("p4"))
        #expect(store.isOrganizationLocked("org-d"))
    }

    @Test("favorites unlock first before non-favorites")
    func favoritesFirst() {
        let store = makeStore(projects: [
            ("fav-old", "org-a", favorite: true, editedHoursAgo: 10),
            ("fav-mid", "org-b", favorite: true, editedHoursAgo: 5),
            ("fav-new", "org-c", favorite: true, editedHoursAgo: 1),
            ("recent", "org-d", favorite: false, editedHoursAgo: 0),
        ])
        store.entitlement = .free
        #expect(!store.isProjectLocked("fav-new"))
        #expect(!store.isProjectLocked("fav-mid"))
        #expect(!store.isProjectLocked("fav-old"))
        #expect(store.isProjectLocked("recent"))
    }

    @Test("org cap blocks a fourth organization even under the project cap")
    func orgCapBlocksFourthOrg() {
        // Three favorites already consume 3 orgs — a 4th-org project stays locked
        // even though only 2 projects would fit under the project cap alone.
        let store = makeStore(projects: [
            ("a1", "org-a", favorite: true, editedHoursAgo: 1),
            ("b1", "org-b", favorite: true, editedHoursAgo: 2),
            ("c1", "org-c", favorite: false, editedHoursAgo: 3),
            ("d1", "org-d", favorite: false, editedHoursAgo: 4),
        ])
        store.entitlement = StudioStoreEntitlement(
            isUnlimited: false,
            maxFavoriteProjects: 3,
            maxFavoriteOrganizations: 2
        )
        #expect(!store.isProjectLocked("a1"))
        #expect(!store.isProjectLocked("b1"))
        #expect(store.isProjectLocked("c1"))
        #expect(store.isProjectLocked("d1"))
        #expect(store.isOrganizationLocked("org-c"))
        #expect(store.isOrganizationLocked("org-d"))
    }

    @Test("defaults to free entitlement before license resolves")
    func defaultEntitlementIsFree() {
        let store = StudioStore()
        #expect(!store.entitlement.isUnlimited)
        #expect(store.entitlement.maxFavoriteProjects == 3)
    }
}

@MainActor
private func makeStore(
    projects: [(id: String, org: String, favorite: Bool, editedHoursAgo: Double)]
) -> StudioStore {
    let now = Date()
    let rows: [ProjectRow] = projects.map { item in
        let project = SanityProject(
            id: item.id,
            displayName: item.id,
            organizationId: item.org,
            organizationName: item.org
        )
        let curation = ProjectCuration(projectId: item.id, isFavorite: item.favorite)
        let doc = EditedDocument(
            id: "doc-\(item.id)",
            title: "Doc",
            typeName: "post",
            editedAt: now.addingTimeInterval(-item.editedHoursAgo * 3600)
        )
        let activity = ProjectActivity(lastEditedDocument: doc)
        return ProjectRow(project: project, curation: curation, activity: activity)
    }
    return StudioStore(rows: rows)
}
