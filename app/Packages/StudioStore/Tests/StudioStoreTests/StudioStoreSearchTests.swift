import Foundation
import Testing
@testable import StudioStore

@Suite("StudioStore document title search")
@MainActor
struct StudioStoreSearchTests {
    @Test("thank you matches spaced and hyphenated queries")
    func thankYouHyphenEquivalence() {
        let store = makeSearchStore(recentTitles: ["Draft: Thank You"])
        store.query = "thank you"
        #expect(store.cachedDocumentMatches(for: store.rows[0]).count == 1)

        store.query = "thank-you"
        #expect(store.cachedDocumentMatches(for: store.rows[0]).count == 1)
    }

    @Test("thank you matches longer titles containing the phrase")
    func thankYouSubstring() {
        let store = makeSearchStore(recentTitles: ["Thank You - Acru Webinar"])
        store.query = "thank you"
        let matches = store.cachedDocumentMatches(for: store.rows[0])
        #expect(matches.count == 1)
        #expect(matches[0].title == "Thank You - Acru Webinar")
    }

    @Test("document-only title match shows project and interleaved document row")
    func documentOnlyMatchInterleaves() {
        let store = makeSearchStore(recentTitles: ["Thank You - Acru Webinar"], projectName: "Unrelated Project")
        store.query = "thank you"
        let items = store.groups.flatMap(\.items)
        #expect(items.contains { item in
            if case .project(let row) = item { return row.id == "p1" }
            return false
        })
        #expect(items.contains { item in
            if case .document(_, let doc) = item { return doc.title.contains("Thank You") }
            return false
        })
    }

    @Test("memoized groups refresh as soon as the query changes")
    func queryChangeInvalidatesGroups() {
        let store = makeSearchStore(recentTitles: ["Home"], projectName: "Acme")
        #expect(store.groups.flatMap(\.items).count == 1)

        store.query = "zzz"
        #expect(store.groups.isEmpty)
        #expect(store.selectedID == nil)

        store.query = ""
        #expect(store.groups.flatMap(\.items).count == 1)
        #expect(store.selectedID == "p1")
    }

    @Test("project acronyms match through precomputed initials")
    func acronymMatchesProject() {
        let store = makeSearchStore(recentTitles: [], projectName: "Elevate Experiences")
        store.query = "ee"
        #expect(store.visibleRows.map(\.id) == ["p1"])
    }

    @Test("plugin document types never surface as cached title matches")
    func excludedTypesAreNotSearchable() {
        let deployment = EditedDocument(id: "d1", title: "Thank You", typeName: "vercel.deploymentTarget", editedAt: Date())
        let row = ProjectRow(
            project: SanityProject(id: "p1", displayName: "Project"),
            curation: ProjectCuration(projectId: "p1"),
            activity: ProjectActivity(lastEditedDocument: deployment, recentDocuments: [deployment])
        )
        let store = StudioStore(rows: [row])
        store.query = "thank"
        #expect(store.cachedDocumentMatches(for: row).isEmpty)
    }
}

@MainActor
private func makeSearchStore(recentTitles: [String], projectName: String = "Project") -> StudioStore {
    let now = Date()
    let recentDocuments = recentTitles.enumerated().map { index, title in
        EditedDocument(
            id: "doc-\(index)",
            title: title,
            typeName: "page",
            editedAt: now.addingTimeInterval(-Double(index) * 60)
        )
    }
    let project = SanityProject(id: "p1", displayName: projectName)
    let curation = ProjectCuration(projectId: "p1")
    let activity = ProjectActivity(
        lastEditedDocument: recentDocuments.first,
        recentDocuments: recentDocuments
    )
    let row = ProjectRow(project: project, curation: curation, activity: activity)
    return StudioStore(rows: [row])
}
