import AVFoundation
import Foundation

nonisolated struct VoiceReplyVoiceCandidate: Hashable, Sendable {
    let identifier: String
    let name: String
    let language: String
    let qualityRank: Int

    init(identifier: String, name: String, language: String, qualityRank: Int) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.qualityRank = qualityRank
    }

    init(voice: AVSpeechSynthesisVoice) {
        self.init(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            qualityRank: Self.qualityRank(for: voice.quality)
        )
    }

    private static func qualityRank(for quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            return 0
        case .enhanced:
            return 1
        case .default:
            return 2
        @unknown default:
            return 3
        }
    }
}

nonisolated enum VoiceReplyVoiceCatalog {
    private static let preferredDefaultVoiceNames = [
        "Lekha",
        "Piya",
        "Geeta",
        "Vani",
        "Samantha",
        "Kathy"
    ]

    private static let supportedVoiceNames = Set(preferredDefaultVoiceNames)
    private static let indiaLanguagePrefixes = ["hi-IN", "bn-IN", "te-IN", "ta-IN", "kn-IN", "en-IN"]

    static func recommendedCandidates(
        from candidates: [VoiceReplyVoiceCandidate],
        selectedIdentifier: String?,
        limit: Int = 4
    ) -> [VoiceReplyVoiceCandidate] {
        let uniqueCandidates = supportedCandidates(from: candidates)
        var recommendations: [VoiceReplyVoiceCandidate] = []
        var usedIdentifiers = Set<String>()

        if let selectedIdentifier,
           let selected = uniqueCandidates.first(where: { $0.identifier == selectedIdentifier }) {
            append(selected, to: &recommendations, usedIdentifiers: &usedIdentifiers)
        }

        let bestEnglishVoices = uniqueCandidates
            .sorted(by: sortCandidates)

        for candidate in bestEnglishVoices {
            append(candidate, to: &recommendations, usedIdentifiers: &usedIdentifiers)
            if recommendations.count >= limit { break }
        }

        return Array(recommendations.prefix(limit))
    }

    static func defaultCandidate(
        from candidates: [VoiceReplyVoiceCandidate],
        selectedIdentifier: String?
    ) -> VoiceReplyVoiceCandidate? {
        let candidates = sortedCandidates(
            from: candidates,
            selectedIdentifier: selectedIdentifier
        )

        if let selectedIdentifier,
           let selected = candidates.first(where: { $0.identifier == selectedIdentifier }) {
            return selected
        }

        return candidates.first
    }

    static func sortedCandidates(
        from candidates: [VoiceReplyVoiceCandidate],
        selectedIdentifier: String?
    ) -> [VoiceReplyVoiceCandidate] {
        let uniqueCandidates = supportedCandidates(from: candidates)
        let recommended = recommendedCandidates(
            from: uniqueCandidates,
            selectedIdentifier: selectedIdentifier
        )
        let recommendedIdentifiers = Set(recommended.map(\.identifier))
        let remaining = uniqueCandidates
            .filter { !recommendedIdentifiers.contains($0.identifier) }
            .sorted(by: sortCandidates)

        return recommended + remaining
    }

    static func recommendedVoices(
        from voices: [AVSpeechSynthesisVoice],
        selectedIdentifier: String?,
        limit: Int = 4
    ) -> [AVSpeechSynthesisVoice] {
        let lookup = voiceLookup(from: voices)
        return recommendedCandidates(
            from: voices.map(VoiceReplyVoiceCandidate.init),
            selectedIdentifier: selectedIdentifier,
            limit: limit
        ).compactMap { lookup[$0.identifier] }
    }

    static func defaultVoice(
        from voices: [AVSpeechSynthesisVoice],
        selectedIdentifier: String?
    ) -> AVSpeechSynthesisVoice? {
        let lookup = voiceLookup(from: voices)
        return defaultCandidate(
            from: voices.map(VoiceReplyVoiceCandidate.init),
            selectedIdentifier: selectedIdentifier
        ).flatMap { lookup[$0.identifier] }
    }

    static func sortedVoices(
        from voices: [AVSpeechSynthesisVoice],
        selectedIdentifier: String?
    ) -> [AVSpeechSynthesisVoice] {
        let lookup = voiceLookup(from: voices)
        return sortedCandidates(
            from: voices.map(VoiceReplyVoiceCandidate.init),
            selectedIdentifier: selectedIdentifier
        ).compactMap { lookup[$0.identifier] }
    }

    private static func voiceLookup(
        from voices: [AVSpeechSynthesisVoice]
    ) -> [String: AVSpeechSynthesisVoice] {
        var lookup: [String: AVSpeechSynthesisVoice] = [:]
        for voice in voices where lookup[voice.identifier] == nil {
            lookup[voice.identifier] = voice
        }
        return lookup
    }

    static func isSupportedLanguage(_ language: String) -> Bool {
        indiaLanguagePrefixes.contains { language.hasPrefix($0) } || language.hasPrefix("en-US")
    }

    static func isSupportedVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        isSupportedLanguage(voice.language) && supportedVoiceNames.contains(voice.name)
    }

    private static func supportedCandidates(
        from candidates: [VoiceReplyVoiceCandidate]
    ) -> [VoiceReplyVoiceCandidate] {
        uniqueCandidates(from: candidates)
            .filter { isSupportedLanguage($0.language) }
            .filter { supportedVoiceNames.contains($0.name) }
    }

    private static func uniqueCandidates(
        from candidates: [VoiceReplyVoiceCandidate]
    ) -> [VoiceReplyVoiceCandidate] {
        var seenIdentifiers = Set<String>()
        return candidates.filter { seenIdentifiers.insert($0.identifier).inserted }
    }

    private static func append(
        _ candidate: VoiceReplyVoiceCandidate,
        to recommendations: inout [VoiceReplyVoiceCandidate],
        usedIdentifiers: inout Set<String>
    ) {
        guard usedIdentifiers.insert(candidate.identifier).inserted else { return }
        recommendations.append(candidate)
    }

    private static func sortCandidates(
        lhs: VoiceReplyVoiceCandidate,
        rhs: VoiceReplyVoiceCandidate
    ) -> Bool {
        let lhsPreferredIndex = preferredDefaultVoiceNames.firstIndex(of: lhs.name) ?? Int.max
        let rhsPreferredIndex = preferredDefaultVoiceNames.firstIndex(of: rhs.name) ?? Int.max
        if lhsPreferredIndex != rhsPreferredIndex {
            return lhsPreferredIndex < rhsPreferredIndex
        }
        if lhs.qualityRank != rhs.qualityRank {
            return lhs.qualityRank < rhs.qualityRank
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
