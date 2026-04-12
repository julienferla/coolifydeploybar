import Foundation

/// Ligne `application_deployment_queue` exposée par l'API (champs fréquents + optionnels).
struct DeploymentQueueItem: Codable, Identifiable, Hashable {
    var id: String { deployment_uuid }

    let deployment_uuid: String
    let status: String
    let application_name: String?
    let application_id: Int?
    let commit: String?
    let commit_message: String?
    let created_at: String?
    let updated_at: String?
    let server_name: String?
    let deployment_url: String?
    let force_rebuild: Bool?
    let restart_only: Bool?
    let rollback: Bool?

    private enum CodingKeys: String, CodingKey {
        case deployment_uuid, status, application_name, application_id
        case commit, commit_message, created_at, updated_at
        case server_name, deployment_url, force_rebuild, restart_only, rollback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deployment_uuid = try c.decode(String.self, forKey: .deployment_uuid)
        status = try c.decode(String.self, forKey: .status)
        application_name = try c.decodeIfPresent(String.self, forKey: .application_name)
        application_id = Self.decodeFlexibleInt(from: c, key: .application_id)
        commit = try c.decodeIfPresent(String.self, forKey: .commit)
        commit_message = try c.decodeIfPresent(String.self, forKey: .commit_message)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
        server_name = try c.decodeIfPresent(String.self, forKey: .server_name)
        deployment_url = try c.decodeIfPresent(String.self, forKey: .deployment_url)
        // Coolify / Laravel : colonnes tinyint souvent sérialisées en 0/1 (Int), pas en true/false JSON.
        force_rebuild = Self.decodeFlexibleBool(from: c, key: .force_rebuild)
        restart_only = Self.decodeFlexibleBool(from: c, key: .restart_only)
        rollback = Self.decodeFlexibleBool(from: c, key: .rollback)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deployment_uuid, forKey: .deployment_uuid)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(application_name, forKey: .application_name)
        if let application_id {
            try c.encode(application_id, forKey: .application_id)
        }
        try c.encodeIfPresent(commit, forKey: .commit)
        try c.encodeIfPresent(commit_message, forKey: .commit_message)
        try c.encodeIfPresent(created_at, forKey: .created_at)
        try c.encodeIfPresent(updated_at, forKey: .updated_at)
        try c.encodeIfPresent(server_name, forKey: .server_name)
        try c.encodeIfPresent(deployment_url, forKey: .deployment_url)
        try c.encodeIfPresent(force_rebuild, forKey: .force_rebuild)
        try c.encodeIfPresent(restart_only, forKey: .restart_only)
        try c.encodeIfPresent(rollback, forKey: .rollback)
    }

    private static func decodeFlexibleInt(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        guard c.contains(key) else { return nil }
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key) { return Int(s) }
        return nil
    }

    /// Tolère `true` / `false`, `0` / `1`, ou chaînes `"0"` / `"1"` / `"true"` / `"false"`.
    private static func decodeFlexibleBool(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool? {
        guard c.contains(key) else { return nil }
        if (try? c.decodeNil(forKey: key)) == true { return nil }
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(t) { return true }
            if ["0", "false", "no", "off", ""].contains(t) { return false }
        }
        return nil
    }

    /// Construit une ligne « file / historique » à partir d’un objet Application renvoyé par
    /// `GET /api/v1/deployments/applications/{uuid}` (tableau JSON, pas `{ count, deployments }`).
    init(
        deployment_uuid: String,
        status: String,
        application_name: String?,
        application_id: Int?,
        commit: String?,
        commit_message: String?,
        created_at: String?,
        updated_at: String?,
        server_name: String?,
        deployment_url: String?,
        force_rebuild: Bool?,
        restart_only: Bool?,
        rollback: Bool?
    ) {
        self.deployment_uuid = deployment_uuid
        self.status = status
        self.application_name = application_name
        self.application_id = application_id
        self.commit = commit
        self.commit_message = commit_message
        self.created_at = created_at
        self.updated_at = updated_at
        self.server_name = server_name
        self.deployment_url = deployment_url
        self.force_rebuild = force_rebuild
        self.restart_only = restart_only
        self.rollback = rollback
    }
}

struct ApplicationDeploymentsPage: Codable, Hashable {
    let count: Int
    let deployments: [DeploymentQueueItem]

    private enum CodingKeys: String, CodingKey {
        case count
        case deployments
    }

    init(count: Int, deployments: [DeploymentQueueItem]) {
        self.count = count
        self.deployments = deployments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent([DeploymentQueueItem].self, forKey: .deployments) ?? []
        if let n = Self.decodeFlexibleCount(from: c, key: .count) {
            count = n
        } else {
            count = list.count
        }
        deployments = list
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(count, forKey: .count)
        try c.encode(deployments, forKey: .deployments)
    }

    private static func decodeFlexibleCount(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        guard c.contains(key) else { return nil }
        if (try? c.decodeNil(forKey: key)) == true { return nil }
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
        return nil
    }
}

/// Objet Application tel que renvoyé par Coolify sur la route deployments/applications (champs optionnels pour tolérer les évolutions d’API).
struct CoolifyApplicationAPIRow: Decodable {
    let uuid: String
    let name: String?
    let status: String?
    let git_commit_sha: String?
    let description: String?
    let created_at: String?
    let updated_at: String?
    let id: Int?

    func asDeploymentQueueItem() -> DeploymentQueueItem {
        let stableId = "\(uuid)|\(git_commit_sha ?? "")|\(updated_at ?? created_at ?? "")|\(id.map(String.init) ?? "")"
        return DeploymentQueueItem(
            deployment_uuid: stableId,
            status: status ?? "unknown",
            application_name: name,
            application_id: id,
            commit: git_commit_sha,
            commit_message: description,
            created_at: created_at,
            updated_at: updated_at,
            server_name: nil,
            deployment_url: nil,
            force_rebuild: nil,
            restart_only: nil,
            rollback: nil
        )
    }
}

extension DeploymentQueueItem {
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Date la plus fiable pour afficher « quand » (mise à jour du build, sinon création).
    var deploymentDate: Date? {
        for s in [updated_at, created_at].compactMap({ $0 }) {
            if let d = Self.iso8601Fractional.date(from: s) { return d }
            if let d = Self.iso8601.date(from: s) { return d }
        }
        return nil
    }

    var isBuildSuccessful: Bool {
        let s = status.lowercased()
        if s.contains("unhealthy") || s.contains("unsuccess") { return false }
        return s == "finished" || s == "success" || s == "successful"
            || (s.contains("success") && !s.contains("unsuccess"))
            || s.contains(":healthy")
    }

    var isBuildFailed: Bool {
        let s = status.lowercased()
        return s == "failed" || s == "error" || s.contains("fail")
            || s == "cancelled" || s == "canceled"
            || s.contains("unhealthy")
    }

    var isBuildInProgress: Bool {
        if isBuildSuccessful || isBuildFailed { return false }
        let s = status.lowercased()
        if s == "finished" || s == "failed" || s == "error" || s == "cancelled" || s == "canceled" { return false }
        return s == "in_progress"
            || s.contains("progress")
            || s == "queued"
            || s == "pending"
            || s == "running"
            || s == "deploying"
            || s == "building"
            || s.contains(":starting")
            || s.contains(":queued")
            || s.contains(":building")
            || s.contains("deploying")
    }
}

extension Array where Element == DeploymentQueueItem {
    /// Plus récent en premier (même ordre que la zone « dernier déploiement » + liste scrollable).
    func sortedByDeploymentDateDescending() -> [DeploymentQueueItem] {
        sorted { a, b in
            (a.deploymentDate ?? .distantPast) > (b.deploymentDate ?? .distantPast)
        }
    }
}
