import Foundation
import SwiftUI

@MainActor
final class DeploymentMonitor: ObservableObject {
    /// Nombre max de déploiements demandés à l’API (pas de pagination au-delà).
    static let deploymentHistoryLimit = 10
    @Published private(set) var queued: [DeploymentQueueItem] = []
    @Published private(set) var history: [DeploymentQueueItem] = []
    @Published private(set) var historyTotal: Int = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var menuBarVisual: MenuBarDeploymentVisual = .idle

    /// Évite de fusionner l’historique d’une autre app si l’UUID change pendant un chargement.
    private var loadedApplicationUUID: String = ""
    private var pollTask: Task<Void, Never>?

    func startPolling(settings: AppSettings) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh(settings: settings)
                let seconds = max(5, settings.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(settings: AppSettings) async {
        guard settings.isConfigured else {
            lastError = "Configure l’URL et le token dans Réglages."
            queued = []
            history = []
            historyTotal = 0
            loadedApplicationUUID = ""
            recomputeMenuBarVisual(settings: settings)
            return
        }

        let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)
        let appId = settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        var errors: [String] = []

        if appId != loadedApplicationUUID {
            history = []
            historyTotal = 0
            loadedApplicationUUID = appId
        }

        var globalQueued: [DeploymentQueueItem] = []
        do {
            globalQueued = try await client.fetchQueuedDeployments()
        } catch {
            errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        var historyDeployments: [DeploymentQueueItem] = []
        var historyCount = 0
        if appId.isEmpty {
            historyDeployments = []
            historyCount = 0
        } else {
            do {
                let h = try await client.fetchApplicationDeployments(
                    applicationUUID: appId,
                    skip: 0,
                    take: Self.deploymentHistoryLimit
                )
                historyDeployments = h.deployments.sortedByDeploymentDateDescending()
                historyCount = h.count
            } catch {
                errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        history = historyDeployments
        historyTotal = historyCount
        queued = Self.buildDisplayQueue(global: globalQueued, history: historyDeployments)

        lastUpdated = Date()
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
        recomputeMenuBarVisual(settings: settings)
    }

    func recomputeMenuBarVisual(settings: AppSettings) {
        let previous = menuBarVisual
        var byUUID: [String: DeploymentQueueItem] = [:]
        for item in history + queued {
            if let existing = byUUID[item.deployment_uuid] {
                let da = item.deploymentDate ?? .distantPast
                let db = existing.deploymentDate ?? .distantPast
                if da >= db { byUUID[item.deployment_uuid] = item }
            } else {
                byUUID[item.deployment_uuid] = item
            }
        }
        let combined = Array(byUUID.values)

        let newVisual: MenuBarDeploymentVisual
        let completedItem: DeploymentQueueItem?

        if combined.contains(where: \.isBuildInProgress) {
            newVisual = .deploying
            completedItem = nil
        } else {
            let finished = combined
                .filter { !$0.isBuildInProgress }
                .sorted { ($0.deploymentDate ?? .distantPast) > ($1.deploymentDate ?? .distantPast) }
            if let latest = finished.first {
                completedItem = latest
                if latest.isBuildSuccessful {
                    newVisual = .success
                } else if latest.isBuildFailed {
                    newVisual = .failure
                } else {
                    newVisual = .idle
                }
            } else {
                newVisual = .idle
                completedItem = nil
            }
        }

        menuBarVisual = newVisual
        DeployNotificationService.postCompletionIfNeeded(
            from: previous,
            to: newVisual,
            completedItem: completedItem,
            notifyEnabled: settings.notifyOnDeploymentComplete
        )
    }

    /// File affichée : endpoint global `/deployments` + entrées **en cours** présentes seulement dans l’historique app (ex. `running:starting`).
    private static func buildDisplayQueue(global: [DeploymentQueueItem], history: [DeploymentQueueItem]) -> [DeploymentQueueItem] {
        var seen = Set(global.map(\.deployment_uuid))
        var out = global
        for h in history where h.isBuildInProgress {
            if seen.contains(h.deployment_uuid) { continue }
            if let c = h.commit, !c.isEmpty,
               global.contains(where: { $0.isBuildInProgress && $0.commit == c })
            {
                continue
            }
            out.append(h)
            seen.insert(h.deployment_uuid)
        }
        return out.sorted { a, b in
            let pa = a.isBuildInProgress
            let pb = b.isBuildInProgress
            if pa != pb { return pa && !pb }
            let da = a.deploymentDate ?? .distantPast
            let db = b.deploymentDate ?? .distantPast
            return da > db
        }
    }
}
