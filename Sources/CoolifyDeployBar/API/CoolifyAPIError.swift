import Foundation

enum CoolifyAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse(statusCode: Int, body: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "URL de base invalide. Exemple : https://coolify.example.com"
        case let .invalidResponse(code, body):
            if let body, !body.isEmpty {
                return "HTTP \(code) : \(body)"
            }
            return "HTTP \(code)"
        case let .decoding(err):
            return "Réponse JSON inattendue : \(err.localizedDescription)"
        case let .transport(err):
            return err.localizedDescription
        }
    }
}
