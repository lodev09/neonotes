import SwiftUI

@main
struct NeoNotessApp: App {
    @StateObject private var store = NoteStore()

    var body: some Scene {
        MenuBarExtra {
            NotesPanelView()
                .environmentObject(store)
        } label: {
            Image(systemName: "note.text")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        Window("About NeoNotes", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
