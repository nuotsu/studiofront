import Foundation

public enum FixtureData {
    public static let organizationOrder: [(id: String, name: String)] = [
        ("orgq7f2", "Northwind Group"),
        ("orgfj91", "Fjord Media"),
        ("orghd44", "Halden & Co"),
        ("orgas08", "Aster Health Partners"),
        ("orgks01", "Kessler Studio"),
    ]

    public static func rows(now: Date = Date()) -> [ProjectRow] {
        let jr = Member(id: "user-jr", displayName: "Jordan Reed", initials: "JR")
        let mk = Member(id: "user-mk", displayName: "Morgan Kim", initials: "MK")
        let al = Member(id: "user-al", displayName: "Alex Lind", initials: "AL")
        let ts = Member(id: "user-ts", displayName: "Taylor Singh", initials: "TS")
        let bv = Member(id: "user-bv", displayName: "Blake Vogt", initials: "BV")
        let dp = Member(id: "user-dp", displayName: "Dana Park", initials: "DP")
        let rn = Member(id: "user-rn", displayName: "Riley Nguyen", initials: "RN")

        func site(_ host: String?) -> [NamedLink] {
            guard let host, let url = URL(string: "https://\(host)") else { return [] }
            return [NamedLink(label: host, url: url)]
        }

        func row(
            id: String,
            name: String,
            orgName: String,
            orgId: String,
            dataset: String,
            favorite: Bool,
            brand: String?,
            siteHost: String?,
            docTitle: String,
            docType: String,
            editedAgo: TimeInterval,
            deployedAgo: TimeInterval?,
            presence: [Member]
        ) -> ProjectRow {
            let project = SanityProject(
                id: id,
                displayName: name,
                organizationId: orgId,
                organizationName: orgName,
                studioHost: id,
                datasets: [Dataset(name: dataset, aclMode: dataset == "production" ? "public" : "private")],
                members: presence,
                currentUserRole: "editor",
                createdAt: now.addingTimeInterval(-90 * 24 * 3600),
                brandColorHex: brand
            )
            let curation = ProjectCuration(
                projectId: id,
                isFavorite: favorite,
                frontendLinks: site(siteHost)
            )
            let activity = ProjectActivity(
                lastDeployedAt: deployedAgo.map { now.addingTimeInterval(-$0) },
                lastEditedDocument: EditedDocument(
                    title: docTitle,
                    typeName: docType,
                    editedAt: now.addingTimeInterval(-editedAgo)
                ),
                activeUsers: presence
            )
            return ProjectRow(project: project, curation: curation, activity: activity)
        }

        return [
            row(
                id: "nw8f3k2a", name: "Northwind Coffee", orgName: "Northwind Group", orgId: "orgq7f2",
                dataset: "production", favorite: true, brand: "6f4a2e", siteHost: "northwindcoffee.com",
                docTitle: "Homepage Hero", docType: "page", editedAgo: 2 * 3600, deployedAgo: 3 * 3600,
                presence: [jr, mk]
            ),
            row(
                id: "fj4m7t1e", name: "Fjord Media Editorial", orgName: "Fjord Media", orgId: "orgfj91",
                dataset: "production", favorite: true, brand: "12324a", siteHost: "fjordmedia.no",
                docTitle: "Issue 14 — Cover Story", docType: "article", editedAgo: 6 * 60, deployedAgo: 22 * 60,
                presence: [al, ts, bv]
            ),
            row(
                id: "nw1c9p4x", name: "Northwind Wholesale", orgName: "Northwind Group", orgId: "orgq7f2",
                dataset: "staging", favorite: false, brand: "6f4a2e", siteHost: "wholesale.northwindcoffee.com",
                docTitle: "Wholesale FAQ", docType: "page", editedAgo: 26 * 3600, deployedAgo: 2 * 24 * 3600,
                presence: []
            ),
            row(
                id: "fj9k2b6d", name: "Fjord Media Careers", orgName: "Fjord Media", orgId: "orgfj91",
                dataset: "production", favorite: false, brand: nil, siteHost: "fjordmedia.no/careers",
                docTitle: "Open Roles", docType: "page", editedAgo: 3 * 24 * 3600, deployedAgo: 5 * 24 * 3600,
                presence: []
            ),
            row(
                id: "hd3x8v5q", name: "Halden & Co Storefront", orgName: "Halden & Co", orgId: "orghd44",
                dataset: "production", favorite: false, brand: "171717", siteHost: "halden.co",
                docTitle: "SS26 Lookbook", docType: "collection", editedAgo: 40 * 60, deployedAgo: 3600,
                presence: [dp]
            ),
            row(
                id: "hd7n2j8w", name: "Halden & Co Journal", orgName: "Halden & Co", orgId: "orghd44",
                dataset: "development", favorite: false, brand: nil, siteHost: nil,
                docTitle: "Draft: Atelier Visit", docType: "article", editedAgo: 20 * 3600, deployedAgo: nil,
                presence: []
            ),
            row(
                id: "as6q1w9r", name: "Aster Health", orgName: "Aster Health Partners", orgId: "orgas08",
                dataset: "production", favorite: false, brand: "2fa37c", siteHost: "asterhealth.com",
                docTitle: "Clinic Locations", docType: "location", editedAgo: 4 * 3600, deployedAgo: 6 * 3600,
                presence: [rn]
            ),
            row(
                id: "as2v8m3c", name: "Aster Health Docs", orgName: "Aster Health Partners", orgId: "orgas08",
                dataset: "staging", favorite: false, brand: "2fa37c", siteHost: "docs.asterhealth.com",
                docTitle: "Patient Onboarding", docType: "guide", editedAgo: 6 * 24 * 3600, deployedAgo: 9 * 24 * 3600,
                presence: []
            ),
            row(
                id: "in2z5y7u", name: "Studio Kit (Internal)", orgName: "Kessler Studio", orgId: "orgks01",
                dataset: "production", favorite: true, brand: nil, siteHost: nil,
                docTitle: "Component Library Notes", docType: "note", editedAgo: 8 * 24 * 3600, deployedAgo: 12 * 24 * 3600,
                presence: []
            ),
            row(
                id: "in7t4r2m", name: "Client Intake", orgName: "Kessler Studio", orgId: "orgks01",
                dataset: "development", favorite: false, brand: nil, siteHost: nil,
                docTitle: "Intake Form Copy", docType: "form", editedAgo: 5 * 3600, deployedAgo: 4 * 24 * 3600,
                presence: [mk, jr]
            ),
        ]
    }
}
