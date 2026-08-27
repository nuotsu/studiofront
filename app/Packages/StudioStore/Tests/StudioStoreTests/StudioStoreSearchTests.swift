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

    @Test("initials match multi-word titles")
    func initialsMatch() {
        let store = makeSearchStore(recentTitles: ["Elevate Experiences"])
        store.query = "ee"
        #expect(store.cachedDocumentMatches(for: store.rows[0]).count == 1)
    }
}

@MainActor
private func makeSearchStore(recentTitles: [String]) -> StudioStore {
    let now = Date()
    let recentDocuments = recentTitles.enumerated().map { index, title in
        EditedDocument(
            id: "doc-\(index)",
            title: title,
            typeName: "page",
            editedAt: now.addingTimeInterval(-Double(index) * 60)
        )
    }
    let project = SanityProject(id: "p1", displayName: "Project")
    let curation = ProjectCuration(projectId: "p1")
    let activity = ProjectActivity(
        lastEditedDocument: recentDocuments.first,
        recentDocuments: recentDocuments
    )
    let row = ProjectRow(project: project, curation: curation, activity: activity)
    return StudioStore(rows: [row])
}
