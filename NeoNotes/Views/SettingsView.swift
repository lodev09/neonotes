import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: NoteStore
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 12) {
            card {
                HStack(spacing: 10) {
                    iconBadge("folder.fill", .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes Folder")
                        Text(store.notesDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.notesDirectory.path)
                    }
                    Spacer(minLength: 12)
                    Button("Change…") { chooseFolder() }
                }
                .padding(12)

                Divider()
                    .padding(.leading, 48)

                HStack {
                    Text("Markdown files in this folder load automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if store.customNotesURL != nil {
                        Button("Use Default") { store.setNotesDirectory(nil) }
                            .controlSize(.small)
                    }
                    Button("Show in Finder") { store.revealInFinder() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            card {
                HStack(spacing: 10) {
                    iconBadge("power", .green)
                    Text("Launch at Login")
                    Spacer()
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                }
                .padding(12)
            }
        }
        .padding(16)
        .frame(width: 420)
        .fixedSize()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func iconBadge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for your notes"
        // Don't point the panel at the sandbox container; let it open
        // somewhere sensible (last used / Documents) when on the default
        if let custom = store.customNotesURL {
            panel.directoryURL = custom
        }
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
