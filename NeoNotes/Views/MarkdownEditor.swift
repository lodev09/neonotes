import SwiftUI
import AppKit

/// NSTextView that draws a muted stats line below the last line of text.
final class StatsTextView: NSTextView {
    private static let statsGap: CGFloat = 12
    private static let statsHeight: CGFloat = 14

    var statsText: String = "" {
        didSet { if statsText != oldValue { needsDisplay = true } }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    // Extend the document so the stats line has room instead of
    // sitting at the very edge of the content
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if !statsText.isEmpty, let layoutManager, let textContainer {
            let needed = layoutManager.usedRect(for: textContainer).maxY
                + textContainerInset.height * 2
                + Self.statsGap + Self.statsHeight
            size.height = max(size.height, needed)
        }
        super.setFrameSize(size)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), openLink(at: point) {
            return
        }
        if event.clickCount == 1, toggleTaskBox(at: point) {
            return
        }
        super.mouseDown(with: event)
    }

    private func openLink(at point: NSPoint) -> Bool {
        guard let url = link(at: point) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let text = string as NSString
        guard index < text.length else { return nil }

        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        guard let match = MarkdownSyntax.linkMatch(
            in: text.substring(with: lineRange),
            at: index - lineRange.location
        ) else { return nil }

        // characterIndex(for:) snaps to the nearest glyph, so make sure the
        // pointer is actually over the link
        let absolute = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
        let glyphs = layoutManager.glyphRange(forCharacterRange: absolute, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        guard rect.contains(containerPoint) else { return nil }
        return match.url
    }

    private var linkTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTrackingArea { removeTrackingArea(linkTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        linkTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        if !refreshLinkCursor() {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !refreshLinkCursor() {
            super.cursorUpdate(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if !refreshLinkCursor(), let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if visibleRect.contains(point) {
                NSCursor.iBeam.set()
            }
        }
    }

    /// Sets the hand cursor when cmd is held over a link; returns whether it did.
    @discardableResult
    private func refreshLinkCursor() -> Bool {
        guard let window, NSEvent.modifierFlags.contains(.command) else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point), link(at: point) != nil else { return false }
        NSCursor.pointingHand.set()
        return true
    }

    private func toggleTaskBox(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let text = string as NSString
        guard index < text.length else { return false }

        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        guard let box = MarkdownSyntax.taskBoxRange(in: text.substring(with: lineRange)) else { return false }
        let boxRange = NSRange(location: lineRange.location + box.location, length: box.length)

        let glyphs = layoutManager.glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil)
        let boxRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        guard boxRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return false }

        let markRange = NSRange(location: boxRange.location + 1, length: 1)
        let mark = text.substring(with: markRange) == " " ? "x" : " "
        guard shouldChangeText(in: markRange, replacementString: mark) else { return false }
        textStorage?.replaceCharacters(in: markRange, with: mark)
        didChangeText()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !statsText.isEmpty, let layoutManager, let textContainer else { return }
        let used = layoutManager.usedRect(for: textContainer)
        let origin = textContainerOrigin
        (statsText as NSString).draw(
            at: NSPoint(
                x: origin.x + textContainer.lineFragmentPadding,
                y: origin.y + used.maxY + Self.statsGap
            ),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var noteID: String
    var bottomInset: CGFloat = 0
    var stats: String = ""
    var onFooterOcclusionChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = StatsTextView.scrollableTextView()
        let textView = scrollView.documentView as! StatsTextView
        textView.statsText = stats

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 16)
        textView.drawsBackground = false
        textView.typingAttributes = MarkdownHighlighter.typingAttributes

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        textView.string = text
        if let storage = textView.textStorage {
            MarkdownHighlighter.highlight(storage)
        }
        context.coordinator.textView = textView

        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.layoutChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.layoutChanged),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? StatsTextView else { return }
        textView.statsText = stats

        if scrollView.contentInsets.bottom != bottomInset {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }

        if context.coordinator.noteID != noteID {
            // Close the pending typing group on the outgoing note's undo manager
            textView.breakUndoCoalescing()
            context.coordinator.noteID = noteID
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownHighlighter.highlight(storage)
            }
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollToBeginningOfDocument(nil)
        } else if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownHighlighter.highlight(storage)
            }
            let location = min(selection.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        if textView.window != nil, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            textView.window?.makeFirstResponder(textView)
        }
        DispatchQueue.main.async {
            context.coordinator.updateFooterOcclusion()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        var noteID: String
        var didFocus = false
        var lastEditRange: NSRange?
        private var undoManagers: [String: UndoManager] = [:]

        var editorUndoManager: UndoManager {
            if let manager = undoManagers[noteID] { return manager }
            let manager = UndoManager()
            undoManagers[noteID] = manager
            return manager
        }

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            self.noteID = parent.noteID
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            lastEditRange = NSRange(
                location: affectedCharRange.location,
                length: (replacementString ?? "").utf16.count
            )
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // Coalesced typing makes undo swallow everything since the last
            // pause; per-line granularity keeps undo predictable
            textView.breakUndoCoalescing()
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            var line = text.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            guard let action = MarkdownSyntax.newlineAction(
                forLine: line,
                cursorOffset: selection.location - lineRange.location
            ) else { return false }

            switch action {
            case .continueList(let prefix):
                textView.insertText("\n" + prefix, replacementRange: selection)
            case .endList(let markerRange):
                let absolute = NSRange(
                    location: lineRange.location + markerRange.location,
                    length: markerRange.length
                )
                if textView.shouldChangeText(in: absolute, replacementString: "") {
                    textView.textStorage?.replaceCharacters(in: absolute, with: "")
                    textView.didChangeText()
                }
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            if let storage = textView.textStorage {
                // Union with the selection covers undo/redo, where
                // shouldChangeTextIn may not reflect the restored range
                let target = lastEditRange.map { NSUnionRange($0, textView.selectedRange()) }
                    ?? textView.selectedRange()
                MarkdownHighlighter.highlightEdited(storage, around: target)
            }
            lastEditRange = nil
            textView.typingAttributes = MarkdownHighlighter.typingAttributes
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
        }

        @objc func layoutChanged() {
            updateFooterOcclusion()
        }

        func updateFooterOcclusion() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let clip = scrollView.contentView
            let visibleBottom = clip.bounds.origin.y + clip.bounds.height
            let under = textView.frame.height - (visibleBottom - parent.bottomInset) > 1
            if under != contentUnderFooter {
                contentUnderFooter = under
                let callback = parent.onFooterOcclusionChange
                DispatchQueue.main.async { callback?(under) }
            }
        }
        private var contentUnderFooter = false

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
