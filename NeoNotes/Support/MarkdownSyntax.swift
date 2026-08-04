import Foundation

/// Shared line-level markdown syntax helpers used by the editor and preview.
enum MarkdownSyntax {
    private static let taskBox = try! NSRegularExpression(
        pattern: "^[ \t]*[-*+][ \t]+(\\[( |x|X)\\])"
    )
    private static let listPrefix = try! NSRegularExpression(
        pattern: "^([ \t]*)(?:([-*+])[ \t]+(\\[(?: |x|X)\\][ \t]*)?|(\\d+)([.)])[ \t]+)"
    )
    static let link = try! NSRegularExpression(pattern: "\\[([^\\]\n]*)\\]\\(([^)\n]+)\\)")
    static let bareLink = try! NSRegularExpression(pattern: "https?://[^\\s<>\"')\\]]+")

    /// URL and range of the markdown or bare link containing `offset` in `line`, or nil.
    static func linkMatch(in line: String, at offset: Int) -> (url: URL, range: NSRange)? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in link.matches(in: line, range: range) where NSLocationInRange(offset, match.range) {
            guard let url = URL(string: ns.substring(with: match.range(at: 2))) else { return nil }
            return (url, match.range)
        }
        for match in bareLink.matches(in: line, range: range) where NSLocationInRange(offset, match.range) {
            guard let url = URL(string: ns.substring(with: match.range)) else { return nil }
            return (url, match.range)
        }
        return nil
    }

    /// Range of the checkbox ("[ ]" or "[x]") within a task line.
    static func taskBoxRange(in line: String) -> NSRange? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return taskBox.firstMatch(in: line, range: range)?.range(at: 1)
    }

    /// The line with its checkbox flipped, or nil if it's not a task line.
    static func togglingTask(in line: String) -> String? {
        guard let box = taskBoxRange(in: line) else { return nil }
        let ns = line as NSString
        let markRange = NSRange(location: box.location + 1, length: 1)
        let mark = ns.substring(with: markRange) == " " ? "x" : " "
        return ns.replacingCharacters(in: markRange, with: mark)
    }

    enum NewlineAction {
        /// Insert "\n" + prefix to continue the list.
        case continueList(prefix: String)
        /// Empty item: delete this range within the line to end the list.
        case endList(markerRange: NSRange)
    }

    /// What pressing Return should do on a list line, or nil for the default newline.
    static func newlineAction(forLine line: String, cursorOffset: Int) -> NewlineAction? {
        let ns = line as NSString
        guard let match = listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              cursorOffset >= match.range.length else { return nil }

        let rest = ns.substring(from: match.range.length).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty {
            return .endList(markerRange: NSRange(location: 0, length: ns.length))
        }

        let indent = ns.substring(with: match.range(at: 1))
        if match.range(at: 2).location != NSNotFound {
            var prefix = indent + ns.substring(with: match.range(at: 2)) + " "
            if match.range(at: 3).location != NSNotFound {
                prefix += "[ ] "
            }
            return .continueList(prefix: prefix)
        }
        let number = Int(ns.substring(with: match.range(at: 4))) ?? 0
        let delimiter = ns.substring(with: match.range(at: 5))
        return .continueList(prefix: indent + "\(number + 1)\(delimiter) ")
    }
}
