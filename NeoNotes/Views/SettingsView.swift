import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: NoteStore
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Store notes in iCloud Drive", isOn: $store.useICloud)
                    .disabled(!store.iCloudAvailable)
            } footer: {
                if store.iCloudAvailable {
                    Text("Notes are moved to iCloud Drive and sync across your Macs.")
                } else {
                    Text("Sign in to iCloud and enable iCloud Drive to sync notes. Requires the app to be signed with an iCloud-enabled team.")
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section {
                LabeledContent("Notes folder") {
                    Text(store.notesDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button("Reveal in Finder") { store.revealInFinder() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
