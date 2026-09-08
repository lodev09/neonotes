import SwiftUI

@main
struct NeoNotessApp: App {
    @StateObject private var store = NoteStore()

    private static let menuBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NeoNotes")!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            NotesPanelView()
                .environmentObject(store)
        } label: {
            // MenuBarExtra ignores .font on its label; size via symbol configuration
            Image(nsImage: Self.menuBarIcon)
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
