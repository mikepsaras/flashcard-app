import SwiftUI

struct SettingsView: View {
    @AppStorage(PersistenceController.syncEnabledKey) private var syncEnabled = false
    @AppStorage(GradingMode.storageKey) private var gradingModeRaw = GradingMode.twoButton.rawValue
    /// Tracks the value at launch so we can tell the user when a relaunch is needed.
    @State private var launchSyncValue = UserDefaults.standard.bool(forKey: PersistenceController.syncEnabledKey)

    private var needsRelaunch: Bool { syncEnabled != launchSyncValue }

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
                Toggle(isOn: $syncEnabled) {
                    Label("Sync with iCloud", systemImage: "icloud")
                }
            } header: {
                Text("Sync")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep your decks up to date across your Mac and iPhone using your private iCloud account.")
                    if needsRelaunch {
                        Label("Quit and reopen Flashcards to apply this change.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                            .font(Typography.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 280)
        #endif
    }
}

#Preview {
    SettingsView()
}
