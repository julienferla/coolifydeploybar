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
}

struct ApplicationDeploymentsPage: Codable, Hashable {
    let count: Int
    let deployments: [DeploymentQueueItem]
}
