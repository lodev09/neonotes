import AppKit

enum MarkdownHighlighter {
    static let fontSizeKey = "editorFontSize"
    static let lineSpacingKey = "editorLineSpacing"
    static let defaultFontSize = 13.5
    static let defaultLineSpacing = 2.5
    static let fontSizeRange = 11.0...20.0
    static let lineSpacingRange = 0.0...10.0

    static var fontSize: CGFloat { setting(fontSizeKey, default: defaultFontSize) }
    static var lineSpacing: CGFloat { setting(lineSpacingKey, default: defaultLineSpacing) }

    private static func setting(_ key: String, default fallback: Double) -> CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: key) as? Double ?? fallback)
    }

    static var baseFont: NSFont { .systemFont(ofSize: fontSize) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) }

    /// Shared with the preview so both modes lay headings out on the same line height.
    static func headingFont(level: Int) -> NSFont {
        let scale: CGFloat = level == 1 ? 1.4 : (level == 2 ? 1.22 : 1.07)
        // Half-point steps keep headings on tidy sizes as the base font scales.
        return .systemFont(ofSize: (fontSize * scale * 2).rounded() / 2, weight: .semibold)
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

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
    // Underscore emphasis requires word boundaries; intraword underscores (a_b_c) are literal
    private static let bold = regex("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*|(?<!\\w)__(?=\\S)(.+?)(?<=\\S)__(?!\\w)", [])
    private static let italic = regex("(?<![*_])\\*(?![*_\\s])([^*_\n]+)(?<!\\s)\\*(?![*_])|(?<![*_\\w])_(?![*_\\s])([^*_\n]+)(?<!\\s)_(?![*_\\w])", [])
    private static let strikethrough = regex("~~(?=\\S)(.+?)(?<=\\S)~~", [])
    private static let inlineCode = regex("`[^`\n]+`", [])
    private static let link = MarkdownSyntax.link
    private static let bareLink = MarkdownSyntax.bareLink
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
            storage.addAttribute(.font, value: headingFont(level: match.range(at: 1).length), range: match.range)
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

        bareLink.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range)
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
