import Foundation

enum CoolifyAPIError: LocalizedError {
    case invalidBaseURL
    case insecureScheme
    case invalidResponse(statusCode: Int, body: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return String(localized: "URL de base invalide. Exemple : https://coolify.example.com")
        case .insecureScheme:
            return String(localized: "URL en http:// non sécurisée. Le token Bearer partirait en clair sur le réseau. Utilisez https:// (ou http:// uniquement vers localhost / IP privée / .local).")
        case let .invalidResponse(code, body):
            if code == 401 {
                let hint = String(localized: "Non autorisé (401). Vérifiez : l’URL est l’origine de l’instance (ex. https://coolify.example.com, sans /dashboard) ; le jeton vient de Coolify → Keys & Tokens → API tokens ; ne collez pas le mot « Bearer » devant le jeton (l’app l’ajoute) ; pas d’espace en trop.")
                if let body, !body.isEmpty {
                    return String(localized: "\(hint) Réponse : \(body)")
                }
                return hint
            }
            if let body, !body.isEmpty {
                return String(localized: "HTTP \(code) : \(body)")
            }
            return String(localized: "HTTP \(code)")
        case let .decoding(err):
            return String(localized: "Réponse JSON inattendue : \(err.localizedDescription)")
        case let .transport(err):
            return err.localizedDescription
        }
    }
}
