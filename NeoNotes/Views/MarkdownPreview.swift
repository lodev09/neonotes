import AppKit
import SwiftUI

private extension NSAttributedString.Key {
    /// Source line index of a task checkbox, set on the checkbox range.
    static let taskLine = NSAttributedString.Key("taskLine")
    /// Marks fenced code paragraphs so the layout manager can draw a card behind them.
    static let codeBlock = NSAttributedString.Key("codeBlock")
}

/// Draws a rounded card behind fenced code blocks.
private final class PreviewLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.codeBlock, in: charRange) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var rect = boundingRect(forGlyphRange: glyphs, in: container)
                rect.origin.x = container.lineFragmentPadding
                rect.size.width = container.size.width - container.lineFragmentPadding * 2
                rect = rect.insetBy(dx: -6, dy: -5).offsetBy(dx: origin.x, dy: origin.y)

                let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                NSColor.textBackgroundColor.withAlphaComponent(0.55).setFill()
                path.fill()
                NSColor.separatorColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Selectable text view that forwards checkbox clicks.
private final class PreviewTextView: NSTextView {
    var onToggleTask: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, toggleTask(at: convert(event.locationInWindow, from: nil)) {
            return
        }
        super.mouseDown(with: event)
    }

    private func toggleTask(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let textStorage else { return false }
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
        guard index < textStorage.length else { return false }

        var boxRange = NSRange()
        guard let line = textStorage.attribute(.taskLine, at: index, effectiveRange: &boxRange) as? Int
        else { return false }

        let glyphs = layoutManager.glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil)
        let boxRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        guard boxRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return false }

        onToggleTask?(line)
        return true
    }
}

/// Read-only rendered view of a note's markdown with native text selection.
struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var bottomInset: CGFloat = 0
    var onFooterOcclusionChange: ((Bool) -> Void)?
    var onToggleTask: ((_ lineIndex: Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = PreviewLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = PreviewTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        textView.linkTextAttributes = linkAttributes
        textView.onToggleTask = { [weak coordinator = context.coordinator] line in
            coordinator?.parent.onToggleTask?(line)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        storage.setAttributedString(MarkdownRenderer.render(text))
        context.coordinator.textView = textView
        context.coordinator.renderedText = text

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
        guard let textView = scrollView.documentView as? PreviewTextView else { return }

        if scrollView.contentInsets.bottom != bottomInset {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }

        if context.coordinator.renderedText != text {
            context.coordinator.renderedText = text
            let visibleOrigin = scrollView.contentView.bounds.origin
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
            textView.scroll(visibleOrigin)
        }
        DispatchQueue.main.async {
            context.coordinator.updateFooterOcclusion()
        }
    }

    final class Coordinator: NSObject {
        var parent: MarkdownPreview
        weak var textView: NSTextView?
        var renderedText: String?
        private var contentUnderFooter = false

        init(_ parent: MarkdownPreview) {
            self.parent = parent
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

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Rendering

private enum MarkdownRenderer {
    static let fontSize: CGFloat = 13.5

    static func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = parse(text)
        for (index, block) in blocks.enumerated() {
            result.append(render(block))
            if index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                ]))
            }
        }
        return result
    }

    private static func render(_ block: Block) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            let size: CGFloat = level == 1 ? 21 : (level == 2 ? 17.5 : 15)
            let weight: NSFont.Weight = level == 1 ? .bold : .semibold
            let heading = NSMutableAttributedString(attributedString: inline(text, font: .systemFont(ofSize: size, weight: weight)))
            heading.addAttribute(
                .paragraphStyle,
                value: style(before: level <= 2 ? 8 : 4),
                range: NSRange(location: 0, length: heading.length)
            )
            return heading

        case .paragraph(let text):
            return inline(text)

        case .code(let code):
            let attributed = NSMutableAttributedString(string: code, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style(before: 8, after: 14, firstIndent: 4, headIndent: 4),
            ])
            attributed.addAttribute(.codeBlock, value: true, range: NSRange(location: 0, length: attributed.length))
            return attributed

        case .quote(let text):
            let quote = NSMutableAttributedString()
            quote.append(NSAttributedString(string: "▎", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
            let body = NSMutableAttributedString(attributedString: inline(text, color: .secondaryLabelColor))
            body.addAttribute(.obliqueness, value: 0.12, range: NSRange(location: 0, length: body.length))
            quote.append(body)
            quote.addAttribute(
                .paragraphStyle,
                value: style(headIndent: 12),
                range: NSRange(location: 0, length: quote.length)
            )
            return quote

        case .listItem(let marker, let text):
            let item = NSMutableAttributedString(string: "\(marker)\t", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
            ])
            item.append(inline(text))
            item.addAttribute(
                .paragraphStyle,
                value: style(after: 4, firstIndent: 4, headIndent: 22, tabStop: 22),
                range: NSRange(location: 0, length: item.length)
            )
            return item

        case .task(let done, let text, let line):
            let item = NSMutableAttributedString()
            let attachment = NSTextAttachment()
            attachment.image = checkboxImage(done: done)
            attachment.bounds = NSRect(x: 0, y: -2.5, width: 14, height: 14)
            item.append(NSAttributedString(attachment: attachment))
            item.append(NSAttributedString(string: "\t"))
            item.addAttribute(.taskLine, value: line, range: NSRange(location: 0, length: item.length))
            item.append(inline(text, color: done ? .secondaryLabelColor : .labelColor))
            item.addAttribute(
                .paragraphStyle,
                value: style(after: 4, firstIndent: 4, headIndent: 22, tabStop: 22),
                range: NSRange(location: 0, length: item.length)
            )
            return item

        case .blank:
            return NSAttributedString()

        case .rule:
            return NSAttributedString(
                string: String(repeating: "─", count: 24),
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.quaternaryLabelColor,
                    .paragraphStyle: style(before: 4, after: 12),
                ]
            )
        }
    }

    private static func checkboxImage(done: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .regular)
        guard let symbol = NSImage(
            systemSymbolName: done ? "checkmark.square.fill" : "square",
            accessibilityDescription: done ? "Completed" : "To do"
        )?.withSymbolConfiguration(config) else { return nil }

        let color: NSColor = done ? .controlAccentColor : .secondaryLabelColor
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
    }

    private static func style(
        before: CGFloat = 0,
        after: CGFloat = 9,
        firstIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        tabStop: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2.5
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = firstIndent
        style.headIndent = headIndent
        if let tabStop {
            style.tabStops = [NSTextTab(textAlignment: .left, location: tabStop)]
        }
        return style
    }

    /// Resolves inline markdown (bold, italic, code, links, strikethrough)
    /// into concrete attributes, since NSTextView doesn't interpret intents.
    private static func inline(
        _ string: String,
        font baseFont: NSFont = NSFont.systemFont(ofSize: MarkdownRenderer.fontSize),
        color: NSColor = .labelColor
    ) -> NSAttributedString {
        let parsed = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: color,
            ]
            if intent.contains(.code) {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
                attributes[.foregroundColor] = NSColor.systemPink
                attributes[.backgroundColor] = NSColor.textBackgroundColor.withAlphaComponent(0.55)
            } else if intent.contains(.stronglyEmphasized) {
                attributes[.font] = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
            }
            if intent.contains(.emphasized) {
                attributes[.obliqueness] = 0.12
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            }
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String)
        case quote(String)
        case listItem(marker: String, text: String)
        case task(done: Bool, text: String, line: Int)
        case rule
        case blank
    }

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
    private static let taskRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+\\[( |x|X)\\]\\s*(.*)$")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+(.*)$")
    private static let orderedRegex = try! NSRegularExpression(pattern: "^(\\d+)[.)]\\s+(.*)$")
    private static let ruleRegex = try! NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})$")

    private static func groups(_ regex: NSRegularExpression, _ string: String) -> [String]? {
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        return (0..<match.numberOfRanges).map {
            guard let r = Range(match.range(at: $0), in: string) else { return "" }
            return String(string[r])
        }
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote = []
            }
        }

        for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix("```") {
                    inCode = false
                    blocks.append(.code(code.joined(separator: "\n")))
                    code = []
                } else {
                    code.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushQuote()
                inCode = true
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                blocks.append(.blank)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            if let m = groups(headingRegex, trimmed) {
                flushParagraph()
                blocks.append(.heading(level: m[1].count, text: m[2]))
            } else if groups(ruleRegex, trimmed) != nil {
                flushParagraph()
                blocks.append(.rule)
            } else if let m = groups(taskRegex, trimmed) {
                flushParagraph()
                blocks.append(.task(done: m[1].lowercased() == "x", text: m[2], line: lineIndex))
            } else if let m = groups(bulletRegex, trimmed) {
                flushParagraph()
                blocks.append(.listItem(marker: "•", text: m[1]))
            } else if let m = groups(orderedRegex, trimmed) {
                flushParagraph()
                blocks.append(.listItem(marker: "\(m[1]).", text: m[2]))
            } else {
                paragraph.append(trimmed)
            }
        }

        if inCode, !code.isEmpty {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushParagraph()
        flushQuote()
        return blocks
    }
}
