import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var applications: [ApplicationSummary] = []
    @State private var loadAppsError: String?
    @State private var isLoadingApps = false

    var body: some View {
        Form {
            Section("Connexion Coolify") {
                TextField("URL (ex. https://coolify.example.com)", text: $settings.baseURL)
                SecureField("Token API (Bearer)", text: $settings.apiToken)
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
        .frame(minWidth: 420, minHeight: 280)
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
