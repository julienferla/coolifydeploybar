import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var applications: [ApplicationSummary] = []
    @State private var loadAppsError: String?
    @State private var isLoadingApps = false

    @State private var releaseStatus: String?
    @State private var releaseActionURL: URL?
    @State private var releaseTag: String?
    @State private var hasNewerRelease = false
    @State private var isCheckingRelease = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                applicationSection
                connectionSection
                monitoringSection
                notificationsSection
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.045),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .task {
            await checkGitHubRelease(userInitiated: false)
        }
    }

    // MARK: - Sections

    private var applicationSection: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color(red: 0.2, green: 0.45, blue: 1.0), Color(red: 0.35, green: 0.65, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
                            )
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Coolify Deploy Bar")
                        .font(.title3.weight(.semibold))
                    Text("Version \(AppVersion.marketingVersion) (\(AppVersion.buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let tag = releaseTag {
                        if let releaseStatus {
                            Text(releaseStatus)
                                .font(.caption)
                                .foregroundStyle(hasNewerRelease ? Color.orange : .secondary)
                        }
                        Text("Dernière release GitHub : \(tag)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await checkGitHubRelease(userInitiated: true) }
                        } label: {
                            if isCheckingRelease {
                                Label("Vérification…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Vérifier les mises à jour", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isCheckingRelease)

                        if let releaseActionURL {
                            if hasNewerRelease {
                                Link("Télécharger la mise à jour", destination: releaseActionURL)
                                    .font(.subheadline.weight(.medium))
                            } else {
                                Link("Voir sur GitHub", destination: releaseActionURL)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } label: {
            sectionLabel("Application", systemImage: "shippingbox")
        }
    }

    private var connectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent {
                    TextField("https://coolify.example.com", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                } label: {
                    Text("URL du serveur")
                }

                LabeledContent {
                    SecureField("Collez votre token API", text: $settings.apiToken)
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Token API")
                }

                Text("Sans préfixe « Bearer » — uniquement la valeur du secret.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            sectionLabel("Connexion Coolify", systemImage: "link")
        }
    }

    private var monitoringSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent {
                    TextField("UUID de l’application Coolify", text: $settings.applicationUUID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } label: {
                    Text("UUID application")
                }

                Text(
                    "Facultatif : sert surtout à ouvrir Coolify dans le navigateur quand l’API ne renvoie pas l’UUID application. "
                        + "La liste dans la barre regroupe toutes les applications détectées sur le serveur."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent {
                    Stepper(value: $settings.pollIntervalSeconds, in: 5 ... 600, step: 5) {
                        Text("\(Int(settings.pollIntervalSeconds)) s")
                            .monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Intervalle de rafraîchissement")
                }

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        Task { await loadApplications() }
                    } label: {
                        Label("Charger les applications", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!settings.isConfigured || isLoadingApps)

                    if isLoadingApps {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let loadAppsError {
                    Text(loadAppsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !applications.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    LabeledContent {
                        Picker("", selection: $settings.applicationUUID) {
                            Text("— Aucune —").tag("")
                            ForEach(applications) { app in
                                Text("\(app.name) (\(String(app.uuid.prefix(8)))…)")
                                    .tag(app.uuid)
                            }
                        }
                        .labelsHidden()
                    } label: {
                        Text("Choisir dans la liste")
                    }
                }
            }
        } label: {
            sectionLabel("Surveillance", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    private var notificationsSection: some View {
        GroupBox {
            Toggle(isOn: $settings.notifyOnDeploymentComplete) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifier à la fin d’un déploiement")
                        .font(.body.weight(.medium))
                    Text(
                        "Une notification macOS lorsque Coolify signale la fin d’un build "
                            + "(succès ou échec), pas pendant l’exécution."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: settings.notifyOnDeploymentComplete) { _, enabled in
                if enabled {
                    Task { await DeployNotificationService.ensureAuthorization() }
                }
            }
        } label: {
            sectionLabel("Notifications", systemImage: "bell.badge")
        }
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
    }

    // MARK: - Actions

    @MainActor
    private func checkGitHubRelease(userInitiated: Bool) async {
        isCheckingRelease = true
        defer { isCheckingRelease = false }
        if userInitiated {
            releaseActionURL = nil
        }
        do {
            let info = try await GitHubReleaseService.fetchLatestRelease()
            releaseTag = info.tagName
            let newer = GitHubReleaseService.isRemoteNewer(
                remoteTag: info.tagName,
                localVersion: AppVersion.marketingVersion
            )
            hasNewerRelease = newer
            if newer {
                releaseStatus = "Une mise à jour est disponible."
                releaseActionURL = URL(string: info.downloadOrReleaseURL)
            } else {
                releaseStatus = userInitiated ? "Vous utilisez la dernière version publiée sur GitHub." : nil
                releaseActionURL = URL(string: info.htmlURL)
            }
        } catch {
            hasNewerRelease = false
            if userInitiated {
                releaseStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                releaseActionURL = nil
            }
        }
    }

    @MainActor
    private func loadApplications() async {
        isLoadingApps = true
        loadAppsError = nil
        defer { isLoadingApps = false }
        let client = CoolifyAPIClient(baseURL: settings.baseURL, token: settings.apiToken)
        do {
            applications = try await client.fetchApplications().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            loadAppsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
