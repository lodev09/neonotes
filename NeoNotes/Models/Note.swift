import Foundation

struct Note: Identifiable, Equatable {
    let id: String
    var content: String
    let createdAt: Date
    var modifiedAt: Date

    var title: String {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let stripped = trimmed.replacingOccurrences(
                of: "^[#>*+\\-\\s\\[\\]x]+",
                with: "",
                options: .regularExpression
            )
            return String((stripped.isEmpty ? trimmed : stripped).prefix(50))
        }
        return "New Note"
    }

    var wordCount: Int {
        content.split(whereSeparator: \.isWhitespace).count
    }

    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
