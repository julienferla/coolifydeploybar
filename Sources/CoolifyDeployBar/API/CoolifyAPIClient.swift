import Foundation

struct CoolifyAPIClient: Sendable {
    var baseURL: String
    var token: String

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
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    /// Historique pour une application : `{ count, deployments }`.
    func fetchApplicationDeployments(applicationUUID: String, skip: Int = 0, take: Int = 15) async throws
        -> ApplicationDeploymentsPage
    {
        let (data, _) = try await request(
            path: "deployments/applications/\(applicationUUID)",
            query: [
                URLQueryItem(name: "skip", value: String(skip)),
                URLQueryItem(name: "take", value: String(take)),
            ]
        )
        do {
            return try JSONDecoder().decode(ApplicationDeploymentsPage.self, from: data)
        } catch {
            throw CoolifyAPIError.decoding(error)
        }
    }
}
