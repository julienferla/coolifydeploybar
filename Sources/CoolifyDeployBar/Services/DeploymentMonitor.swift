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
    /// Incrémenté ~20×/s pendant `.deploying` pour forcer le redraw du label `MenuBarExtra` (sinon `TimelineView` / effets restent figés).
    @Published private(set) var menuBarDeployingPulse: UInt64 = 0

    /// `deployment_uuid` → UUID application Coolify (pour liens web quand la ligne ne porte pas l’UUID).
    private var deploymentToApplicationUUID: [String: String] = [:]
    private var pollTask: Task<Void, Never>?
    private var menuBarDeployingPulseTask: Task<Void, Never>?

    /// UUID des déploiements vus « en cours » au dernier recalcul (pour notifier même si l’icône barre de menus n’a pas affiché `.deploying` entre deux polls).
    private var lastSeenInProgressDeploymentUUIDs: Set<String> = []
    /// Évite d’envoyer plusieurs fois la même fin de déploiement à chaque rafraîchissement.
    private var lastNotifiedFinishedDeploymentUUID: String?

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
        stopMenuBarDeployingPulse()
    }

    func refresh(settings: AppSettings) async {
        guard settings.isConfigured else {
            lastError = "Configure l’URL et le token dans Réglages."
            queued = []
            history = []
            historyTotal = 0
            deploymentToApplicationUUID = [:]
            recomputeMenuBarVisual(settings: settings)
            return
        }

        let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)
        let fallbackAppUUID = settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        var errors: [String] = []

        var globalQueued: [DeploymentQueueItem] = []
        do {
            globalQueued = try await client.fetchQueuedDeployments()
        } catch {
            errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        var applicationUUIDs: [String] = []
        do {
            applicationUUIDs = try await client.fetchApplications().map(\.uuid)
        } catch {
            errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        if applicationUUIDs.isEmpty, !fallbackAppUUID.isEmpty {
            applicationUUIDs = [fallbackAppUUID]
        }

        deploymentToApplicationUUID = [:]
        var historyDeployments: [DeploymentQueueItem] = []
        var historyCountSum = 0

        await withTaskGroup(of: (String, Result<ApplicationDeploymentsPage, Error>).self) { group in
            for appUUID in applicationUUIDs {
                group.addTask {
                    do {
                        let page = try await client.fetchApplicationDeployments(
                            applicationUUID: appUUID,
                            skip: 0,
                            take: Self.deploymentHistoryLimit
                        )
                        return (appUUID, .success(page))
                    } catch {
                        return (appUUID, .failure(error))
                    }
                }
            }
            for await (appUUID, result) in group {
                switch result {
                case .success(let page):
                    historyCountSum += page.count
                    for d in page.deployments {
                        deploymentToApplicationUUID[d.deployment_uuid] = appUUID
                    }
                    historyDeployments.append(contentsOf: page.deployments)
                case .failure(let err):
                    errors.append((err as? LocalizedError)?.errorDescription ?? err.localizedDescription)
                }
            }
        }

        var byUUID: [String: DeploymentQueueItem] = [:]
        for d in historyDeployments {
            if let existing = byUUID[d.deployment_uuid] {
                let da = d.deploymentDate ?? .distantPast
                let db = existing.deploymentDate ?? .distantPast
                if da >= db { byUUID[d.deployment_uuid] = d }
            } else {
                byUUID[d.deployment_uuid] = d
            }
        }
        let mergedSorted = Array(byUUID.values).sortedByDeploymentDateDescending()

        history = mergedSorted
        historyTotal = historyCountSum
        queued = Self.buildDisplayQueue(global: globalQueued, history: mergedSorted)

        lastUpdated = Date()
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
        recomputeMenuBarVisual(settings: settings)
    }

    /// UUID d’application Coolify pour résoudre les liens (file globale ou fusion multi-apps).
    func resolvedApplicationUUID(for item: DeploymentQueueItem, settings: AppSettings) -> String {
        if let u = deploymentToApplicationUUID[item.deployment_uuid], !u.isEmpty { return u }
        return settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recomputeMenuBarVisual(settings: AppSettings) {
        let previous = menuBarVisual
        let priorInProgressUUIDs = lastSeenInProgressDeploymentUUIDs
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
        if newVisual == .deploying {
            startMenuBarDeployingPulseIfNeeded()
        } else {
            stopMenuBarDeployingPulse()
        }

        let currentInProgress = Set(combined.filter(\.isBuildInProgress).map(\.deployment_uuid))
        lastSeenInProgressDeploymentUUIDs = currentInProgress

        let notifyEnabled = settings.notifyOnDeploymentComplete
        let finishedUUID = completedItem?.deployment_uuid
        let emergedFromTrackedProgress = finishedUUID.map { priorInProgressUUIDs.contains($0) } ?? false
        let shouldNotify = notifyEnabled
            && (newVisual == .success || newVisual == .failure)
            && completedItem != nil
            && (previous == .deploying || emergedFromTrackedProgress)
            && finishedUUID != lastNotifiedFinishedDeploymentUUID

        if shouldNotify, let item = completedItem {
            lastNotifiedFinishedDeploymentUUID = item.deployment_uuid
            let baseURL = settings.baseURL
            let token = settings.apiToken
            let appUUID = resolvedApplicationUUID(for: item, settings: settings)
            Task { @MainActor in
                let client = CoolifyAPIClient(baseURL: baseURL, token: token)
                let url = await CoolifyDeploymentURLResolver.resolveAsync(
                    client: client,
                    item: item,
                    selectedApplicationUUID: appUUID
                )
                await DeployNotificationService.postCompletionIfNeeded(
                    to: newVisual,
                    completedItem: item,
                    notifyEnabled: notifyEnabled,
                    openURL: url
                )
            }
        }
    }

    private func startMenuBarDeployingPulseIfNeeded() {
        guard menuBarDeployingPulseTask == nil else { return }
        menuBarDeployingPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard menuBarVisual == .deploying else { break }
                menuBarDeployingPulse &+= 1
            }
            menuBarDeployingPulseTask = nil
        }
    }

    private func stopMenuBarDeployingPulse() {
        menuBarDeployingPulseTask?.cancel()
        menuBarDeployingPulseTask = nil
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
