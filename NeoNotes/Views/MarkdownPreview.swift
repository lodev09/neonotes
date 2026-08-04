import SwiftUI

/// Read-only rendered view of a note's markdown.
struct MarkdownPreview: View {
    let text: String
    var bottomInset: CGFloat = 0
    var onFooterOcclusionChange: ((Bool) -> Void)?
    var onToggleTask: ((_ lineIndex: Int) -> Void)?

    @State private var contentMaxY: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private static let bottomPadding: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, bottomInset + Self.bottomPadding)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named("previewScroll")).maxY
            } action: { maxY in
                contentMaxY = maxY
                reportOcclusion()
            }
        }
        .coordinateSpace(name: "previewScroll")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            viewportHeight = height
            reportOcclusion()
        }
    }

    private func reportOcclusion() {
        guard viewportHeight > 0 else { return }
        let textBottom = contentMaxY - (bottomInset + Self.bottomPadding)
        onFooterOcclusionChange?(textBottom > viewportHeight - bottomInset + 1)
    }

    // MARK: - Blocks

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String)
        case quote(String)
        case listItem(marker: String, text: String)
        case task(done: Bool, text: String, line: Int)
        case rule
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 3)
        case .paragraph(let string):
            Text(inline(string))
                .font(.system(size: 13.5))
                .lineSpacing(2.5)
        case .code(let string):
            Text(string)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.separator, lineWidth: 1)
                        }
                }
        case .quote(let string):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(inline(string))
                    .font(.system(size: 13.5))
                    .italic()
                    .foregroundStyle(.secondary)
            }
        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(inline(text))
                    .font(.system(size: 13.5))
                    .lineSpacing(2.5)
            }
            .padding(.leading, 4)
        case .task(let done, let text, let line):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Button {
                    onToggleTask?(line)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12.5))
                        .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                Text(inline(text))
                    .font(.system(size: 13.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            .padding(.leading, 4)
        case .rule:
            Divider().padding(.vertical, 2)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 21, weight: .bold)
        case 2: .system(size: 17.5, weight: .semibold)
        case 3: .system(size: 15, weight: .semibold)
        default: .system(size: 13.5, weight: .semibold)
        }
    }

    private func inline(_ string: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)

        let codeRanges = attributed.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRanges {
            attributed[range].font = .system(size: 12.5, design: .monospaced)
            attributed[range].foregroundColor = Color(nsColor: .systemPink)
            attributed[range].backgroundColor = Color(nsColor: .textBackgroundColor).opacity(0.55)
        }
        return attributed
    }

    // MARK: - Parsing

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
