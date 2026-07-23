import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    private let store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(LoomPreferenceKeys.statusAutoRefreshEnabled)
    private var statusAutoRefreshEnabled: Bool = true

    @AppStorage(LoomPreferenceKeys.modelsAutoCheckEnabled)
    private var modelsAutoCheckEnabled: Bool = true

    @AppStorage(LoomPreferenceKeys.voiceReplyVoiceIdentifier)
    private var voiceReplyVoiceIdentifier: String = ""

    @State private var previewSynthesizer = AVSpeechSynthesizer()
    @State private var isShowingDeleteAllConfirmation: Bool = false
    @State private var chatTemplates: [ChatTemplate] = ChatTemplateLibrary.load()

    private var sessionsRootURL: URL? {
        try? LoomPaths.sessionsRoot()
    }

    init(store: SessionStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                automationCard
                voiceRepliesCard
                chatTemplatesCard
                localDataCard
                dangerCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.settings")
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete all sessions?",
            isPresented: $isShowingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all local sessions and cannot be undone.")
        }
        .onDisappear {
            previewSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(LoomTheme.Typography.pageHero)

            Text("Control how Loom stays up to date and where your local session data is stored.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomFeatureCard(.sunset, cornerRadius: 16)
    }

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automation")
                .font(LoomTheme.Typography.sectionTitle)

            Toggle("Refresh local readiness automatically", isOn: $statusAutoRefreshEnabled)
            Toggle("Check model availability automatically", isOn: $modelsAutoCheckEnabled)

            Text("Turn these off if you prefer manual checks while troubleshooting.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var localDataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Data & Privacy")
                .font(LoomTheme.Typography.sectionTitle)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions folder")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                Text(sessionsRootURL?.path ?? "Unavailable")
                    .font(LoomTheme.Typography.monospacedFootnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Open Sessions Folder") {
                guard let url = sessionsRootURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
            .disabled(sessionsRootURL == nil)
            .accessibilityIdentifier("settings.openSessionsFolder")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var voiceRepliesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Replies")
                .font(LoomTheme.Typography.sectionTitle)

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                Picker("Voice", selection: selectedVoiceIdentifier) {
                    if !recommendedVoices.isEmpty {
                        Section("Recommended") {
                            ForEach(recommendedVoices, id: \.identifier) { voice in
                                Text(voiceDisplayName(for: voice))
                                    .tag(voice.identifier)
                            }
                        }
                    }
                    Section("Female Voices") {
                        ForEach(remainingVoices, id: \.identifier) { voice in
                            Text(voiceDisplayName(for: voice))
                                .tag(voice.identifier)
                        }
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("settings.voicePicker")
            }

            Button("Preview Voice") {
                previewVoice()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("settings.previewVoice")

            Text("Choose the female voice Loom uses when reading assistant replies aloud. Lekha is the default when available.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var chatTemplatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat Templates")
                .font(LoomTheme.Typography.sectionTitle)

            ForEach($chatTemplates) { $template in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Template name", text: $template.title)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $template.prompt)
                        .font(LoomTheme.Typography.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 76)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                        .accessibilityLabel("\(template.title) prompt")
                }
            }

            HStack {
                Button("Reset") {
                    chatTemplates = ChatTemplateLibrary.reset()
                    NotificationCenter.default.post(name: .loomChatTemplatesDidChange, object: nil)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save Templates") {
                    chatTemplates = ChatTemplateLibrary.save(chatTemplates)
                    NotificationCenter.default.post(name: .loomChatTemplatesDidChange, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveChatTemplates)
                .accessibilityIdentifier("settings.saveChatTemplates")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Danger Zone")
                .font(LoomTheme.Typography.sectionTitle)

            Text("Delete all sessions from this Mac. This cannot be undone.")
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)

            Button("Delete All Sessions…", role: .destructive) {
                isShowingDeleteAllConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.deleteAllSessions")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        VoiceReplyVoiceCatalog.sortedVoices(
            from: AVSpeechSynthesisVoice.speechVoices(),
            selectedIdentifier: voiceReplyVoiceIdentifier.nonEmptyTrimmed
        )
    }

    private var recommendedVoices: [AVSpeechSynthesisVoice] {
        VoiceReplyVoiceCatalog.recommendedVoices(
            from: availableVoices,
            selectedIdentifier: voiceReplyVoiceIdentifier.nonEmptyTrimmed
        )
    }

    private var remainingVoices: [AVSpeechSynthesisVoice] {
        let recommendedIdentifiers = Set(recommendedVoices.map(\.identifier))
        return availableVoices.filter { !recommendedIdentifiers.contains($0.identifier) }
    }

    private var selectedVoiceIdentifier: Binding<String> {
        Binding(
            get: {
                guard let identifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed else {
                    return defaultVoiceIdentifier
                }
                guard let voice = AVSpeechSynthesisVoice(identifier: identifier),
                      VoiceReplyVoiceCatalog.isSupportedVoice(voice) else {
                    return defaultVoiceIdentifier
                }
                return identifier
            },
            set: { newIdentifier in
                if newIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    voiceReplyVoiceIdentifier = defaultVoiceIdentifier
                } else {
                    voiceReplyVoiceIdentifier = newIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        )
    }

    private var defaultVoiceIdentifier: String {
        VoiceReplyVoiceCatalog.defaultVoice(
            from: AVSpeechSynthesisVoice.speechVoices(),
            selectedIdentifier: nil
        )?.identifier ?? ""
    }

    private var canSaveChatTemplates: Bool {
        chatTemplates.allSatisfy { template in
            template.title.nonEmptyTrimmed != nil && template.prompt.nonEmptyTrimmed != nil
        }
    }

    private func localizedLanguageName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func voiceDisplayName(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(localizedLanguageName(for: voice.language)))"
    }

    private func previewVoice() {
        let utterance = AVSpeechUtterance(string: VoiceReplyPreferences.previewText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        if let identifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed,
           let configuredVoice = AVSpeechSynthesisVoice(identifier: identifier),
           VoiceReplyVoiceCatalog.isSupportedVoice(configuredVoice) {
            utterance.voice = configuredVoice
        } else {
            utterance.voice = VoiceReplyVoiceCatalog.defaultVoice(
                from: AVSpeechSynthesisVoice.speechVoices(),
                selectedIdentifier: nil
            )
        }

        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance)
    }

    private func deleteAllSessions() {
        Task {
            try? await store.deleteAllSessions()
            NotificationCenter.default.post(name: .loomSessionsDidChange, object: nil)
        }
    }
}
