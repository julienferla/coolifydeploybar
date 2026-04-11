import AppKit
import SwiftUI

struct DeploymentMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: DeploymentMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let err = monitor.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                Divider()
            }
            Section {
                if monitor.queued.isEmpty {
                    Text("Aucun déploiement en cours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(monitor.queued) { item in
                        deploymentRow(item)
                    }
                }
            } header: {
                Text("File d’attente")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if !settings.applicationUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Section {
                    if monitor.history.isEmpty {
                        Text("Aucun déploiement récent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        Text("\(monitor.history.count) affiché(s) sur \(monitor.historyTotal)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(monitor.history) { item in
                            deploymentRow(item)
                        }
                    }
                } header: {
                    Text("Historique (app)")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()
            HStack {
                Button("Actualiser") {
                    Task { await monitor.refresh(settings: settings) }
                }
                .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button("Réglages…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            .padding(8)
        }
        .frame(minWidth: 320)
        .task {
            monitor.startPolling(settings: settings)
            await monitor.refresh(settings: settings)
        }
        .onDisappear {
            monitor.stopPolling()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coolify Deploy Bar")
                    .font(.headline)
                if let t = monitor.lastUpdated {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private func deploymentRow(_ item: DeploymentQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.application_name ?? "Application")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(item.status)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusTint(item.status).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if let c = item.commit, !c.isEmpty {
                Text(String(c.prefix(7)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let msg = item.commit_message, !msg.isEmpty {
                Text(msg)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "finished", "success":
            return .green
        case "failed", "error":
            return .red
        case "in_progress", "running":
            return .orange
        default:
            return .gray
        }
    }
}
