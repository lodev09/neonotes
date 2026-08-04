import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: NoteStore
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes folder") {
                    Text(store.notesDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Change…") { chooseFolder() }
                    if store.customNotesURL != nil {
                        Button("Use Default") { store.setNotesDirectory(nil) }
                    }
                    Button("Reveal in Finder") { store.revealInFinder() }
                }
            } footer: {
                Text("Markdown files already in the folder are loaded automatically.")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for your notes"
        panel.directoryURL = store.notesDirectory
        if panel.runModal() == .OK, let url = panel.url {
            store.setNotesDirectory(url)
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
