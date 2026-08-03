import AppKit

enum MarkdownHighlighter {
    static let fontSize: CGFloat = 13.5

    static var baseFont: NSFont { .systemFont(ofSize: fontSize) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2.5
        return style
    }()

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let heading = regex("^(#{1,6})[ \t].*$")
    private static let blockquote = regex("^[ \t]*>.*$")
    private static let listMarker = regex("^[ \t]*(?:[-*+]|\\d+\\.)[ \t]")
    private static let taskBox = regex("^[ \t]*[-*+][ \t]\\[( |x|X)\\]")
    private static let horizontalRule = regex("^[ \t]*(-{3,}|\\*{3,}|_{3,})[ \t]*$")
    private static let bold = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", [])
    private static let italic = regex("(?<![*_])[*_](?![*_\\s])([^*_\n]+)(?<![\\s])[*_](?![*_])", [])
    private static let strikethrough = regex("~~(?=\\S)(.+?)(?<=\\S)~~", [])
    private static let inlineCode = regex("`[^`\n]+`", [])
    private static let link = regex("\\[([^\\]\n]*)\\]\\(([^)\n]+)\\)", [])
    private static let codeFence = regex("^```.*?^```[ \t]*$", [.anchorsMatchLines, .dotMatchesLineSeparators])

    static func highlight(_ storage: NSTextStorage) {
        highlight(storage, range: NSRange(location: 0, length: storage.length))
    }

    /// Re-highlights only the edited paragraphs. Full-document passes on every
    /// keystroke invalidate all layout and make the scroll position jump.
    static func highlightEdited(_ storage: NSTextStorage, around editRange: NSRange) {
        let text = storage.string as NSString
        // Fences span paragraphs; fall back to a full pass when present
        if text.range(of: "```").location != NSNotFound {
            highlight(storage)
            return
        }
        let location = min(editRange.location, text.length)
        let length = min(editRange.length, text.length - location)
        highlight(storage, range: text.paragraphRange(for: NSRange(location: location, length: length)))
    }

    private static func highlight(_ storage: NSTextStorage, range full: NSRange) {
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(typingAttributes, range: full)

        heading.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            let size: CGFloat = level == 1 ? 19 : (level == 2 ? 16.5 : 14.5)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 1))
        }

        blockquote.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .obliqueness: 0.12,
            ], range: match.range)
        }

        listMarker.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range)
        }

        taskBox.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range)
        }

        horizontalRule.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range)
        }

        bold.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .semibold), range: match.range)
            dimMarkers(storage, match: match, markerLength: 2)
        }

        italic.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.obliqueness, value: 0.12, range: match.range)
            dimMarkers(storage, match: match, markerLength: 1)
        }

        strikethrough.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: match.range(at: 1))
            dimMarkers(storage, match: match, markerLength: 2)
        }

        link.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range(at: 1))
        }

        inlineCode.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.06),
            ], range: match.range)
        }

        codeFence.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.setAttributes([
                .font: monoFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle,
            ], range: match.range)
        }

        storage.endEditing()
    }

    private static func dimMarkers(_ storage: NSTextStorage, match: NSTextCheckingResult, markerLength: Int) {
        let range = match.range
        guard range.length > markerLength * 2 else { return }
        let opening = NSRange(location: range.location, length: markerLength)
        let closing = NSRange(location: range.location + range.length - markerLength, length: markerLength)
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: opening)
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closing)
    }
}
