import Foundation
import Testing
@testable import StudioStore

@Suite("StudioStore live presence sidecar")
@MainActor
struct StudioStorePresenceTests {
    @Test("presence updates without invalidating list grouping")
    func presenceDoesNotRegroup() {
        let store = makePresenceStore(projectIDs: ["p1", "p2"])
        let groupsBefore = store.groups
        let idsBefore = groupsBefore.flatMap { $0.items.map(\.id) }

        let member = Member(id: "u1", displayName: "Alex")
        store.setActiveUsers([member], forProjectID: "p1")

        let groupsAfter = store.groups
        let idsAfter = groupsAfter.flatMap { $0.items.map(\.id) }
        #expect(idsAfter == idsBefore)
        #expect(store.activeUsers(for: "p1") == [member])
        #expect(store.activeUsers(for: "p2").isEmpty)
        // Memoized list rows must not be the source of truth for presence.
        let cachedRow = groupsAfter.flatMap(\.items).map(\.projectRow).first { $0.id == "p1" }
        #expect(cachedRow?.activity.activeUsers.isEmpty == true)
    }

    @Test("empty presence clears members but keeps the slice identity")
    func emptyClearsEntry() {
        let store = makePresenceStore(projectIDs: ["p1"])
        let slice = store.presenceSlice(for: "p1")
        store.setActiveUsers([Member(id: "u1", displayName: "Alex")], forProjectID: "p1")
        store.setActiveUsers([], forProjectID: "p1")
        #expect(store.activeUsers(for: "p1").isEmpty)
        #expect(store.activeUsersByProjectID["p1"] == nil)
        // Same slice object so Observation subscribers keep tracking it.
        #expect(store.presenceSlice(for: "p1") === slice)
        #expect(slice.members.isEmpty)
    }

    @Test("clearActiveUsers drops every entry")
    func clearAll() {
        let store = makePresenceStore(projectIDs: ["p1", "p2"])
        store.setActiveUsers([Member(id: "u1", displayName: "Alex")], forProjectID: "p1")
        store.setActiveUsers([Member(id: "u2", displayName: "Sam")], forProjectID: "p2")
        store.clearActiveUsers()
        #expect(store.activeUsersByProjectID.isEmpty)
        #expect(store.activeUsers(for: "p1").isEmpty)
        #expect(store.activeUsers(for: "p2").isEmpty)
    }

    @Test("presenceSlice is stable per project id")
    func sliceIdentity() {
        let store = makePresenceStore(projectIDs: ["p1"])
        let a = store.presenceSlice(for: "p1")
        let b = store.presenceSlice(for: "p1")
        #expect(a === b)
        store.setActiveUsers([Member(id: "u1", displayName: "Alex")], forProjectID: "p1")
        #expect(store.presenceSlice(for: "p1") === a)
        #expect(a.members.count == 1)
    }
}

@MainActor
private func makePresenceStore(projectIDs: [String]) -> StudioStore {
    let rows: [ProjectRow] = projectIDs.map { id in
        ProjectRow(
            project: SanityProject(id: id, displayName: id, organizationId: "org", organizationName: "Org"),
            curation: ProjectCuration(projectId: id),
            activity: ProjectActivity()
        )
    }
    return StudioStore(rows: rows, organizations: [OrganizationRecord(id: "org", name: "Org")])
}
