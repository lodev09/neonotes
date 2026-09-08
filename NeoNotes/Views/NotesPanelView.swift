import SwiftUI

/// Toolbar-like icon button: comfortable hit target + hover/press highlight.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }

    private struct ButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering = $0 }
        }
    }
}

/// Same hover highlight for controls that can't take a ButtonStyle (Menus).
struct HoverChrome<Content: View>: View {
    @State private var hovering = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(minWidth: 25, minHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(hovering ? 0.07 : 0))
            )
            .onHover { hovering = $0 }
    }
}

struct NotesPanelView: View {
    private static let minPanelSize = CGSize(width: 340, height: 400)
    private static let maxPanelSize = CGSize(width: 800, height: 1000)

    @EnvironmentObject private var store: NoteStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("panelWidth") private var panelWidth = 460.0
    @AppStorage("panelHeight") private var panelHeight = 580.0
    @State private var footerHeight: CGFloat = 40
    @State private var dotsWidth: CGFloat = 0
    @State private var contentUnderFooter = false
    @State private var isPreviewing = false
    @State private var confirmingDelete = false
    @State private var dragStartIndex: Int?
    @State private var draggingID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            Divider()
            Group {
                if isPreviewing {
                    MarkdownPreview(
                        text: store.selectedNote?.content ?? "",
                        bottomInset: footerHeight,
                        onFooterOcclusionChange: { contentUnderFooter = $0 },
                        onToggleTask: { toggleTask(atLine: $0) }
                    )
                } else {
                    MarkdownEditor(
                        text: contentBinding,
                        noteID: store.selectedID ?? "",
                        bottomInset: footerHeight,
                        stats: statsText,
                        fileName: fileName,
                        onRevealFile: { store.revealSelectedInFinder() },
                        onFooterOcclusionChange: { contentUnderFooter = $0 }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                footer
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(contentUnderFooter ? 1 : 0)
                            .animation(.easeInOut(duration: 0.15), value: contentUnderFooter)
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        footerHeight = height
                    }
            }
            .overlay(alignment: .bottom) {
                if confirmingDelete {
                    deleteConfirmBar
                        .padding(.bottom, footerHeight + 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: confirmingDelete)
        }
        .frame(width: panelWidth, height: panelHeight)
        .overlay {
            ResizeEdges(
                width: $panelWidth,
                height: $panelHeight,
                minSize: Self.minPanelSize,
                maxSize: Self.maxPanelSize
            )
        }
        .onAppear { store.reload() }
        .onDisappear { store.flush() }
        .background {
            // Shortcuts inside Menu items only work while the menu is open;
            // this invisible button makes ⌘, work from the panel itself
            Button("") { openAppSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func openAppSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func toggleTask(atLine lineIndex: Int) {
        guard let note = store.selectedNote else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex),
              let toggled = MarkdownSyntax.togglingTask(in: lines[lineIndex]) else { return }
        lines[lineIndex] = toggled
        store.updateContent(lines.joined(separator: "\n"), for: store.selectedID)
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.selectedNote?.content ?? "" },
            set: { store.updateContent($0, for: store.selectedID) }
        )
    }

    private var header: some View {
        HStack(spacing: 4) {
            HoverChrome {
                // Menu labels don't compress, so the title lives outside
                // and the Menu is a transparent hit layer on top
                HStack(spacing: 6) {
                    Text(store.selectedNote?.title ?? "NeoNotes")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .overlay {
                    Menu {
                        ForEach(store.notes) { note in
                            Button {
                                store.selectedID = note.id
                            } label: {
                                if note.id == store.selectedID {
                                    Label(note.title, systemImage: "checkmark")
                                } else {
                                    Text(note.title)
                                }
                            }
                        }
                        Divider()
                        Button("New Note") { store.createNote() }
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                }
            }

            Spacer(minLength: 0)

            Button {
                store.createNote()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note (⌘N)")
        }
    }

    private var settingsMenu: some View {
        HoverChrome {
            Menu {
                Button("About NeoNotes") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "about")
                }
                Button("Settings") { openAppSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Quit NeoNotes") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 25, height: 25)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var footer: some View {
        let dotSize = dotSize(available: dotsWidth)
        return HStack(spacing: 8) {
            // Dots shrink to fit their space; controls keep their size
            HStack(spacing: 0) {
                ForEach(store.notes) { note in
                    noteDot(note, size: dotSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                dotsWidth = width
            }

            if store.selectedNote != nil {
                Button {
                    isPreviewing.toggle()
                } label: {
                    Image(systemName: "textformat")
                        .foregroundStyle(
                            isPreviewing
                                ? AnyShapeStyle(store.color(for: store.selectedID ?? ""))
                                : AnyShapeStyle(.secondary)
                        )
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut("e", modifiers: .command)
                .help(isPreviewing ? "Edit (⌘E)" : "Preview (⌘E)")

                Button {
                    store.revealSelectedInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(IconButtonStyle())
                .help("Show Note in Finder")

                Button {
                    if store.selectedNote?.isEmpty ?? false {
                        confirmingDelete = false
                        store.deleteSelected()
                    } else {
                        confirmingDelete.toggle()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle())
                .help("Delete Note")
            }

            Divider()
                .frame(height: 16)

            settingsMenu
        }
        .animation(.spring(duration: 0.25), value: store.selectedID)
        .animation(.spring(duration: 0.25), value: store.notes.map(\.id))
        .animation(.spring(duration: 0.2, bounce: 0.3), value: draggingID)
        .onChange(of: store.selectedID) { _, _ in
            confirmingDelete = false
        }
        .background {
            Group {
                Button("") { store.selectRelative(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("") { store.selectRelative(1) }
                    .keyboardShortcut("]", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    private var fileName: String {
        store.selectedNote.map { "\($0.id).md" } ?? ""
    }

    private var statsText: String {
        guard let note = store.selectedNote else { return "" }
        return "\(fileName) · \(note.wordCount) words"
    }

    private var deleteConfirmBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
            Text("Delete “\(store.selectedNote?.title ?? "")”?")
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Cancel") {
                confirmingDelete = false
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)

            Button("Delete") {
                confirmingDelete = false
                store.deleteSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        }
        .frame(maxWidth: 400)
        .padding(.horizontal, 12)
    }

    /// Largest dot size that lets every capsule fit the available width.
    private func dotSize(available: CGFloat) -> CGFloat {
        let count = CGFloat(max(store.notes.count, 1))
        guard available > 0 else { return 13 }
        // n dots at (s + 12pt hit padding), selected one stretches by 1.15s
        let fitted = (available - 12 * count) / (count + 1.15)
        return min(13, max(5, fitted))
    }

    private func noteDot(_ note: Note, size: CGFloat) -> some View {
        let isSelected = note.id == store.selectedID
        let height = size
        let width = pillWidth(note, size: size)

        // Same view tree whether selected or not, so SwiftUI animates the
        // resize instead of crossfading. Clicks/drags go to an AppKit view:
        // a SwiftUI Menu opens on mouse-down and would swallow the drag.
        return Capsule()
            .fill(store.color(for: note.id))
            .frame(width: width, height: height)
            .scaleEffect(draggingID == note.id ? 1.3 : 1)
            .padding(.horizontal, 6)
            .frame(height: 25)
            .zIndex(draggingID == note.id ? 1 : 0)
            .overlay {
                DotHitArea(
                    toolTip: isSelected ? "\(note.title) — Note Color · Drag to Reorder" : note.title,
                    onClick: { store.selectedID = note.id },
                    menu: isSelected ? { colorMenu(for: note) } : nil,
                    onPress: { draggingID = note.id },
                    onDrag: { dragDot(note, by: $0, size: size) },
                    onRelease: {
                        dragStartIndex = nil
                        draggingID = nil
                    }
                )
            }
    }

    private func pillWidth(_ note: Note, size: CGFloat) -> CGFloat {
        note.id == store.selectedID ? ceil(size * 2.15) : size
    }

    /// Pill plus its 6pt hit padding on each side
    private func dotWidth(_ note: Note, size: CGFloat) -> CGFloat {
        pillWidth(note, size: size) + 12
    }

    private func dragDot(_ note: Note, by dx: CGFloat, size: CGFloat) {
        if dragStartIndex == nil { dragStartIndex = store.notes.firstIndex { $0.id == note.id } }
        guard let start = dragStartIndex else { return }
        // The other dots keep their relative order during the drag, so
        // measure against them: drop where the dragged dot's center lands
        let others = store.notes.filter { $0.id != note.id }
        let leading = others.prefix(start).reduce(0) { $0 + dotWidth($1, size: size) }
        let center = leading + dx + dotWidth(note, size: size) / 2
        var target = 0
        var x: CGFloat = 0
        for other in others {
            let width = dotWidth(other, size: size)
            if x + width / 2 < center { target += 1 }
            x += width
        }
        store.moveNote(note.id, to: target)
    }

    private func colorMenu(for note: Note) -> NSMenu {
        let menu = NSMenu()
        for entry in NoteStore.palette {
            menu.addItem(ClosureMenuItem(entry.name) { store.setColorHex(entry.hex, for: note.id) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Custom…") {
            ColorPanelBridge.shared.present(initial: store.nsColor(for: note.id)) { picked in
                if let hex = picked.hexString {
                    store.setColorHex(hex, for: note.id)
                }
            }
        })
        menu.addItem(ClosureMenuItem("Auto") { store.setColorHex(nil, for: note.id) })
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() { handler() }
}

/// Transparent hit target: click selects or pops the menu, horizontal drag reports its delta.
struct DotHitArea: NSViewRepresentable {
    var toolTip: String
    var onClick: () -> Void
    var menu: (() -> NSMenu)?
    var onPress: () -> Void
    var onDrag: ((CGFloat) -> Void)?
    var onRelease: () -> Void

    func makeNSView(context: Context) -> DotHitView {
        DotHitView()
    }

    func updateNSView(_ view: DotHitView, context: Context) {
        view.toolTip = toolTip
        view.onClick = onClick
        view.makeMenu = menu
        view.onPress = onPress
        view.onDrag = onDrag
        view.onRelease = onRelease
    }
}

final class DotHitView: NSView {
    var onClick: () -> Void = {}
    var makeMenu: (() -> NSMenu)?
    var onPress: () -> Void = {}
    var onDrag: ((CGFloat) -> Void)?
    var onRelease: () -> Void = {}

    private var dragStartX: CGFloat?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        dragging = false
        onPress()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let onDrag, let dragStartX else { return }
        let dx = event.locationInWindow.x - dragStartX
        if !dragging, abs(dx) < 4 { return }
        dragging = true
        onDrag(dx)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartX = nil; dragging = false }
        onRelease()
        guard !dragging else { return }
        if let makeMenu {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        } else {
            onClick()
        }
    }
}
