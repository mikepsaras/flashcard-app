import SwiftUI

struct SettingsView: View {
    @AppStorage(GradingMode.storageKey) private var gradingModeRaw = GradingMode.twoButton.rawValue
    @AppStorage(AIProvider.selectedProviderKey) private var aiProviderRaw = AIProvider.openAI.rawValue
    @State private var apiKey = ""
    @State private var model = ""
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable { case idle, testing, ok, failed(String) }
    private var aiProvider: AIProvider { AIProvider(rawValue: aiProviderRaw) ?? .openAI }

    var body: some View {
        Form {
            Section {
                Picker(selection: $gradingModeRaw) {
                    ForEach(GradingMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                } label: {
                    Label("Grading buttons", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("Studying")
            } footer: {
                Text("Two buttons mark a card known or not. Four buttons (Again / Hard / Good / Easy) give the spaced-repetition scheduler finer signal.")
            }

            Section {
                Picker("Provider", selection: $aiProviderRaw) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                SecureField("API key", text: $apiKey)
                TextField("Model", text: $model, prompt: Text(aiProvider.defaultModel))
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    Button { testConnection() } label: {
                        Label("Test connection", systemImage: "checkmark.seal")
                    }
                    .disabled(apiKey.isEmpty || testStatus == .testing)
                    Spacer()
                    testStatusView
                }
            } header: {
                Text("AI Card Generation")
            } footer: {
                Text("Your key is stored in this device's Keychain and used only to call \(aiProvider.displayName) directly. Get one at \(aiProvider.keyConsoleURL).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { loadAI() }
        .onChange(of: aiProviderRaw) { _, _ in loadAI() }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue, account: aiProvider.keychainAccount)
            testStatus = .idle
        }
        .onChange(of: model) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: aiProvider.modelDefaultsKey)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #endif
    }

    @ViewBuilder private var testStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .font(Typography.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.danger)
                .font(Typography.caption)
                .lineLimit(2)
        }
    }

    private func loadAI() {
        apiKey = KeychainStore.get(account: aiProvider.keychainAccount) ?? ""
        model = UserDefaults.standard.string(forKey: aiProvider.modelDefaultsKey) ?? ""
        testStatus = .idle
    }

    private func testConnection() {
        let key = apiKey
        let usedModel = model.isEmpty ? aiProvider.defaultModel : model
        let provider = aiProvider
        testStatus = .testing
        Task {
            do {
                _ = try await CardGenerator().generate(
                    prompt: "Make one flashcard about the capital of France.",
                    count: 1, provider: provider, model: usedModel, apiKey: key
                )
                testStatus = .ok
            } catch {
                testStatus = .failed((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView()
}
