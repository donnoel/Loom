import Foundation

nonisolated struct ChatTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var prompt: String
}

nonisolated enum ChatTemplateLibrary {
    static let defaultTemplates: [ChatTemplate] = [
        ChatTemplate(
            id: "plan",
            title: "Plan",
            prompt: "Help me make a clear plan. Include the goal, the first few steps, and anything I should watch out for."
        ),
        ChatTemplate(
            id: "debug",
            title: "Debug",
            prompt: "Help me debug this. Ask for anything missing, identify likely causes, and suggest the smallest safe next step."
        ),
        ChatTemplate(
            id: "rewrite",
            title: "Rewrite",
            prompt: "Rewrite this so it is clear, friendly, and easy to understand while preserving the original meaning."
        ),
        ChatTemplate(
            id: "compare",
            title: "Compare",
            prompt: "Compare these options. Show the tradeoffs, best fit, risks, and your recommendation."
        )
    ]

    static func load(userDefaults: UserDefaults = .standard) -> [ChatTemplate] {
        guard let data = userDefaults.data(forKey: LoomPreferenceKeys.chatTemplates),
              let decoded = try? JSONDecoder().decode([ChatTemplate].self, from: data) else {
            return defaultTemplates
        }

        let normalized = normalizedTemplates(decoded)
        return normalized.isEmpty ? defaultTemplates : normalized
    }

    @discardableResult
    static func save(_ templates: [ChatTemplate], userDefaults: UserDefaults = .standard) -> [ChatTemplate] {
        let normalized = normalizedTemplates(templates)
        if let data = try? JSONEncoder().encode(normalized) {
            userDefaults.set(data, forKey: LoomPreferenceKeys.chatTemplates)
        }
        return normalized
    }

    @discardableResult
    static func reset(userDefaults: UserDefaults = .standard) -> [ChatTemplate] {
        userDefaults.removeObject(forKey: LoomPreferenceKeys.chatTemplates)
        return defaultTemplates
    }

    private static func normalizedTemplates(_ templates: [ChatTemplate]) -> [ChatTemplate] {
        let fallbackByID = Dictionary(uniqueKeysWithValues: defaultTemplates.map { ($0.id, $0) })

        return templates.compactMap { template in
            let fallback = fallbackByID[template.id]
            guard fallback != nil || !template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let title = template.title.nonEmptyTrimmed ?? fallback?.title
            let prompt = template.prompt.nonEmptyTrimmed ?? fallback?.prompt
            guard let title, let prompt else { return nil }

            return ChatTemplate(
                id: template.id.trimmingCharacters(in: .whitespacesAndNewlines),
                title: title,
                prompt: prompt
            )
        }
    }
}
