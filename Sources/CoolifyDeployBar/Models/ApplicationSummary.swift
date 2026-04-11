import Foundation

/// Sous-ensemble des champs renvoyés par `GET /api/v1/applications` après `removeSensitiveData`.
struct ApplicationSummary: Codable, Identifiable, Hashable {
    var id: String { uuid }

    let uuid: String
    let name: String
    let fqdn: String?
    let description: String?
}
