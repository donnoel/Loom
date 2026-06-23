import Foundation

actor SessionSearchService {
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
    }

    func search(
        query: String,
        in sessions: [Session],
        maxResults: Int = 50
    ) async -> [SessionSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard maxResults > 0 else { return [] }

        var results: [SessionSearchResult] = []
        results.reserveCapacity(min(32, maxResults))

        for session in sessions {
            guard !Task.isCancelled else { return results }

            if let titleRange = Self.firstMatchRange(in: session.metadata.title, for: trimmedQuery) {
                results.append(
                    SessionSearchResult(
                        sessionID: session.id,
                        sessionTitle: session.metadata.title,
                        snippet: Self.snippet(in: session.metadata.title, around: titleRange),
                        source: .title,
                        messageID: nil,
                        messageRole: nil
                    )
                )
                if results.count >= maxResults { return results }
            }

            do {
                let messages = try await store.loadMessages(sessionID: session.id)
                guard !Task.isCancelled else { return results }

                for message in messages {
                    guard let messageRange = Self.firstMatchRange(in: message.content, for: trimmedQuery) else {
                        continue
                    }

                    results.append(
                        SessionSearchResult(
                            sessionID: session.id,
                            sessionTitle: session.metadata.title,
                            snippet: Self.snippet(in: message.content, around: messageRange),
                            source: .message,
                            messageID: message.id,
                            messageRole: message.role
                        )
                    )
                    if results.count >= maxResults { return results }
                }
            } catch {
                // Ignore per-session read failures to keep global search resilient.
                continue
            }
        }

        return results
    }

    private static func firstMatchRange(in text: String, for query: String) -> Range<String.Index>? {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    private static func snippet(in text: String, around range: Range<String.Index>) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        let start = normalized.index(range.lowerBound, offsetBy: -36, limitedBy: normalized.startIndex) ?? normalized.startIndex
        let end = normalized.index(range.upperBound, offsetBy: 36, limitedBy: normalized.endIndex) ?? normalized.endIndex

        var value = String(normalized[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > normalized.startIndex {
            value = "…\(value)"
        }
        if end < normalized.endIndex {
            value = "\(value)…"
        }
        return value
    }
}
