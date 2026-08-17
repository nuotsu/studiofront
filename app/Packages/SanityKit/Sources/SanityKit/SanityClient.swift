import Foundation

/// Single network entry point. Typed errors only — never surface `URLError` or tokens.
public actor SanityClient {
    public static let shared = SanityClient()

    public static let datasetConcurrencyLimit = 5

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func currentUser(token: String) async throws -> SanityUser {
        do {
            let dto: UserDTO = try await get(
                path: "\(SanityAPI.version)/users/me",
                token: token
            )
            return SanityUser(
                id: dto.id,
                name: dto.name,
                email: dto.email,
                profileImageURL: dto.profileImage.flatMap(URL.init(string:))
            )
        } catch SanityError.unauthorized {
            throw SanityAuthError.unauthorized
        } catch SanityError.cancelled {
            throw CancellationError()
        } catch SanityError.transport(let message) {
            throw SanityAuthError.transport(message)
        } catch {
            throw SanityAuthError.transport("Couldn’t reach Sanity.")
        }
    }

    public func listProjects(token: String, etag: String? = nil) async throws -> SanityConditional<[RemoteProject]> {
        let result: SanityConditional<[ProjectDTO]> = try await getConditional(
            path: "\(SanityAPI.version)/projects",
            token: token,
            etag: etag
        )
        return result.map { $0.map { $0.asRemote() } }
    }

    public func listDatasets(
        token: String,
        projectId: String,
        etag: String? = nil
    ) async throws -> SanityConditional<[RemoteDataset]> {
        let result: SanityConditional<[DatasetDTO]> = try await getConditional(
            path: "\(SanityAPI.version)/projects/\(projectId)/datasets",
            token: token,
            etag: etag
        )
        return result.map { dtos in
            dtos.map { RemoteDataset(name: $0.name, aclMode: $0.aclMode ?? "public") }
        }
    }

    /// Batched member-profile lookup for `Member.displayName`/`imageURL` — the
    /// project members list itself carries only ids/roles, not names or
    /// avatars. Chunked at 100 ids per call to match Sanity's own documented
    /// batch limit for this endpoint.
    public func projectMemberProfiles(
        token: String,
        projectId: String,
        ids: [String]
    ) async throws -> [RemoteMemberProfile] {
        guard !ids.isEmpty else { return [] }
        var result: [RemoteMemberProfile] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let slice = Array(ids[start..<min(start + 100, ids.count)])
            let dtos: [ProjectUserDTO] = try await get(
                path: "\(SanityAPI.version)/projects/\(projectId)/users/\(slice.joined(separator: ","))",
                token: token
            )
            result += dtos.map {
                RemoteMemberProfile(
                    id: $0.id,
                    displayName: $0.displayName ?? $0.id,
                    imageURL: $0.imageUrl.flatMap(URL.init(string:))
                )
            }
        }
        return result
    }

    public func listOrganizations(token: String) async throws -> [RemoteOrganization] {
        let dtos: [OrganizationDTO] = try await get(
            path: "\(SanityAPI.version)/organizations",
            token: token
        )
        return dtos.map { RemoteOrganization(id: $0.id, name: $0.resolvedName) }
    }

    public func listStudioApplications(
        token: String,
        organizationId: String
    ) async throws -> [RemoteStudioApp] {
        let dtos: [UserApplicationDTO] = try await get(
            path: "\(SanityAPI.userApplicationsVersion)/user-applications",
            token: token,
            query: [
                URLQueryItem(name: "organizationId", value: organizationId),
                URLQueryItem(name: "appType", value: "studio"),
            ]
        )
        return dtos.compactMap { dto in
            guard let host = dto.appHost, !host.isEmpty else { return nil }
            return RemoteStudioApp(projectId: dto.projectId, appHost: host, isExternal: dto.urlType == "external", title: dto.title)
        }
    }

    /// Content query against the project's dataset over the CDN, for activity data
    /// not available from the Management API (§6.3). Never throws for lack of
    /// dataset access — callers should treat `.unauthorized`/`.notFound` as a
    /// normal, quiet "no activity" state rather than a reportable error.
    public func lastEditedDocument(
        token: String,
        projectId: String,
        dataset: String,
        etag: String? = nil
    ) async throws -> SanityConditional<RemoteEditedDocument?> {
        let groq = """
        {
          "published": *[!(_id in path("drafts.**")) && !(_id in path("_.**"))] | order(_updatedAt desc)[0]{_id, _type, _updatedAt, title, name},
          "draft": *[_id in path("drafts.**") && !(_id in path("_.**"))] | order(_updatedAt desc)[0]{_id, _type, _updatedAt, title, name}
        }
        """
        guard var components = URLComponents(
            url: URL(string: "https://\(projectId).apicdn.sanity.io")!,
            resolvingAgainstBaseURL: false
        ) else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }
        components.path = "/\(SanityAPI.version)/data/query/\(dataset)"
        components.queryItems = [URLQueryItem(name: "query", value: groq)]
        guard let url = components.url else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }

        let result: SanityConditional<QueryEnvelope> = try await performGET(url: url, token: token, etag: etag)
        return result.map { envelope in
            RemoteEditedDocument.resolving(published: envelope.published, draft: envelope.draft)
        }
    }

    /// The presence websocket URL, matching exactly what Sanity Studio itself
    /// connects to (`getBifurClient` in `prepareConfig.tsx`): `wss://<projectId
    /// >.api.sanity.io/<presenceVersion>/socket/<dataset>?tag=...`. Pure — does
    /// not open a connection.
    public nonisolated func socketURL(projectId: String, dataset: String) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(projectId).api.sanity.io"
        components.path = "/\(SanityAPI.presenceVersion)/socket/\(dataset)"
        components.queryItems = [URLQueryItem(name: "tag", value: "dev.nuotsu.studiofront.presence")]
        guard let url = components.url else {
            preconditionFailure("socketURL produced an invalid URL for project \(projectId)")
        }
        return url
    }

    /// Recent editors of a dataset over the documented History API's
    /// transactions endpoint (§7.2's fallback presence source) — never the
    /// CDN, since the History API isn't CDN-fronted. Real per-project API
    /// quota per §6.2; callers should poll conservatively.
    public func recentEditors(
        token: String,
        projectId: String,
        dataset: String,
        since: Date,
        limit: Int = 50
    ) async throws -> [RemoteRecentEdit] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(projectId).api.sanity.io"
        components.path = "/\(SanityAPI.version)/data/history/\(dataset)/transactions"
        components.queryItems = [
            URLQueryItem(name: "fromTime", value: ISO8601DateFormatter().string(from: since)),
            URLQueryItem(name: "excludeContent", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "tag", value: "dev.nuotsu.studiofront.presence"),
        ]
        guard let url = components.url else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }
        let lines = try await performNDJSONGET(url: url, token: token)
        return lines.compactMap { line in
            guard let entry = try? SanityJSON.decoder.decode(TransactionLogEntryDTO.self, from: line) else {
                return nil
            }
            return RemoteRecentEdit(authorId: entry.author, updatedAt: entry.timestamp, documentIDs: entry.documentIDs)
        }
    }

    /// Batched `{_id, _type}` lookup for building edit-intent links — presence
    /// data (both the realtime socket and the History API) carries a
    /// document's id but never its schema type. CDN-fronted like
    /// `lastEditedDocument`, since this is read-only lookup data, not
    /// something that needs to bypass caching.
    public func documentTypes(
        token: String,
        projectId: String,
        dataset: String,
        ids: [String]
    ) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let groq = "*[_id in $ids]{_id, _type}"
        guard var components = URLComponents(
            url: URL(string: "https://\(projectId).apicdn.sanity.io")!,
            resolvingAgainstBaseURL: false
        ) else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }
        components.path = "/\(SanityAPI.version)/data/query/\(dataset)"
        let idsParam = "[" + ids.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        components.queryItems = [
            URLQueryItem(name: "query", value: groq),
            URLQueryItem(name: "$ids", value: idsParam),
        ]
        guard let url = components.url else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }
        let conditional: SanityConditional<ArrayQueryEnvelope<DocumentTypeProjectionDTO>> = try await performGET(url: url, token: token, etag: nil)
        guard let envelope = conditional.value else { throw SanityError.decoding }
        return Dictionary(uniqueKeysWithValues: envelope.result.map { ($0.id, $0.type) })
    }

    // MARK: - HTTP

    private func get<T: Decodable & Sendable>(
        path: String,
        token: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let result: SanityConditional<T> = try await getConditional(path: path, token: token, query: query, etag: nil)
        guard let value = result.value else { throw SanityError.decoding }
        return value
    }

    private func getConditional<T: Decodable & Sendable>(
        path: String,
        token: String,
        query: [URLQueryItem] = [],
        etag: String?
    ) async throws -> SanityConditional<T> {
        var url = SanityAPI.baseURL
        for component in path.split(separator: "/") {
            url = url.appending(path: String(component))
        }
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query
            guard let resolved = components?.url else {
                throw SanityError.transport("Couldn’t reach Sanity.")
            }
            url = resolved
        }
        return try await performGET(url: url, token: token, etag: etag)
    }

    private func performGET<T: Decodable & Sendable>(
        url: URL,
        token: String,
        etag: String?
    ) async throws -> SanityConditional<T> {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw SanityError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw SanityError.cancelled
        } catch {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }

        let responseETag = http.value(forHTTPHeaderField: "ETag")

        switch http.statusCode {
        case 304:
            return SanityConditional(value: nil, etag: responseETag ?? etag, notModified: true)
        case 200:
            do {
                let decoded = try SanityJSON.decoder.decode(T.self, from: data)
                return SanityConditional(value: decoded, etag: responseETag, notModified: false)
            } catch {
                throw SanityError.decoding
            }
        case 401, 403:
            throw SanityError.unauthorized
        case 404:
            throw SanityError.notFound
        default:
            throw SanityError.transport("Sanity returned an unexpected response.")
        }
    }

    /// Fetches and splits an NDJSON response body into per-line `Data`. A line
    /// that fails to decode downstream (including error lines, e.g.
    /// `{"error": {...}}`) is simply dropped by the caller rather than failing
    /// the whole batch.
    private func performNDJSONGET(url: URL, token: String) async throws -> [Data] {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw SanityError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw SanityError.cancelled
        } catch {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw SanityError.transport("Couldn’t reach Sanity.")
        }

        switch http.statusCode {
        case 200:
            return data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
        case 401, 403:
            throw SanityError.unauthorized
        case 404:
            throw SanityError.notFound
        default:
            throw SanityError.transport("Sanity returned an unexpected response.")
        }
    }

    private struct UserDTO: Decodable {
        var id: String
        var name: String
        var email: String?
        var profileImage: String?
    }
}
