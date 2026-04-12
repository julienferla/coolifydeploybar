import Foundation

struct CoolifyAPIClient: Sendable {
    var baseURL: String
    var token: String

    /// Jeton tel qu’attendu par Coolify (sans préfixe `Bearer`, espaces retirés).
    private func normalizedAPIToken() -> String {
        var t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let bearerPrefix = "bearer "
        if t.lowercased().hasPrefix(bearerPrefix) {
            t = String(t.dropFirst(bearerPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private func normalizedAPIRoot() throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoolifyAPIError.invalidBaseURL }
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/api/v1") {
            guard let u = URL(string: trimmed) else { throw CoolifyAPIError.invalidBaseURL }
            return u
        }
        if trimmed.hasSuffix("/api") {
            guard let u = URL(string: trimmed + "/v1") else { throw CoolifyAPIError.invalidBaseURL }
            return u
        }
        guard let u = URL(string: trimmed + "/api/v1") else { throw CoolifyAPIError.invalidBaseURL }
        return u
    }

    private func request(path: String, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        let root = try normalizedAPIRoot()
        var trimmedPath = path
        if trimmedPath.hasPrefix("/") { trimmedPath.removeFirst() }
        var url = root
        for segment in trimmedPath.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw CoolifyAPIError.invalidBaseURL
            }
            components.queryItems = query
            guard let u = components.url else { throw CoolifyAPIError.invalidBaseURL }
            url = u
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let authToken = normalizedAPIToken()
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw CoolifyAPIError.invalidResponse(statusCode: -1, body: nil)
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw CoolifyAPIError.invalidResponse(statusCode: http.statusCode, body: body)
            }
            return (data, http)
        } catch let e as CoolifyAPIError {
            throw e
        } catch {
            throw CoolifyAPIError.transport(error)
        }
    }

    /// File d'attente globale : déploiements `queued` / `in_progress`.
    func fetchQueuedDeployments() async throws -> [DeploymentQueueItem] {
        let (data, _) = try await request(path: "deployments")
        do {
            return try JSONDecoder().decode([DeploymentQueueItem].self, from: data)
        } catch {
            throw CoolifyAPIError.decoding(error)
        }
    }

    /// Liste des applications (tableau JSON brut).
    func fetchApplications() async throws -> [ApplicationSummary] {
        let (data, _) = try await request(path: "applications")
        do {
            return try JSONDecoder().decode([ApplicationSummary].self, from: data)
        } catch {
            throw CoolifyAPIError.decoding(error)
        }
    }

    /// Historique pour une application : `{ count, deployments }`, parfois sous `data` (Laravel / ressources API),
    /// parfois un tableau de lignes file d’attente, ou (ancien) un tableau d’objets Application.
    func fetchApplicationDeployments(applicationUUID: String, skip: Int = 0, take: Int = 10) async throws
        -> ApplicationDeploymentsPage
    {
        let (data, _) = try await request(
            path: "deployments/applications/\(applicationUUID)",
            query: [
                URLQueryItem(name: "skip", value: String(skip)),
                URLQueryItem(name: "take", value: String(take)),
            ]
        )
        let decoder = JSONDecoder()

        // 1) `{ "data": { "count", "deployments" } }` — si on décodait d’abord la page à la racine, les clés
        //    manquantes donneraient `deployments: []` et `count: 0` sans erreur (succès silencieux vide).
        struct DeploymentsPageInData: Decodable {
            let data: ApplicationDeploymentsPage
        }
        if let wrapped = try? decoder.decode(DeploymentsPageInData.self, from: data) {
            return Self.normalizedDeploymentsPage(wrapped.data)
        }

        // 2) `{ "data": [ … ], "meta": { "total": … } }` (pagination Laravel)
        struct DeploymentsMeta: Decodable {
            let total: Int?
        }
        struct DeploymentsArrayInData: Decodable {
            let data: [DeploymentQueueItem]
            let meta: DeploymentsMeta?
        }
        if let wrapped = try? decoder.decode(DeploymentsArrayInData.self, from: data) {
            let sorted = wrapped.data.sortedByDeploymentDateDescending()
            let total = wrapped.meta?.total ?? sorted.count
            return ApplicationDeploymentsPage(count: max(total, sorted.count), deployments: sorted)
        }

        // 3) `{ "count", "deployments" }` à la racine
        if let page = try? decoder.decode(ApplicationDeploymentsPage.self, from: data) {
            return Self.normalizedDeploymentsPage(page)
        }

        // 4) Tableau de lignes `application_deployment_queue` à la racine
        if let items = try? decoder.decode([DeploymentQueueItem].self, from: data) {
            let sorted = items.sortedByDeploymentDateDescending()
            return ApplicationDeploymentsPage(count: sorted.count, deployments: sorted)
        }

        do {
            let rows = try decoder.decode([CoolifyApplicationAPIRow].self, from: data)
            let items = rows.map { $0.asDeploymentQueueItem() }
            let sorted = items.sortedByDeploymentDateDescending()
            return ApplicationDeploymentsPage(count: sorted.count, deployments: sorted)
        } catch {
            throw CoolifyAPIError.decoding(error)
        }
    }

    private static func normalizedDeploymentsPage(_ page: ApplicationDeploymentsPage) -> ApplicationDeploymentsPage {
        let sorted = page.deployments.sortedByDeploymentDateDescending()
        let count = max(page.count, sorted.count)
        return ApplicationDeploymentsPage(count: count, deployments: sorted)
    }

    /// Détail application pour résoudre `project_uuid` / `environment_uuid` (chemins web Coolify).
    func fetchApplicationRouting(uuid: String) async throws -> ApplicationRoutingDetail {
        let trimmed = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoolifyAPIError.invalidResponse(statusCode: 400, body: "UUID application vide")
        }
        let (data, _) = try await request(path: "applications/\(trimmed)")
        let decoder = JSONDecoder()
        struct Wrapped: Decodable {
            let data: ApplicationRoutingDetail
        }
        if let wrapped = try? decoder.decode(Wrapped.self, from: data) {
            return wrapped.data
        }
        do {
            return try decoder.decode(ApplicationRoutingDetail.self, from: data)
        } catch {
            throw CoolifyAPIError.decoding(error)
        }
    }
}
