import AppKit
import Combine
import SwiftUI

@MainActor
final class NoteStore: ObservableObject {
    private static let useICloudKey = "useICloud"
    private static let noteColorsKey = "noteColors"

    static let palette: [(name: String, hex: String)] = [
        ("Red", "D97366"),
        ("Orange", "E69E61"),
        ("Yellow", "E3C770"),
        ("Green", "73BA8C"),
        ("Teal", "6BB3BF"),
        ("Blue", "7099D4"),
        ("Purple", "A68CD1"),
        ("Pink", "D994AD"),
    ]

    @Published private(set) var notes: [Note] = []
    @Published var selectedID: String? {
        didSet { if oldValue != selectedID { flush() } }
    }
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var noteColors: [String: String] =
        UserDefaults.standard.dictionary(forKey: NoteStore.noteColorsKey) as? [String: String] ?? [:]
    @Published var useICloud: Bool {
        didSet {
            guard oldValue != useICloud else { return }
            UserDefaults.standard.set(useICloud, forKey: Self.useICloudKey)
            migrate(toICloud: useICloud)
        }
    }

    private var ubiquityNotesURL: URL?
    private let localNotesURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NeoNotes/Notes", isDirectory: true)
    }()

    private var pendingSaves: Set<String> = []
    private var saveTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var directoryMonitor: DispatchSourceFileSystemObject?

    var notesDirectory: URL {
        if useICloud, let ubiquityNotesURL { return ubiquityNotesURL }
        return localNotesURL
    }

    var selectedNote: Note? {
        notes.first { $0.id == selectedID }
    }

    var selectedIndex: Int? {
        notes.firstIndex { $0.id == selectedID }
    }

    init() {
        useICloud = UserDefaults.standard.bool(forKey: Self.useICloudKey)
        reload()
        watchDirectory()

        Task.detached(priority: .utility) { [weak self] in
            let url = FileManager.default
                .url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents/Notes", isDirectory: true)
            await MainActor.run {
                guard let self else { return }
                self.ubiquityNotesURL = url
                self.iCloudAvailable = url != nil
                if self.useICloud, url != nil {
                    self.reload()
                    self.watchDirectory()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: - Loading

    func reload() {
        let fm = FileManager.default
        let dir = notesDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let files = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        var loaded: [Note] = []
        for url in files {
            if url.lastPathComponent.hasSuffix(".icloud") {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension.lowercased() == "md",
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            var note = Note(
                id: url.deletingPathExtension().lastPathComponent,
                content: content,
                createdAt: values?.creationDate ?? modified,
                modifiedAt: modified
            )
            // Keep unsaved edits over what's on disk
            if pendingSaves.contains(note.id),
               let existing = notes.first(where: { $0.id == note.id }) {
                note.content = existing.content
            }
            loaded.append(note)
        }

        // Oldest first; id tiebreak keeps order stable across reloads
        notes = loaded.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id
        }

        if notes.isEmpty {
            createNote(content: Self.welcomeContent)
        } else if selectedID == nil || selectedNote == nil {
            selectedID = notes.first?.id
        }
    }

    // MARK: - Editing

    func updateContent(_ content: String, for id: String?) {
        guard let id,
              let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].content != content else { return }

        notes[index].content = content
        notes[index].modifiedAt = Date()
        pendingSaves.insert(id)

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard !pendingSaves.isEmpty else { return }
        for id in pendingSaves {
            guard let note = notes.first(where: { $0.id == id }) else { continue }
            try? note.content.write(to: fileURL(for: id), atomically: true, encoding: .utf8)
        }
        pendingSaves.removeAll()
    }

    @discardableResult
    func createNote(content: String = "") -> Note {
        flush()
        let fm = FileManager.default
        try? fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: Date())
        var id = "Note \(stamp)"
        var counter = 2
        while fm.fileExists(atPath: fileURL(for: id).path) {
            id = "Note \(stamp) (\(counter))"
            counter += 1
        }

        let note = Note(id: id, content: content, createdAt: Date(), modifiedAt: Date())
        try? content.write(to: fileURL(for: id), atomically: true, encoding: .utf8)
        setColorHex(Self.palette[notes.count % Self.palette.count].hex, for: id)
        notes.append(note)
        selectedID = id
        return note
    }

    func deleteSelected() {
        guard let index = selectedIndex else { return }
        let note = notes[index]
        pendingSaves.remove(note.id)
        setColorHex(nil, for: note.id)

        let url = fileURL(for: note.id)
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch { try? FileManager.default.removeItem(at: url) }

        notes.remove(at: index)
        if notes.isEmpty {
            createNote()
        } else {
            selectedID = notes[min(index, notes.count - 1)].id
        }
    }

    func selectRelative(_ offset: Int) {
        guard let index = selectedIndex else { return }
        let target = index + offset
        guard notes.indices.contains(target) else { return }
        selectedID = notes[target].id
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([notesDirectory])
    }

    func revealSelectedInFinder() {
        guard let id = selectedID else { return }
        flush()
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: id)])
    }

    // MARK: - Note colors

    func color(for id: String) -> Color {
        Color(nsColor: nsColor(for: id))
    }

    func nsColor(for id: String) -> NSColor {
        if let hex = noteColors[id], let custom = NSColor(hex: hex) {
            return custom
        }
        return NSColor(hex: Self.palette[Self.autoPaletteIndex(for: id)].hex)!
    }

    /// Pass nil to reset back to the auto-generated color.
    func setColorHex(_ hex: String?, for id: String) {
        if let hex {
            noteColors[id] = hex
        } else {
            noteColors.removeValue(forKey: id)
        }
        UserDefaults.standard.set(noteColors, forKey: Self.noteColorsKey)
    }

    /// Stable across launches, unlike Hashable's seeded hashValue.
    private static func autoPaletteIndex(for id: String) -> Int {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(palette.count))
    }

    // MARK: - iCloud migration

    private func migrate(toICloud: Bool) {
        flush()
        guard let ubiquityNotesURL else {
            reload()
            watchDirectory()
            return
        }

        let source = toICloud ? localNotesURL : ubiquityNotesURL
        let destination = toICloud ? ubiquityNotesURL : localNotesURL

        Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
            let files = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []

            for file in files where file.pathExtension.lowercased() == "md" {
                var target = destination.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    let name = file.deletingPathExtension().lastPathComponent
                    target = destination.appendingPathComponent("\(name) (moved).md")
                }
                do {
                    try fm.setUbiquitous(toICloud, itemAt: file, destinationURL: target)
                } catch {
                    try? fm.copyItem(at: file, to: target)
                    try? fm.removeItem(at: file)
                }
            }

            await MainActor.run {
                self?.reload()
                self?.watchDirectory()
            }
        }
    }

    // MARK: - Directory watching

    private func watchDirectory() {
        directoryMonitor?.cancel()
        directoryMonitor = nil

        let fd = open(notesDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reloadTask?.cancel()
                self.reloadTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    self.reload()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryMonitor = source
    }

    private func fileURL(for id: String) -> URL {
        notesDirectory.appendingPathComponent(id).appendingPathExtension("md")
    }

    private static let welcomeContent = """
    # Welcome to NeoNotes 👋

    Your notes live in the **menu bar** — always one click away.

    ## Markdown, built in
    - **Bold**, *italic*, ~~strikethrough~~
    - `inline code` and fenced blocks
    - [Links](https://example.com)
    - > Quotes

    ## Tips
    - ⌘N — new note
    - ⌘[ and ⌘] — switch notes
    - Turn on **iCloud sync** in Settings

    Happy noting!
    """
}
