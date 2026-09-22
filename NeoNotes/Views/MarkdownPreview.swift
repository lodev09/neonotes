import AppKit
import SwiftUI

private extension NSAttributedString.Key {
    /// Source line index of a task checkbox, set on the checkbox range.
    static let taskLine = NSAttributedString.Key("taskLine")
    /// Marks fenced code paragraphs so the layout manager can draw a card behind them.
    static let codeBlock = NSAttributedString.Key("codeBlock")
    /// Marks a thematic break paragraph so the layout manager can draw a full-width line.
    static let horizontalRule = NSAttributedString.Key("horizontalRule")
}

/// Draws a rounded card behind fenced code blocks and full-width horizontal rules.
private final class PreviewLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.codeBlock, in: charRange) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var rect = boundingRect(forGlyphRange: glyphs, in: container)
                // NSTextView clips background drawing to the container rect,
                // so the stroke must stay inside it.
                rect.origin.x = 0.5
                rect.size.width = container.size.width - 1
                rect = rect.insetBy(dx: 0, dy: -5).offsetBy(dx: origin.x, dy: origin.y)

                let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                NSColor.textBackgroundColor.withAlphaComponent(0.55).setFill()
                path.fill()
                NSColor.separatorColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            storage.enumerateAttribute(.horizontalRule, in: charRange) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = boundingRect(forGlyphRange: glyphs, in: container)
                NSColor.separatorColor.setFill()
                NSRect(
                    x: origin.x,
                    y: origin.y + rect.midY - 0.5,
                    width: container.size.width,
                    height: 1
                ).fill()
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
    @AppStorage(MarkdownHighlighter.fontSizeKey) private var fontSize = MarkdownHighlighter.defaultFontSize
    @AppStorage(MarkdownHighlighter.lineSpacingKey) private var lineSpacing = MarkdownHighlighter.defaultLineSpacing

    let text: String
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
        textView.textContainerInset = NSSize(width: 10, height: 16)
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

        storage.setAttributedString(MarkdownRenderer.render(text))
        context.coordinator.textView = textView
        context.coordinator.renderedText = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? PreviewTextView else { return }

        if context.coordinator.fontSize != fontSize || context.coordinator.lineSpacing != lineSpacing {
            context.coordinator.fontSize = fontSize
            context.coordinator.lineSpacing = lineSpacing
            context.coordinator.renderedText = nil
        }

        if context.coordinator.renderedText != text {
            context.coordinator.renderedText = text
            let visibleOrigin = scrollView.contentView.bounds.origin
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
            // Layout is lazy and nothing else forces it inside the panel's
            // event loop, so the window would repaint one interaction late.
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.needsDisplay = true
            textView.scroll(visibleOrigin)
        }
    }

    final class Coordinator: NSObject {
        var parent: MarkdownPreview
        weak var textView: NSTextView?
        var renderedText: String?
        var fontSize = MarkdownHighlighter.defaultFontSize
        var lineSpacing = MarkdownHighlighter.defaultLineSpacing

        init(_ parent: MarkdownPreview) {
            self.parent = parent
        }
    }
}

// MARK: - Rendering

private enum MarkdownRenderer {
    static var fontSize: CGFloat { MarkdownHighlighter.fontSize }

    private static let bullet = "\u{25CF}"
    /// Horizontal shift per list nesting level.
    private static let listIndent: CGFloat = 18

    static func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = parse(text)
        for (index, block) in blocks.enumerated() {
            let rendered = render(block)
            result.append(rendered)
            // Table cells carry their own paragraph-terminating newlines.
            if index < blocks.count - 1, !rendered.string.hasSuffix("\n") {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .paragraphStyle: style(),
                ]))
            }
        }
        return result
    }

    private static func render(_ block: Block) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            let heading = NSMutableAttributedString(
                attributedString: inline(text, font: MarkdownHighlighter.headingFont(level: level))
            )
            heading.addAttribute(
                .paragraphStyle,
                value: style(),
                range: NSRange(location: 0, length: heading.length)
            )
            return heading

        case .paragraph(let text):
            let paragraph = NSMutableAttributedString(attributedString: inline(text))
            paragraph.addAttribute(
                .paragraphStyle,
                value: style(),
                range: NSRange(location: 0, length: paragraph.length)
            )
            return paragraph

        case .code(let code):
            let attributed = NSMutableAttributedString(string: code, attributes: [
                .font: MarkdownHighlighter.monoFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style(firstIndent: 4, headIndent: 4),
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

        case .listItem(let marker, let text, let level):
            let nested = CGFloat(level) * listIndent
            let item = NSMutableAttributedString(string: "\(marker)\t", attributes: markerAttributes(marker))
            item.append(inline(text))
            item.addAttribute(
                .paragraphStyle,
                value: style(firstIndent: 4 + nested, headIndent: 22 + nested, tabStop: 22 + nested),
                range: NSRange(location: 0, length: item.length)
            )
            return item

        case .task(let done, let text, let line, let level):
            let nested = CGFloat(level) * listIndent
            let item = NSMutableAttributedString()
            let attachment = NSTextAttachment()
            attachment.image = checkboxImage(done: done)
            attachment.bounds = NSRect(x: 0, y: -2.5, width: 14, height: 14)
            item.append(NSAttributedString(attachment: attachment))
            item.append(NSAttributedString(string: "\t"))
            item.addAttribute(.taskLine, value: line, range: NSRange(location: 0, length: item.length))
            item.addAttribute(.cursor, value: NSCursor.arrow, range: NSRange(location: 0, length: 1))
            item.append(inline(text, color: done ? .secondaryLabelColor : .labelColor))
            item.addAttribute(
                .paragraphStyle,
                value: style(firstIndent: 4 + nested, headIndent: 26 + nested, tabStop: 26 + nested),
                range: NSRange(location: 0, length: item.length)
            )
            return item

        case .table(let header, let alignments, let rows):
            return renderTable(header: header, alignments: alignments, rows: rows)

        case .blank:
            return NSAttributedString()

        case .rule:
            return NSAttributedString(
                string: "\u{00A0}",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .horizontalRule: true,
                    .paragraphStyle: style(),
                ]
            )
        }
    }

    private static func renderTable(
        header: [String],
        alignments: [NSTextAlignment],
        rows: [[String]]
    ) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = header.count
        table.collapsesBorders = true

        let result = NSMutableAttributedString()
        for (rowIndex, row) in ([header] + rows).enumerated() {
            for column in 0..<header.count {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: column,
                    columnSpan: 1
                )
                block.setBorderColor(.controlAccentColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setValue(100.0 / CGFloat(header.count), type: .percentageValueType, for: .width)
                if rowIndex == 0 {
                    block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.alignment = column < alignments.count ? alignments[column] : .left
                style.lineSpacing = MarkdownHighlighter.lineSpacing

                let font: NSFont = rowIndex == 0
                    ? .systemFont(ofSize: fontSize, weight: .semibold)
                    : .systemFont(ofSize: fontSize)
                let cell = NSMutableAttributedString(
                    attributedString: inline(column < row.count ? row[column] : "", font: font)
                )
                cell.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                cell.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cell.length))
                result.append(cell)
            }
        }
        return result
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private static let checkboxHostView = FlippedView()

    private static func checkboxImage(done: Bool) -> NSImage {
        let cell = NSButtonCell()
        cell.setButtonType(.switch)
        cell.title = ""
        cell.state = done ? .on : .off
        cell.controlSize = .small
        // Drawing handler re-runs on each draw, so appearance and accent
        // color changes are picked up without re-rendering.
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { rect in
            cell.draw(withFrame: rect, in: checkboxHostView)
            return true
        }
        image.accessibilityDescription = done ? "Completed" : "To do"
        return image
    }

    /// Bullets draw a larger glyph at a fraction of the text size, offset back up
    /// to the text's optical centre. Scaling "•" up instead would make the marker
    /// drive the line height and put list rows out of step with the editor.
    private static func markerAttributes(_ marker: String) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        if marker == bullet {
            attributes[.font] = NSFont.systemFont(ofSize: fontSize * 0.41)
            attributes[.baselineOffset] = fontSize * 0.14
        }
        return attributes
    }

    private static func style(
        firstIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        tabStop: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = MarkdownHighlighter.lineSpacing
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
        case listItem(marker: String, text: String, level: Int)
        case task(done: Bool, text: String, line: Int, level: Int)
        case table(header: [String], alignments: [NSTextAlignment], rows: [[String]])
        case rule
        case blank
    }

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$")
    private static let taskRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+\\[( |x|X)\\]\\s*(.*)$")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^[-*+]\\s+(.*)$")
    private static let orderedRegex = try! NSRegularExpression(pattern: "^(\\d+)[.)]\\s+(.*)$")
    private static let ruleRegex = try! NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})$")
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: "^\\|\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?$"
    )

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.components(separatedBy: "|")
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableAlignments(_ separator: String) -> [NSTextAlignment] {
        tableCells(separator).map { spec in
            switch (spec.hasPrefix(":"), spec.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }
    }

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

        let lines = text.components(separatedBy: "\n")
        var skipUntil = -1

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex <= skipUntil { continue }
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

            if trimmed.hasPrefix("|"), lineIndex + 1 < lines.count,
               groups(tableSeparatorRegex, lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)) != nil {
                let header = tableCells(trimmed)
                if !header.isEmpty {
                    flushParagraph()
                    let alignments = tableAlignments(lines[lineIndex + 1].trimmingCharacters(in: .whitespaces))
                    var rows: [[String]] = []
                    var next = lineIndex + 2
                    while next < lines.count {
                        let row = lines[next].trimmingCharacters(in: .whitespaces)
                        guard row.hasPrefix("|") else { break }
                        rows.append(tableCells(row))
                        next += 1
                    }
                    blocks.append(.table(header: header, alignments: alignments, rows: rows))
                    skipUntil = next - 1
                    continue
                }
            }

            if let m = groups(headingRegex, trimmed) {
                flushParagraph()
                blocks.append(.heading(level: m[1].count, text: m[2]))
            } else if groups(ruleRegex, trimmed) != nil {
                flushParagraph()
                blocks.append(.rule)
            } else if let m = groups(taskRegex, trimmed) {
                flushParagraph()
                let level = MarkdownSyntax.listLevel(of: line)
                blocks.append(.task(done: m[1].lowercased() == "x", text: m[2], line: lineIndex, level: level))
            } else if let m = groups(bulletRegex, trimmed) {
                flushParagraph()
                let level = MarkdownSyntax.listLevel(of: line)
                blocks.append(.listItem(marker: bullet, text: m[1], level: level))
            } else if let m = groups(orderedRegex, trimmed) {
                flushParagraph()
                let level = MarkdownSyntax.listLevel(of: line)
                blocks.append(.listItem(marker: "\(m[1]).", text: m[2], level: level))
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
