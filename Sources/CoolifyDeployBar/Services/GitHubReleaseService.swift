import Foundation

/// Vérifie les releases GitHub publiques (sans token) pour proposer une mise à jour.
enum GitHubReleaseService {
    private static let repoPath = "julienferla/coolifydeploybar"
    private static let releasesLatestURL = URL(string: "https://api.github.com/repos/\(repoPath)/releases/latest")!

    struct LatestReleaseInfo: Sendable {
        let tagName: String
        let htmlURL: String
        let publishedAt: String?
        /// Lien direct vers un asset .dmg s’il existe, sinon page release.
        let downloadOrReleaseURL: String
    }

    enum ServiceError: LocalizedError {
        case invalidResponse(Int)
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let code): return "HTTP \(code)"
            case .noData: return "Réponse vide"
            }
        }
    }

    private struct GitHubReleaseJSON: Decodable {
        let tag_name: String
        let html_url: String
        let published_at: String?
        let assets: [Asset]?
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    static func fetchLatestRelease() async throws -> LatestReleaseInfo {
        var req = URLRequest(url: releasesLatestURL)
        req.setValue("CoolifyDeployBar-update-check", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ServiceError.noData }
        guard (200 ..< 300).contains(http.statusCode) else { throw ServiceError.invalidResponse(http.statusCode) }
        let decoded = try JSONDecoder().decode(GitHubReleaseJSON.self, from: data)
        let dmg = decoded.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
        let url = dmg?.browser_download_url ?? decoded.html_url
        return LatestReleaseInfo(
            tagName: decoded.tag_name,
            htmlURL: decoded.html_url,
            publishedAt: decoded.published_at,
            downloadOrReleaseURL: url
        )
    }

    /// true si `remote` est strictement plus récent que `local` (comparaison semver simple : 1.2.3).
    static func isRemoteNewer(remoteTag: String, localVersion: String) -> Bool {
        let r = semverComponents(stripPrefix(remoteTag))
        let l = semverComponents(stripPrefix(localVersion))
        let maxN = max(r.count, l.count)
        for i in 0 ..< maxN {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private static func stripPrefix(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("v") { t.removeFirst() }
        return t
    }

    private static func semverComponents(_ s: String) -> [Int] {
        let part = s.split(separator: "-").first.map(String.init) ?? s
        return part.split(separator: ".").compactMap { comp in
            let prefix = comp.prefix { $0.isNumber }
            return Int(prefix)
        }
    }
}

enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
