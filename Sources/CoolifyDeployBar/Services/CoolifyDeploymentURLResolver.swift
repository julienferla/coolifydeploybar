import Foundation

/// Construit une URL vers l’interface web Coolify (hors `/api/v1`) pour un déploiement ou une application.
enum CoolifyDeploymentURLResolver: Sendable {
    private static let uuidRegex = try! NSRegularExpression(
        pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    )

    /// Racine web (ex. `https://coolify.example`) à partir de la même base que le client API.
    static func webRootURL(fromAPIBaseURL baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/api/v1") {
            trimmed = String(trimmed.dropLast("/api/v1".count))
        } else if trimmed.hasSuffix("/api") {
            trimmed = String(trimmed.dropLast("/api".count))
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return URL(string: trimmed)
    }

    /// Résout une URL « ouvrir dans Coolify » : `deployment_url` si présent, sinon chemins connus avec UUID projet/env/app.
    static func resolve(
        apiBaseURL: String,
        item: DeploymentQueueItem,
        selectedApplicationUUID: String,
        routing: ApplicationRoutingDetail?
    ) -> URL? {
        guard let root = webRootURL(fromAPIBaseURL: apiBaseURL) else { return nil }

        if let raw = item.deployment_url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let absolute = URL(string: raw), absolute.scheme != nil {
                return absolute
            }
            if let relative = URL(string: raw, relativeTo: root) {
                return relative.absoluteURL
            }
        }

        let appUUID = applicationUUID(from: item, selectedApplicationUUID: selectedApplicationUUID)
        guard !appUUID.isEmpty else { return root }

        let project = routing?.project_uuid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = routing?.environment_uuid?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let p = project, let e = environment, !p.isEmpty, !e.isEmpty {
            if isPureDeploymentUUID(item.deployment_uuid),
               let dep = pureDeploymentUUID(item.deployment_uuid)
            {
                return pathURL(
                    root,
                    ["project", p, "environment", e, "application", appUUID, "deployment", dep]
                )
            }
            return pathURL(root, ["project", p, "environment", e, "application", appUUID])
        }

        return root
    }

    private static func pathURL(_ root: URL, _ components: [String]) -> URL {
        var u = root
        for c in components {
            u = u.appendingPathComponent(c, isDirectory: false)
        }
        return u
    }

    /// Résolution asynchrone : charge le détail application si `deployment_url` est absent (pour `project_uuid` / `environment_uuid`).
    static func resolveAsync(
        client: CoolifyAPIClient,
        item: DeploymentQueueItem,
        selectedApplicationUUID: String
    ) async -> URL? {
        let base = client.baseURL
        let trimmedURL = item.deployment_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedURL.isEmpty {
            return resolve(apiBaseURL: base, item: item, selectedApplicationUUID: selectedApplicationUUID, routing: nil)
        }

        let appUUID = applicationUUID(from: item, selectedApplicationUUID: selectedApplicationUUID)
        var routing: ApplicationRoutingDetail?
        if !appUUID.isEmpty {
            routing = try? await client.fetchApplicationRouting(uuid: appUUID)
        }
        return resolve(apiBaseURL: base, item: item, selectedApplicationUUID: selectedApplicationUUID, routing: routing)
    }

    /// UUID d’application : segment avant `|` pour les id synthétiques de la file globale, sinon l’app sélectionnée.
    static func applicationUUID(from item: DeploymentQueueItem, selectedApplicationUUID: String) -> String {
        let id = item.deployment_uuid
        if id.contains("|") {
            let first = String(id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUUIDString(trimmed) { return trimmed }
        }
        if isPureDeploymentUUID(id) {
            return selectedApplicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedApplicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPureDeploymentUUID(_ deploymentUUID: String) -> Bool {
        !deploymentUUID.contains("|") && isUUIDString(deploymentUUID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func pureDeploymentUUID(_ deploymentUUID: String) -> String? {
        let t = deploymentUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUUIDString(t) else { return nil }
        return t
    }

    private static func isUUIDString(_ s: String) -> Bool {
        let range = NSRange(s.startIndex ..< s.endIndex, in: s)
        return uuidRegex.firstMatch(in: s, options: [], range: range) != nil
    }
}
