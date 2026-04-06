import Foundation

enum SearchMatcher {
    static func matches(query: String, fields: [String?]) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return false
        }

        let haystack = normalize(fields.compactMap { $0 }.joined(separator: " "))
        guard !haystack.isEmpty else {
            return false
        }

        if haystack.contains(normalizedQuery) {
            return true
        }

        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        return !tokens.isEmpty && tokens.allSatisfy { haystack.contains($0) }
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
