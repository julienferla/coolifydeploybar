import SwiftUI

struct DeploymentMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: DeploymentMonitor

    @State private var menuApplications: [ApplicationSummary] = []
    @State private var isLoadingMenuApplications = false
    @State private var menuApplicationsError: String?

    /// Empreinte connexion pour relancer chargement / polling si URL ou token change.
    private var connectionFingerprint: String {
        settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            + "|" + settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Liste pour le sélecteur : apps Coolify + entrée synthétique si l’UUID enregistré n’est pas dans la liste (saisie manuelle).
    private var applicationsForPicker: [ApplicationSummary] {
        var list = menuApplications
        let id = settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty, !list.contains(where: { $0.uuid == id }) {
            list.append(
                ApplicationSummary(
                    uuid: id,
                    name: "UUID enregistré (\(String(id.prefix(8)))…)",
                    fqdn: nil,
                    description: nil
                )
            )
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// File + historique fusionnés par `deployment_uuid` en gardant **la ligne la plus récente** (évite incohérence queued vs history).
    private var mergedDeploymentsDescending: [DeploymentQueueItem] {
        var byUUID: [String: DeploymentQueueItem] = [:]
        for item in monitor.history + monitor.queued {
            if let existing = byUUID[item.deployment_uuid] {
                let da = item.deploymentDate ?? .distantPast
                let db = existing.deploymentDate ?? .distantPast
                if da >= db { byUUID[item.deployment_uuid] = item }
            } else {
                byUUID[item.deployment_uuid] = item
            }
        }
        return Array(byUUID.values).sorted { ($0.deploymentDate ?? .distantPast) > ($1.deploymentDate ?? .distantPast) }
    }

    /// Mis en avant : build **en cours** le plus récent s’il y en a un, sinon le déploiement le plus récent.
    private var highlightedDeployment: DeploymentQueueItem? {
        let merged = mergedDeploymentsDescending
        guard !merged.isEmpty else { return nil }
        if let active = merged
            .filter(\.isBuildInProgress)
            .max(by: { ($0.deploymentDate ?? .distantPast) < ($1.deploymentDate ?? .distantPast) })
        {
            return active
        }
        return merged.first
    }

    /// Liste scrollable sous la carte : tout le reste, trié du plus récent au plus ancien.
    private var timelineWithoutHighlight: [DeploymentQueueItem] {
        let merged = mergedDeploymentsDescending
        guard let h = highlightedDeployment else { return merged }
        return merged.filter { $0.deployment_uuid != h.deployment_uuid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // VStack (pas LazyVStack) : dans un popover MenuBarExtra, LazyVStack + ScrollView
            // peut rester à hauteur nulle et n’afficher aucune ligne alors que l’historique est chargé.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let err = monitor.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                        Divider()
                    }
                    if let item = highlightedDeployment {
                        lastDeploymentHighlight(item)
                        Divider()
                            .padding(.vertical, 4)
                    }
                    if timelineWithoutHighlight.isEmpty, highlightedDeployment == nil {
                        Text(settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Indique l’UUID de l’application pour l’historique."
                            : "Aucun déploiement à afficher pour le moment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                    }
                    if timelineWithoutHighlight.isEmpty,
                       highlightedDeployment != nil,
                       monitor.history.count < monitor.historyTotal
                    {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await monitor.loadMoreHistory(settings: settings) }
                            }
                    }
                    // Indices : si l’API renvoie plusieurs lignes avec le même `deployment_uuid`, `id: \.element.id`
                    // casse le rendu SwiftUI (liste vide / incohérente).
                    ForEach(Array(timelineWithoutHighlight.indices), id: \.self) { index in
                        let item = timelineWithoutHighlight[index]
                        deploymentTimelineRow(item)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        if index < timelineWithoutHighlight.count - 1 {
                            Divider()
                                .padding(.leading, 10)
                        }
                        if index == timelineWithoutHighlight.count - 1 {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await monitor.loadMoreHistory(settings: settings) }
                                }
                        }
                    }
                    if monitor.isLoadingMoreHistory {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.75)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            // MenuBarExtra en `.window` : sans hauteur minimale, le ScrollView peut se voir attribuer ~0 pt
            // de hauteur et tout le bloc déploiements / historique disparaît visuellement.
            .frame(minHeight: 280, maxHeight: 400)

            Divider()
            HStack {
                Button("Actualiser") {
                    Task {
                        await loadApplicationsForMenu()
                        await monitor.refresh(settings: settings)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button("Réglages…") {
                    SettingsWindowPresenter.show(settings: settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            .padding(8)
        }
        .frame(minWidth: 340)
        .task(id: connectionFingerprint) {
            guard settings.isConfigured else {
                menuApplications = []
                menuApplicationsError = nil
                monitor.stopPolling()
                return
            }
            monitor.startPolling(settings: settings)
            await loadApplicationsForMenu()
            await monitor.refresh(settings: settings)
        }
        .onChange(of: settings.applicationUUID) { _, _ in
            Task { await monitor.refresh(settings: settings) }
        }
        .onDisappear {
            monitor.stopPolling()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coolify Deploy Bar")
                        .font(.headline)
                    if let t = monitor.lastUpdated {
                        Text(t.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       monitor.historyTotal > 0
                    {
                        Text("\(monitor.history.count) chargé · \(monitor.historyTotal) au total")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            if settings.isConfigured {
                projectSelectorRow
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var projectSelectorRow: some View {
        if isLoadingMenuApplications, menuApplications.isEmpty {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Chargement des projets…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let err = menuApplicationsError, menuApplications.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await loadApplicationsForMenu() }
                }
                .font(.caption)
            }
        } else if applicationsForPicker.count > 1 {
            HStack(alignment: .center) {
                Text("Projet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Projet", selection: $settings.applicationUUID) {
                    Text("— Aucune —").tag("")
                    ForEach(applicationsForPicker) { app in
                        Text("\(app.name) (\(String(app.uuid.prefix(8)))…)")
                            .tag(app.uuid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .trailing)
            }
        } else if let only = applicationsForPicker.first {
            HStack {
                Text("Projet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(only.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @MainActor
    private func loadApplicationsForMenu() async {
        guard settings.isConfigured else {
            menuApplications = []
            menuApplicationsError = nil
            return
        }
        isLoadingMenuApplications = true
        menuApplicationsError = nil
        defer { isLoadingMenuApplications = false }
        let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)
        do {
            let apps = try await client.fetchApplications().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            menuApplications = apps
            if apps.count == 1 {
                let onlyId = apps[0].uuid.trimmingCharacters(in: .whitespacesAndNewlines)
                if settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settings.applicationUUID = onlyId
                }
            }
        } catch {
            menuApplications = []
            menuApplicationsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Bloc mis en avant : message de commit lisible (plusieurs lignes).
    private func lastDeploymentHighlight(_ item: DeploymentQueueItem) -> some View {
        let accent = statusAccent(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dernier déploiement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let d = item.deploymentDate {
                    Text(d.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(accent)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(item.application_name ?? "Application")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            HStack {
                if let c = item.commit, !c.isEmpty {
                    Text(String(c.prefix(7)))
                        .font(.callout.monospaced().weight(.medium))
                }
                Spacer(minLength: 8)
                Text(item.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            if let msg = item.commit_message, !msg.isEmpty {
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func deploymentTimelineRow(_ item: DeploymentQueueItem) -> some View {
        let accent = statusAccent(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.application_name ?? "Application")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let d = item.deploymentDate {
                    Text(d.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                if let c = item.commit, !c.isEmpty {
                    Text(String(c.prefix(7)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Text(item.status)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Spacer(minLength: 0)
            }
            if let msg = item.commit_message, !msg.isEmpty {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusAccent(for item: DeploymentQueueItem) -> Color {
        if item.isBuildSuccessful { return .green }
        if item.isBuildFailed { return .red }
        if item.isBuildInProgress { return .blue }
        return statusTint(item.status)
    }

    private func statusTint(_ status: String) -> Color {
        let s = status.lowercased()
        if s.contains("success") || s == "finished" { return .green }
        if s.contains("fail") || s == "error" { return .red }
        if s.contains("progress") || s == "running" || s == "queued" || s == "pending" { return .blue }
        return .gray
    }
}
