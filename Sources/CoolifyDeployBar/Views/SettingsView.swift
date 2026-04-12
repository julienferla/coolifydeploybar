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
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        // `arrow.triangle.branch.circle.fill` n’existe pas sur toutes les versions macOS (erreur runtime).
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 6) {
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
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        Button {
                            Task { await checkGitHubRelease(userInitiated: true) }
                        } label: {
                            if isCheckingRelease {
                                Label("Vérification…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Vérifier les mises à jour", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isCheckingRelease)
                        if let releaseActionURL {
                            if hasNewerRelease {
                                Link("Télécharger la mise à jour", destination: releaseActionURL)
                                    .font(.subheadline)
                            } else {
                                Link("Voir sur GitHub", destination: releaseActionURL)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Application")
            }

            Section("Connexion Coolify") {
                TextField("URL (ex. https://coolify.example.com)", text: $settings.baseURL)
                SecureField("Token API (sans « Bearer »)", text: $settings.apiToken)
            }
            Section("Surveillance") {
                TextField("UUID application (historique)", text: $settings.applicationUUID)
                    .font(.system(.body, design: .monospaced))
                Stepper(
                    value: $settings.pollIntervalSeconds,
                    in: 5 ... 600,
                    step: 5
                ) {
                    Text("Intervalle : \(Int(settings.pollIntervalSeconds)) s")
                }
                HStack {
                    Button("Charger les applications") {
                        Task { await loadApplications() }
                    }
                    .disabled(!settings.isConfigured || isLoadingApps)
                    if isLoadingApps {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                if let loadAppsError {
                    Text(loadAppsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !applications.isEmpty {
                    Picker("Choisir une application", selection: $settings.applicationUUID) {
                        Text("— Aucune —").tag("")
                        ForEach(applications) { app in
                            Text("\(app.name) (\(app.uuid.prefix(8))…)")
                                .tag(app.uuid)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 380)
        .task {
            await checkGitHubRelease(userInitiated: false)
        }
    }

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
            applications = try await client.fetchApplications().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadAppsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
