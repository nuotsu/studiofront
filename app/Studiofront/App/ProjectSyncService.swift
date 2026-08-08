import Foundation
import SanityKit
import StudioStore

@MainActor
final class ProjectSyncService {
    private let store: StudioStore
    private let auth: AuthSession
    private let client: SanityClient
    private var snapshot = PersistedSnapshot()
    private var inFlight: Task<Void, Never>?
    private var refreshGeneration = 0

    init(store: StudioStore, auth: AuthSession, client: SanityClient = .shared) {
        self.store = store
        self.auth = auth
        self.client = client
    }

    func loadCache(applyToStore: Bool = true) {
        let liveCuration = store.curationSnapshot
        let liveOrgs = store.organizationSnapshot
        if let loaded = PersistenceStore.load() {
            snapshot = loaded
            if !liveCuration.isEmpty {
                var byID = Dictionary(uniqueKeysWithValues: snapshot.curation.map { ($0.projectId, $0) })
                for item in liveCuration { byID[item.projectId] = item }
                snapshot.curation = Array(byID.values)
            }
            if !liveOrgs.isEmpty {
                let liveFavorites = Dictionary(uniqueKeysWithValues: liveOrgs.map { ($0.id, $0.isFavorite) })
                snapshot.organizations = snapshot.organizations.map { org in
                    var copy = org
                    if let favorite = liveFavorites[org.id] { copy.isFavorite = favorite }
                    return copy
                }
            }
        } else if !liveCuration.isEmpty || !liveOrgs.isEmpty {
            if !liveCuration.isEmpty { snapshot.curation = liveCuration }
            if !liveOrgs.isEmpty { snapshot.organizations = liveOrgs }
        }
        guard applyToStore else { return }
        if auth.isSignedIn || auth.needsReconnect {
            applySnapshotToStore()
        } else {
            store.clearLiveRows()
        }
    }

    func handleAuthChange() {
        switch auth.status {
        case .signedIn:
            loadCache()
        case .signedOut:
            persistCuration()
            store.clearLiveRows()
        case .reconnectRequired:
            loadCache()
        case .connecting:
            break
        }
    }

    func persistCuration() {
        snapshot.curation = store.curationSnapshot
        snapshot.organizations = store.organizationSnapshot.isEmpty ? snapshot.organizations : store.organizationSnapshot
        PersistenceStore.save(snapshot)
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
            await self.performRefresh(force: force)
            guard generation == self.refreshGeneration else { return }
            self.store.isRefreshing = false
            self.inFlight = nil
        }
    }

    private func performRefresh(force: Bool) async {
        guard let token = try? TokenStore.shared.load(), !token.isEmpty else {
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
                persistCuration()
                applySnapshotToStore()
                return
            }

            guard let remote = projectsResult.value else { return }
            if let etag = projectsResult.etag {
                snapshot.etags["projects"] = etag
            }

            var orgNames = Dictionary(uniqueKeysWithValues: snapshot.organizations.map { ($0.id, $0.name) })
            if let orgs = try? await client.listOrganizations(token: token) {
                orgNames = Dictionary(uniqueKeysWithValues: orgs.map { ($0.id, $0.name) })
                let existingFavorites = Dictionary(uniqueKeysWithValues: snapshot.organizations.map { ($0.id, $0.isFavorite) })
                let liveFavorites = Dictionary(uniqueKeysWithValues: store.organizationSnapshot.map { ($0.id, $0.isFavorite) })
                snapshot.organizations = orgs.map { remote in
                    PersistedOrganization(
                        id: remote.id,
                        name: remote.name,
                        isFavorite: liveFavorites[remote.id] ?? existingFavorites[remote.id] ?? false
                    )
                }
            }

            var studioHosts: [String: String] = [:]
            for orgID in Set(remote.compactMap(\.organizationId)) {
                try Task.checkCancellation()
                guard let apps = try? await client.listStudioApplications(token: token, organizationId: orgID) else {
                    continue
                }
                for app in apps {
                    if let projectId = app.projectId {
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

            let currentUserID = auth.signedInUser?.id
            snapshot.projects = remote.map { project in
                SanityProject(
                    id: project.id,
                    displayName: project.displayName,
                    organizationId: project.organizationId,
                    organizationName: project.organizationId.flatMap { orgNames[$0] } ?? project.organizationId,
                    studioHost: project.studioHost ?? studioHosts[project.id],
                    datasets: datasetsByProject[project.id] ?? [],
                    members: project.members.map { member in
                        Member(id: member.id, displayName: member.id, role: member.role)
                    },
                    currentUserRole: project.members.first(where: { $0.id == currentUserID })?.role,
                    createdAt: project.createdAt == .distantPast ? Date() : project.createdAt,
                    brandColorHex: project.color.flatMap(Self.normalizedHex)
                )
            }
            snapshot.cachedAt = Date()
            snapshot.curation = mergedCuration(with: remote.map(\.id))
            PersistenceStore.save(snapshot)
            applySnapshotToStore()
        } catch is CancellationError {
            return
        } catch SanityError.cancelled {
            return
        } catch SanityError.unauthorized {
            auth.markReconnectRequired()
        } catch {
            applySnapshotToStore()
        }
    }

    private func mergedCuration(with remoteIDs: [String]) -> [ProjectCuration] {
        var byID = Dictionary(uniqueKeysWithValues: snapshot.curation.map { ($0.projectId, $0) })
        for id in remoteIDs where byID[id] == nil {
            byID[id] = ProjectCuration(projectId: id)
        }
        for row in store.rows {
            byID[row.id] = row.curation
        }
        return Array(byID.values)
    }

    private func applySnapshotToStore() {
        let curationByID = Dictionary(uniqueKeysWithValues: snapshot.curation.map { ($0.projectId, $0) })
        let remoteIDs = Set(snapshot.projects.map(\.id))
        var rows: [ProjectRow] = snapshot.projects.map { project in
            ProjectRow(
                project: project,
                curation: curationByID[project.id] ?? ProjectCuration(projectId: project.id),
                activity: ProjectActivity(),
                isUnavailable: false
            )
        }

        for curation in snapshot.curation where !remoteIDs.contains(curation.projectId) {
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
                    activity: ProjectActivity(),
                    isUnavailable: true
                )
            )
        }

        var organizations = snapshot.organizations.map {
            OrganizationRecord(id: $0.id, name: $0.name, isFavorite: $0.isFavorite)
        }
        var knownIDs = Set(organizations.map(\.id))
        for project in snapshot.projects {
            guard let id = project.organizationId, !knownIDs.contains(id) else { continue }
            knownIDs.insert(id)
            organizations.append(
                OrganizationRecord(id: id, name: project.organizationName ?? id, isFavorite: false)
            )
        }

        store.replaceRows(rows, organizations: organizations)
    }

    private static func normalizedHex(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard (cleaned.count == 3 || cleaned.count == 6), cleaned.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return cleaned
    }
}
