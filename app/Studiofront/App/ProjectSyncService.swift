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
    private var persistCurationTask: Task<Void, Never>?
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
            persistCurationNow()
            store.clearLiveRows()
            liveUserID = nil
        case .reconnectRequired:
            await loadCache()
        case .connecting:
            break
        }
    }

    func persistCuration() {
        persistCurationTask?.cancel()
        persistCurationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.persistCurationNow()
        }
    }

    /// Writes curation immediately — used on sign-out and before a full refresh
    /// snapshot save so debounced toggles are not lost.
    func persistCurationNow() {
        persistCurationTask?.cancel()
        persistCurationTask = nil
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
                persistCurationNow()
                applySnapshotToStore()
                return
            }

            guard let remote = projectsResult.value else { return }
            if let etag = projectsResult.etag {
                snapshot.etags["projects"] = etag
            }

            let client = self.client
            let limit = SanityClient.datasetConcurrencyLimit
            // Independent of everything below; only needed once projects are assembled.
            async let fetchedOrganizations = try? client.listOrganizations(token: token)

            var studioHosts: [String: String] = [:]
            var externalStudioHostsFromApps: [String: URL] = [:]
            var studioAppsByProject: [String: [StudioApp]] = [:]
            let orgIDs = Array(Set(remote.compactMap(\.organizationId)))
            await forEachConcurrently(orgIDs, limit: limit) { orgID in
                (try? await client.listStudioApplications(token: token, organizationId: orgID)) ?? []
            } onResult: { apps in
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
            try Task.checkCancellation()

            var datasetsByProject: [String: [Dataset]] = Dictionary(
                uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.datasets) }
            )
            let projectIDs = remote.map(\.id)
            let datasetRequests = projectIDs.map { id in (id: id, etag: force ? nil : snapshot.etags["datasets:\(id)"]) }
            var datasetsError: (any Error)?
            await forEachConcurrently(datasetRequests, limit: limit) { request -> (String, Result<SanityConditional<[RemoteDataset]>, any Error>) in
                do {
                    return (request.id, .success(try await client.listDatasets(token: token, projectId: request.id, etag: request.etag)))
                } catch SanityError.notFound {
                    return (request.id, .success(SanityConditional(value: [], etag: nil, notModified: false)))
                } catch {
                    return (request.id, .failure(error))
                }
            } onResult: { id, outcome in
                switch outcome {
                case let .success(result):
                    if let etag = result.etag {
                        snapshot.etags["datasets:\(id)"] = etag
                    }
                    if !result.notModified, let value = result.value {
                        datasetsByProject[id] = value.map { Dataset(name: $0.name, aclMode: $0.aclMode) }
                    }
                case let .failure(error):
                    datasetsError = datasetsError ?? error
                }
            }
            if let datasetsError { throw datasetsError }
            try Task.checkCancellation()

            // Drop cached etags/activity for projects no longer in `remote` (deleted,
            // moved, or access revoked) so the persisted snapshot doesn't grow forever.
            let validProjectIDs = Set(projectIDs)
            snapshot.etags = snapshot.etags.filter { key, _ in
                if key.hasPrefix("datasets:") {
                    return validProjectIDs.contains(String(key.dropFirst("datasets:".count)))
                }
                if key.hasPrefix("activity:") {
                    return validProjectIDs.contains(String(key.dropFirst("activity:".count)))
                }
                return true
            }
            snapshot.activity = snapshot.activity.filter { validProjectIDs.contains($0.key) }

            var memberProfilesByProject: [String: [String: RemoteMemberProfile]] = [:]
            let memberRequests = remote
                .map { (projectID: $0.id, memberIDs: $0.members.map(\.id)) }
                .filter { !$0.memberIDs.isEmpty }
            await forEachConcurrently(memberRequests, limit: limit) { request in
                let profiles = try? await client.projectMemberProfiles(
                    token: token,
                    projectId: request.projectID,
                    ids: request.memberIDs
                )
                return (request.projectID, profiles ?? [])
            } onResult: { id, profiles in
                memberProfilesByProject[id] = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            }
            try Task.checkCancellation()

            var orgNames: [String: String]
            if let orgs = await fetchedOrganizations {
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
                    brandColorHex: project.color.flatMap(Self.normalizedHex),
                    isArchived: project.isArchived,
                    studioApps: studioApps
                )
            }
            snapshot.cachedAt = Date()
            let curation = mergedCuration(with: remote.map(\.id), userID: userID)
            snapshot.curationByUser[userID] = curation

            let curationByID = Dictionary(uniqueKeysWithValues: curation.map { ($0.projectId, $0) })
            let eligibleIDs = remote.filter { project in
                !(curationByID[project.id]?.isHidden ?? false)
                    && !(store.hideArchivedProjects && project.isArchived)
            }.map(\.id)
            let preferExternal = settings.studioURLPreference == .external
            let studioURLByProject = Dictionary(uniqueKeysWithValues: snapshot.projects.compactMap { project in
                project.resolvedStudioURL(preferExternal: preferExternal).map { (project.id, $0) }
            })
            snapshot.activity = await fetchActivity(
                token: token,
                projectIDs: eligibleIDs,
                datasetsByProject: datasetsByProject,
                studioURLByProject: studioURLByProject,
                previous: snapshot.activity,
                force: force
            )

            guard generation == refreshGeneration else { return }
            persistCurationTask?.cancel()
            persistCurationTask = nil
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
        previous: [String: ProjectActivity],
        force: Bool
    ) async -> [String: ProjectActivity] {
        var result = previous
        let client = self.client
        let requests = projectIDs.compactMap { id -> (id: String, dataset: String, etag: String?, studioURL: URL?)? in
            guard let dataset = Self.primaryDataset(from: datasetsByProject[id] ?? []) else { return nil }
            return (id, dataset, force ? nil : snapshot.etags["activity:\(id)"], studioURLByProject[id])
        }
        await forEachConcurrently(requests, limit: SanityClient.datasetConcurrencyLimit) { request -> (String, ProjectActivity?, String?) in
            let id = request.id
            do {
                let conditional = try await client.recentEditedDocuments(
                    token: token,
                    projectId: id,
                    dataset: request.dataset,
                    etag: request.etag
                )
                if conditional.notModified {
                    return (id, nil, conditional.etag)
                }
                let docs: [RemoteEditedDocument] = conditional.value ?? []
                let recentDocuments = docs.map { doc in
                    EditedDocument(
                        id: doc.id,
                        title: doc.title,
                        typeName: doc.typeName,
                        editedAt: doc.updatedAt,
                        deepLinkURL: request.studioURL.flatMap {
                            Self.editIntentURL(studioURL: $0, documentId: doc.id, typeName: doc.typeName)
                        }
                    )
                }
                return (id, ProjectActivity(
                    lastEditedDocument: recentDocuments.first,
                    recentDocuments: recentDocuments
                ), conditional.etag)
            } catch is CancellationError {
                return (id, nil, nil)
            } catch SanityError.cancelled {
                return (id, nil, nil)
            } catch {
                return (id, ProjectActivity(), nil)
            }
        } onResult: { id, activity, etag in
            if let etag {
                snapshot.etags["activity:\(id)"] = etag
            }
            if let activity {
                result[id] = activity
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
