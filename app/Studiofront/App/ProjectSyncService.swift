import Foundation
import SanityKit
import StudioStore

@MainActor
final class ProjectSyncService {
    private let store: StudioStore
    private let auth: AuthSession
    private let settings: AppSettings
    private let client: SanityClient
    private var snapshot = PersistedSnapshot()
    private var inFlight: Task<Void, Never>?
    private var refreshGeneration = 0
    /// Which user's data `store.rows`/`store.organizations` currently reflect.
    /// Lets `loadCache`/`persistCuration` tell live in-memory edits apart from
    /// a *different* account's leftover state instead of assuming they always
    /// belong to whoever is signed in right now.
    private var liveUserID: String?

    private var currentUserID: String? {
        auth.signedInUser?.id ?? (auth.needsReconnect ? snapshot.lastActiveUserID : nil)
    }

    init(store: StudioStore, auth: AuthSession, settings: AppSettings, client: SanityClient = .shared) {
        self.store = store
        self.auth = auth
        self.settings = settings
        self.client = client
    }

    func loadCache(applyToStore: Bool = true) async {
        let userID = currentUserID
        let liveMatchesUser = userID != nil && liveUserID == userID
        let liveCuration = liveMatchesUser ? store.curationSnapshot : []
        let liveOrgs = liveMatchesUser ? store.organizationSnapshot : []

        if let loaded = await PersistenceStore.load() {
            snapshot = loaded
        }
        if let signedInID = auth.signedInUser?.id {
            snapshot.lastActiveUserID = signedInID
        }
        if let userID {
            mergeLiveCurationAndOrgs(curation: liveCuration, orgs: liveOrgs, into: userID)
        }
        guard applyToStore else { return }
        if auth.isSignedIn || auth.needsReconnect {
            applySnapshotToStore()
        } else {
            store.clearLiveRows()
        }
    }

    func handleAuthChange() async {
        switch auth.status {
        case .signedIn:
            await loadCache()
        case .signedOut:
            persistCuration()
            store.clearLiveRows()
            liveUserID = nil
        case .reconnectRequired:
            await loadCache()
        case .connecting:
            break
        }
    }

    func persistCuration() {
        guard let userID = currentUserID ?? liveUserID else { return }
        mergeLiveCurationAndOrgs(curation: store.curationSnapshot, orgs: store.organizationSnapshot, into: userID)
        PersistenceStore.save(snapshot)
    }

    /// Folds the store's currently live curation/org-favorite state (if any)
    /// into `snapshot`, scoped to `userID`. Org id/name stay in the shared
    /// `snapshot.organizations` directory; only the favorite/pin flag is
    /// per-user.
    private func mergeLiveCurationAndOrgs(curation liveCuration: [ProjectCuration], orgs liveOrgs: [PersistedOrganization], into userID: String) {
        if !liveCuration.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: (snapshot.curationByUser[userID] ?? []).map { ($0.projectId, $0) })
            for item in liveCuration { byID[item.projectId] = item }
            snapshot.curationByUser[userID] = Array(byID.values)
        }
        if !liveOrgs.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: snapshot.organizations.map { ($0.id, $0) })
            for org in liveOrgs { byID[org.id] = PersistedOrganization(id: org.id, name: org.name) }
            snapshot.organizations = Array(byID.values)
            snapshot.organizationFavoritesByUser[userID] = Set(liveOrgs.filter(\.isFavorite).map(\.id))
        }
    }

    func cancel() {
        refreshGeneration += 1
        inFlight?.cancel()
        inFlight = nil
        store.isRefreshing = false
    }

    func refreshIfStale(interval: TimeInterval) {
        guard auth.isSignedIn else { return }
        let stale: Bool
        if snapshot.projects.isEmpty {
            stale = true
        } else if let cachedAt = snapshot.cachedAt {
            stale = Date().timeIntervalSince(cachedAt) >= interval
        } else {
            stale = true
        }
        if stale {
            refresh(force: false)
        }
    }

    func refresh(force: Bool) {
        guard auth.isSignedIn else { return }
        inFlight?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        store.isRefreshing = true
        inFlight = Task {
            await self.performRefresh(force: force, generation: generation)
            guard generation == self.refreshGeneration else { return }
            self.store.isRefreshing = false
            self.inFlight = nil
        }
    }

    private func performRefresh(force: Bool, generation: Int) async {
        guard let token = try? TokenStore.shared.load(), !token.isEmpty else {
            auth.markReconnectRequired()
            return
        }
        guard let userID = auth.signedInUser?.id else {
            auth.markReconnectRequired()
            return
        }

        do {
            try Task.checkCancellation()
            let projectsResult = try await client.listProjects(
                token: token,
                etag: force ? nil : snapshot.etags["projects"]
            )

            if projectsResult.notModified, !snapshot.projects.isEmpty, !force {
                snapshot.cachedAt = Date()
                if let etag = projectsResult.etag { snapshot.etags["projects"] = etag }
                guard generation == refreshGeneration else { return }
                persistCuration()
                applySnapshotToStore()
                return
            }

            guard let remote = projectsResult.value else { return }
            if let etag = projectsResult.etag {
                snapshot.etags["projects"] = etag
            }

            var orgNames: [String: String]
            if let orgs = try? await client.listOrganizations(token: token) {
                orgNames = Dictionary(uniqueKeysWithValues: orgs.map { ($0.id, $0.name) })
                snapshot.organizations = orgs.map { PersistedOrganization(id: $0.id, name: $0.name) }
                let existingFavorites = snapshot.organizationFavoritesByUser[userID] ?? []
                let liveFavorites = Dictionary(uniqueKeysWithValues: store.organizationSnapshot.map { ($0.id, $0.isFavorite) })
                var favoriteIDs = existingFavorites
                for org in orgs {
                    guard let live = liveFavorites[org.id] else { continue }
                    if live { favoriteIDs.insert(org.id) } else { favoriteIDs.remove(org.id) }
                }
                snapshot.organizationFavoritesByUser[userID] = favoriteIDs
            } else {
                orgNames = Dictionary(uniqueKeysWithValues: snapshot.organizations.map { ($0.id, $0.name) })
            }

            var studioHosts: [String: String] = [:]
            var externalStudioHostsFromApps: [String: URL] = [:]
            var studioAppsByProject: [String: [StudioApp]] = [:]
            for orgID in Set(remote.compactMap(\.organizationId)) {
                try Task.checkCancellation()
                guard let apps = try? await client.listStudioApplications(token: token, organizationId: orgID) else {
                    continue
                }
                for app in apps {
                    guard let projectId = app.projectId else { continue }
                    studioAppsByProject[projectId, default: []].append(
                        StudioApp(host: app.appHost, isExternal: app.isExternal, title: app.title)
                    )
                    if app.isExternal {
                        if let url = URL(string: app.appHost) {
                            externalStudioHostsFromApps[projectId] = url
                        }
                    } else {
                        studioHosts[projectId] = app.appHost
                    }
                }
            }

            var datasetsByProject: [String: [Dataset]] = Dictionary(
                uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.datasets) }
            )
            let projectIDs = remote.map(\.id)
            let limit = SanityClient.datasetConcurrencyLimit
            let client = self.client
            for start in stride(from: 0, to: projectIDs.count, by: limit) {
                try Task.checkCancellation()
                let end = min(start + limit, projectIDs.count)
                let slice = Array(projectIDs[start..<end])
                try await withThrowingTaskGroup(of: (String, SanityConditional<[RemoteDataset]>).self) { group in
                    for id in slice {
                        let etag = force ? nil : snapshot.etags["datasets:\(id)"]
                        group.addTask {
                            do {
                                return (id, try await client.listDatasets(token: token, projectId: id, etag: etag))
                            } catch SanityError.notFound {
                                return (id, SanityConditional(value: [], etag: nil, notModified: false))
                            }
                        }
                    }
                    for try await (id, result) in group {
                        if let etag = result.etag {
                            snapshot.etags["datasets:\(id)"] = etag
                        }
                        if result.notModified { continue }
                        if let value = result.value {
                            datasetsByProject[id] = value.map { Dataset(name: $0.name, aclMode: $0.aclMode) }
                        }
                    }
                }
            }

            // Drop cached etags/activity for projects no longer in `remote` (deleted,
            // moved, or access revoked) so the persisted snapshot doesn't grow forever.
            let validProjectIDs = Set(projectIDs)
            snapshot.etags = snapshot.etags.filter { key, _ in
                guard key.hasPrefix("datasets:") else { return true }
                return validProjectIDs.contains(String(key.dropFirst("datasets:".count)))
            }
            snapshot.activity = snapshot.activity.filter { validProjectIDs.contains($0.key) }

            var memberProfilesByProject: [String: [String: RemoteMemberProfile]] = [:]
            for start in stride(from: 0, to: remote.count, by: limit) {
                try Task.checkCancellation()
                let slice = Array(remote[start..<min(start + limit, remote.count)])
                await withTaskGroup(of: (String, [RemoteMemberProfile]).self) { group in
                    for project in slice {
                        let ids = project.members.map(\.id)
                        group.addTask {
                            guard !ids.isEmpty else { return (project.id, []) }
                            let profiles = try? await client.projectMemberProfiles(
                                token: token,
                                projectId: project.id,
                                ids: ids
                            )
                            return (project.id, profiles ?? [])
                        }
                    }
                    for await (id, profiles) in group {
                        memberProfilesByProject[id] = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
                    }
                }
            }

            snapshot.projects = remote.map { project in
                let resolvedHost = project.studioHost ?? studioHosts[project.id]
                let resolvedExternal = externalStudioHostsFromApps[project.id] ?? project.externalStudioHost
                var studioApps = studioAppsByProject[project.id] ?? []
                // `/user-applications` doesn't cover every project (e.g. the
                // deprecated `metadata.externalStudioHost` field) — synthesize
                // an entry so the dropdown still lists it.
                if !studioApps.contains(where: { !$0.isExternal }), let resolvedHost, !resolvedHost.isEmpty {
                    studioApps.append(StudioApp(host: resolvedHost, isExternal: false))
                }
                if !studioApps.contains(where: \.isExternal), let resolvedExternal {
                    studioApps.append(StudioApp(host: resolvedExternal.absoluteString, isExternal: true))
                }
                return SanityProject(
                    id: project.id,
                    displayName: project.displayName,
                    organizationId: project.organizationId,
                    organizationName: project.organizationId.flatMap { orgNames[$0] } ?? project.organizationId,
                    studioHost: resolvedHost,
                    // `/user-applications` is the current, more accurate source
                    // (confirmed against the live API: SanityPress 2023's app entry
                    // points at a different, newer domain than its own deprecated
                    // metadata.externalStudioHost still records) — prefer it.
                    externalStudioHost: resolvedExternal,
                    datasets: datasetsByProject[project.id] ?? [],
                    members: project.members.map { member in
                        let profile = memberProfilesByProject[project.id]?[member.id]
                        return Member(
                            id: member.id,
                            displayName: profile?.displayName ?? "",
                            imageURL: profile?.imageURL,
                            role: member.role
                        )
                    },
                    currentUserRole: project.members.first(where: { $0.id == userID })?.role,
                    createdAt: project.createdAt == .distantPast ? Date() : project.createdAt,
                    brandColorHex: project.color.flatMap(Self.normalizedHex),
                    isArchived: project.isArchived,
                    studioApps: studioApps
                )
            }
            snapshot.cachedAt = Date()
            let curation = mergedCuration(with: remote.map(\.id), userID: userID)
            snapshot.curationByUser[userID] = curation

            let curationByID = Dictionary(uniqueKeysWithValues: curation.map { ($0.projectId, $0) })
            let eligibleIDs = projectIDs.filter { !(curationByID[$0]?.isHidden ?? false) }
            let preferExternal = settings.studioURLPreference == .external
            let studioURLByProject = Dictionary(uniqueKeysWithValues: snapshot.projects.compactMap { project in
                project.resolvedStudioURL(preferExternal: preferExternal).map { (project.id, $0) }
            })
            snapshot.activity = await fetchActivity(
                token: token,
                projectIDs: eligibleIDs,
                datasetsByProject: datasetsByProject,
                studioURLByProject: studioURLByProject,
                previous: snapshot.activity
            )

            guard generation == refreshGeneration else { return }
            PersistenceStore.save(snapshot)
            applySnapshotToStore()
        } catch is CancellationError {
            return
        } catch SanityError.cancelled {
            return
        } catch SanityError.unauthorized {
            auth.markReconnectRequired()
        } catch {
            guard generation == refreshGeneration else { return }
            applySnapshotToStore()
        }
    }

    /// Fetches the recently-edited documents per project (§6.3). Per-project
    /// failures — including lack of dataset access, which is expected and not
    /// every user token grants read access to every org's datasets — resolve
    /// to an empty `ProjectActivity` rather than surfacing an error or
    /// triggering reconnect. Cancellation leaves the project's previous
    /// cached value untouched.
    private func fetchActivity(
        token: String,
        projectIDs: [String],
        datasetsByProject: [String: [Dataset]],
        studioURLByProject: [String: URL],
        previous: [String: ProjectActivity]
    ) async -> [String: ProjectActivity] {
        var result = previous
        let limit = SanityClient.datasetConcurrencyLimit
        let client = self.client
        for start in stride(from: 0, to: projectIDs.count, by: limit) {
            if Task.isCancelled { break }
            let end = min(start + limit, projectIDs.count)
            let slice = Array(projectIDs[start..<end])
            await withTaskGroup(of: (String, ProjectActivity?).self) { group in
                for id in slice {
                    guard let dataset = Self.primaryDataset(from: datasetsByProject[id] ?? []) else { continue }
                    group.addTask {
                        do {
                            let conditional = try await client.recentEditedDocuments(
                                token: token,
                                projectId: id,
                                dataset: dataset
                            )
                            let docs: [RemoteEditedDocument] = conditional.value ?? []
                            let recentDocuments = docs.map { doc in
                                EditedDocument(
                                    title: doc.title,
                                    typeName: doc.typeName,
                                    editedAt: doc.updatedAt,
                                    deepLinkURL: studioURLByProject[id].flatMap {
                                        Self.editIntentURL(studioURL: $0, documentId: doc.id, typeName: doc.typeName)
                                    }
                                )
                            }
                            return (id, ProjectActivity(
                                lastEditedDocument: recentDocuments.first,
                                recentDocuments: recentDocuments
                            ))
                        } catch is CancellationError {
                            return (id, nil)
                        } catch SanityError.cancelled {
                            return (id, nil)
                        } catch {
                            return (id, ProjectActivity())
                        }
                    }
                }
                for await (id, activity) in group {
                    if let activity {
                        result[id] = activity
                    }
                }
            }
        }
        return result
    }

    /// Sanity's documented edit-intent URL format:
    /// `<studioURL>/intent/edit/id=<id>;type=<type>`. Drafts are stored under
    /// `drafts.<id>` — Studio's editor resolves either draft or published from
    /// the bare id, so the prefix is stripped before building the link.
    /// Also used by `PresenceCoordinator` to build deep links for presence
    /// avatars — kept as the one place this URL format is built.
    nonisolated static func editIntentURL(studioURL: URL, documentId: String, typeName: String) -> URL? {
        let draftsPrefix = "drafts."
        let canonicalId = documentId.hasPrefix(draftsPrefix) ? String(documentId.dropFirst(draftsPrefix.count)) : documentId
        var string = studioURL.absoluteString
        if string.hasSuffix("/") { string.removeLast() }
        return URL(string: "\(string)/intent/edit/id=\(canonicalId);type=\(typeName)")
    }

    /// Also used by `PresenceCoordinator` to pick a project's dataset for
    /// presence connections/polls — kept as the one place this choice is made.
    static func primaryDataset(from datasets: [Dataset]) -> String? {
        if datasets.contains(where: { $0.name == "production" }) { return "production" }
        return datasets.map(\.name).sorted().first
    }

    private func mergedCuration(with remoteIDs: [String], userID: String) -> [ProjectCuration] {
        var byID = Dictionary(uniqueKeysWithValues: (snapshot.curationByUser[userID] ?? []).map { ($0.projectId, $0) })
        for id in remoteIDs where byID[id] == nil {
            byID[id] = ProjectCuration(projectId: id)
        }
        for row in store.rows {
            byID[row.id] = row.curation
        }
        return Array(byID.values)
    }

    private func applySnapshotToStore() {
        let userID = currentUserID
        let curation = userID.flatMap { snapshot.curationByUser[$0] } ?? []
        let favoriteOrgIDs = userID.flatMap { snapshot.organizationFavoritesByUser[$0] } ?? []
        let curationByID = Dictionary(uniqueKeysWithValues: curation.map { ($0.projectId, $0) })
        let remoteIDs = Set(snapshot.projects.map(\.id))
        var rows: [ProjectRow] = snapshot.projects.map { project in
            ProjectRow(
                project: project,
                curation: curationByID[project.id] ?? ProjectCuration(projectId: project.id),
                activity: snapshot.activity[project.id] ?? ProjectActivity(),
                isUnavailable: false
            )
        }

        for curation in curation where !remoteIDs.contains(curation.projectId) {
            let kept = curation.isFavorite || curation.nickname != nil
                || !curation.frontendLinks.isEmpty || !curation.extraStudioLinks.isEmpty
            guard kept else { continue }
            rows.append(
                ProjectRow(
                    project: SanityProject(
                        id: curation.projectId,
                        displayName: curation.nickname ?? curation.projectId
                    ),
                    curation: curation,
                    activity: snapshot.activity[curation.projectId] ?? ProjectActivity(),
                    isUnavailable: true
                )
            )
        }

        var organizations = snapshot.organizations.map {
            OrganizationRecord(id: $0.id, name: $0.name, isFavorite: favoriteOrgIDs.contains($0.id))
        }
        var knownIDs = Set(organizations.map(\.id))
        for project in snapshot.projects {
            guard let id = project.organizationId, !knownIDs.contains(id) else { continue }
            knownIDs.insert(id)
            organizations.append(
                OrganizationRecord(id: id, name: project.organizationName ?? id, isFavorite: favoriteOrgIDs.contains(id))
            )
        }

        store.replaceRows(rows, organizations: organizations)
        liveUserID = userID
    }

    private static func normalizedHex(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard (cleaned.count == 3 || cleaned.count == 6), cleaned.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return cleaned
    }
}
