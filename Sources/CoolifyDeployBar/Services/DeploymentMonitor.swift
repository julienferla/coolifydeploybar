import Foundation
import SwiftUI

@MainActor
final class DeploymentMonitor: ObservableObject {
    @Published private(set) var queued: [DeploymentQueueItem] = []
    @Published private(set) var history: [DeploymentQueueItem] = []
    @Published private(set) var historyTotal: Int = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

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
            return
        }

        let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)

        do {
            async let q = client.fetchQueuedDeployments()
            let appId = settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
            let h: ApplicationDeploymentsPage?
            if appId.isEmpty {
                h = nil
            } else {
                h = try await client.fetchApplicationDeployments(applicationUUID: appId, skip: 0, take: 20)
            }

            queued = try await q
            if let h {
                history = h.deployments
                historyTotal = h.count
            } else {
                history = []
                historyTotal = 0
            }
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
