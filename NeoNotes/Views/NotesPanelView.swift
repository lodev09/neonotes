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
                } label: {
                    HStack(spacing: 6) {
                        Text(store.selectedNote?.title ?? "NeoNotes")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Spacer()

            Button {
                store.createNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note (⌘N)")

            HoverChrome {
                Menu {
                    Button("About NeoNotes") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "about")
                    }
                    Button("Settings…") { openAppSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                    Divider()
                    Button("Quit NeoNotes") { NSApp.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "ellipsis.circle")
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
    }

    private var footer: some View {
        let dotSize = dotSize(available: dotsWidth)
        return HStack(spacing: 8) {
            // Dots shrink to fit their space; controls keep their size
            HStack(spacing: 6) {
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

        }
        .animation(.spring(duration: 0.25), value: store.selectedID)
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

    private var statsText: String {
        "\(store.selectedNote?.wordCount ?? 0) words"
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
        // n dots at (s + 6pt hit padding), 6pt gaps, selected one stretches by 1.15s
        let fitted = (available - 12 * count + 6) / (count + 1.15)
        return min(13, max(5, fitted))
    }

    private func noteDot(_ note: Note, size: CGFloat) -> some View {
        let isSelected = note.id == store.selectedID
        let height = size
        let width: CGFloat = isSelected ? ceil(size * 2.15) : size

        // A single stable view per note: swapping Button/Menu on selection
        // makes SwiftUI crossfade instead of animating the resize.
        return Menu {
            colorMenuItems(for: note)
        } label: {
            Capsule()
                .fill(store.color(for: note.id).opacity(isSelected ? 1 : 0.45))
                .frame(width: width, height: height)
                .padding(3)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay {
            // Unselected: intercept the click to select instead of opening the menu
            if !isSelected {
                Button {
                    store.selectedID = note.id
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .help(isSelected ? "\(note.title) — Note Color" : note.title)
    }

    @ViewBuilder
    private func colorMenuItems(for note: Note) -> some View {
        ForEach(NoteStore.palette, id: \.hex) { entry in
            Button(entry.name) {
                store.setColorHex(entry.hex, for: note.id)
            }
        }
        Divider()
        Button("Custom…") {
            ColorPanelBridge.shared.present(initial: store.nsColor(for: note.id)) { picked in
                if let hex = picked.hexString {
                    store.setColorHex(hex, for: note.id)
                }
            }
        }
        Button("Auto") {
            store.setColorHex(nil, for: note.id)
        }
    }
}
