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
            if code == 401 {
                let hint =
                    "Non autorisé (401). Vérifiez : l’URL est l’origine de l’instance (ex. https://coolify.example.com, sans /dashboard) ; le jeton vient de Coolify → Keys & Tokens → API tokens ; ne collez pas le mot « Bearer » devant le jeton (l’app l’ajoute) ; pas d’espace en trop."
                if let body, !body.isEmpty {
                    return "\(hint) Réponse : \(body)"
                }
                return hint
            }
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
