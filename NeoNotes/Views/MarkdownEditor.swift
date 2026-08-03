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
            context.coordinator.noteID = noteID
            context.coordinator.editorUndoManager.removeAllActions()
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
        let editorUndoManager = UndoManager()

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
