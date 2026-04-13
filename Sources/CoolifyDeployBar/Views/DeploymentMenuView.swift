import AppKit
import SwiftUI

struct DeploymentMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: DeploymentMonitor

    /// Empreinte connexion pour relancer chargement / polling si URL ou token change.
    private var connectionFingerprint: String {
        settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            + "|" + settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        Text("Aucun déploiement à afficher pour le moment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
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
                    }
                }
            }
            // MenuBarExtra en `.window` : sans hauteur minimale, le ScrollView peut se voir attribuer ~0 pt
            // de hauteur et tout le bloc déploiements / historique disparaît visuellement.
            .frame(minHeight: 280, maxHeight: 400)

            Divider()
            HStack(spacing: 8) {
                Button("Actualiser") {
                    Task {
                        await monitor.refresh(settings: settings)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quitter l’application")
                .accessibilityLabel("Quitter l’application")

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
                monitor.stopPolling()
                return
            }
            monitor.startPolling(settings: settings)
            if settings.notifyOnDeploymentComplete {
                await DeployNotificationService.ensureAuthorization()
            }
            await monitor.refresh(settings: settings)
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
                    if monitor.historyTotal > 0 {
                        Text(
                            "\(monitor.history.count) déploiements récents (toutes apps) · \(monitor.historyTotal) enregistrements côté API (cumul)"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
    }

    @MainActor
    private func openCoolifyInBrowser(item: DeploymentQueueItem) {
        Task { @MainActor in
            guard settings.isConfigured else { return }
            let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)
            let id = monitor.resolvedApplicationUUID(for: item, settings: settings)
            let url = await CoolifyDeploymentURLResolver.resolveAsync(
                client: client,
                item: item,
                selectedApplicationUUID: id
            )
            guard let url else { return }
            NSWorkspace.shared.open(url)
        }
    }

    /// Lien explicite vers Coolify (libellé + icône, zone de clic large).
    @ViewBuilder
    private func coolifyOpenControl(for item: DeploymentQueueItem) -> some View {
        if settings.isConfigured {
            Button {
                openCoolifyInBrowser(item: item)
            } label: {
                Label("Ouvrir dans Coolify", systemImage: "safari")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.link)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .help("Ouvre la page du déploiement ou de l’application dans Coolify")
        }
    }

    /// Bloc mis en avant : message de commit lisible (plusieurs lignes).
    private func lastDeploymentHighlight(_ item: DeploymentQueueItem) -> some View {
        let accent = statusAccent(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            if item.isBuildInProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dernier déploiement")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let start = item.deploymentStartedAt {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Lancé")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(start.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(accent)
                        }
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Durée")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(Self.formatDeployElapsed(since: start, now: context.date))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                    } else {
                        Text("Heure de lancement inconnue")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
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
            HStack(alignment: .center) {
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
            coolifyOpenControl(for: item)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            coolifyOpenControl(for: item)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Bleu explicite pour l’état « en cours » (indépendant de l’accent couleur macOS, souvent orange).
    private static let deployInProgressBlue = Color(red: 0.05, green: 0.42, blue: 0.95)

    private func statusAccent(for item: DeploymentQueueItem) -> Color {
        if item.isBuildSuccessful { return .green }
        if item.isBuildFailed { return .red }
        if item.isBuildInProgress { return Self.deployInProgressBlue }
        return statusTint(item.status)
    }

    private func statusTint(_ status: String) -> Color {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "finished" || s == "success" || s == "successful" || s == "running:healthy" { return .green }
        if s == "failed" || s == "error" || s == "cancelled-by-user" { return .red }
        if s == "in_progress" || s == "queued" || s == "pending" { return Self.deployInProgressBlue }
        return .gray
    }

    /// Durée écoulée depuis le lancement (compte les secondes, format lisible).
    private static func formatDeployElapsed(since start: Date, now: Date) -> String {
        let sec = max(0, Int(now.timeIntervalSince(start).rounded(.down)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 {
            return String(format: "%d h %02d min %02d s", h, m, s)
        }
        if m > 0 {
            return String(format: "%d min %02d s", m, s)
        }
        return String(format: "%d s", s)
    }
}
