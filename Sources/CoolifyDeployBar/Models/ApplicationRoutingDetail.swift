import Foundation

/// Champs utiles pour construire une URL web Coolify à partir de `GET /api/v1/applications/{uuid}`.
/// L’API évolue : on décode de façon tolérante (clés optionnelles + objets imbriqués).
struct ApplicationRoutingDetail: Decodable, Sendable {
    let uuid: String
    let project_uuid: String?
    let environment_uuid: String?

    private enum CodingKeys: String, CodingKey {
        case uuid
        case project_uuid
        case environment_uuid
        case project
        case environment
    }

    private struct UUIDBox: Decodable {
        let uuid: String?
    }

    init(uuid: String, project_uuid: String?, environment_uuid: String?) {
        self.uuid = uuid
        self.project_uuid = project_uuid
        self.environment_uuid = environment_uuid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let uuid = try c.decode(String.self, forKey: .uuid)
        var p = try c.decodeIfPresent(String.self, forKey: .project_uuid)
        var e = try c.decodeIfPresent(String.self, forKey: .environment_uuid)
        if p == nil, let nested = try? c.decode(UUIDBox.self, forKey: .project) {
            p = nested.uuid
        }
        if e == nil, let nested = try? c.decode(UUIDBox.self, forKey: .environment) {
            e = nested.uuid
        }
        self.init(uuid: uuid, project_uuid: p, environment_uuid: e)
    }
}
