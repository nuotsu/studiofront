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
            return RemoteStudioApp(projectId: dto.projectId, appHost: host, isExternal: dto.urlType == "external")
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

    private struct UserDTO: Decodable {
        var id: String
        var name: String
        var email: String?
        var profileImage: String?
    }
}
